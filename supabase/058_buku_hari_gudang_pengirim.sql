-- Gudang + pengirim: daftar ikut buku (default terbuka),
-- kalender = pilih buku tanggal itu. Boleh diulang.

CREATE OR REPLACE FUNCTION public.setoran_buku_untuk_hari(p_tanggal date DEFAULT NULL)
RETURNS TABLE (
  id bigint,
  tanggal date,
  ditutup boolean,
  hidup boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hari date;
  v_today date;
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_buka bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;

  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_hari := COALESCE(p_tanggal, v_today);

  SELECT b.id INTO v_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  IF p_tanggal IS NULL THEN
    IF v_buka IS NULL THEN
      RETURN;
    END IF;
    SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_buka;
    id := v_id;
    tanggal := v_tgl;
    ditutup := COALESCE(v_tutup, false);
    hidup := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_buka IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_buka;
    IF v_hari = v_today OR v_hari = v_tgl THEN
      id := v_id;
      tanggal := v_tgl;
      ditutup := COALESCE(v_tutup, false);
      hidup := true;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.tanggal = v_hari
  ORDER BY b.id DESC
  LIMIT 1;
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  id := v_id;
  tanggal := v_tgl;
  ditutup := COALESCE(v_tutup, false);
  hidup := (v_buka IS NOT NULL AND v_id = v_buka);
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_buku_hari(p_tanggal date)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT x.id FROM public.setoran_buku_untuk_hari(p_tanggal) x;
$$;

CREATE OR REPLACE FUNCTION public.gudang_kartu_rute(p_tanggal date)
RETURNS TABLE (
  rute text,
  nama_sales text,
  jumlah_nota integer,
  sudah_siap integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_hidup boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  IF v_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM public.transaksi t
    WHERE t.status IS DISTINCT FROM 'batal'
      AND (
        t.id_setoran_buku = v_id
        OR (v_hidup AND t.id_setoran_buku IS NULL)
      )
  ),
  hitung AS (
    SELECT
      n.rute,
      count(DISTINCT n.id_transaksi)::integer AS jumlah_nota,
      count(DISTINCT n.id_transaksi) FILTER (
        WHERE n.status IN ('dikirim', 'terkirim') OR n.waktu_packed IS NOT NULL
      )::integer AS sudah_siap,
      coalesce(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS omset_packed,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint AS laba_order,
      coalesce(sum(
        CASE
          WHEN i.qty_packed IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
        END
      ), 0)::bigint AS laba_packed,
      coalesce(sum(
        CASE
          WHEN i.qty_actual IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
        END
      ), 0)::bigint AS laba_actual
    FROM nota n
    LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.rute
  )
  SELECT
    h.rute,
    coalesce(
      (
        SELECT u.nama
        FROM public.users u
        WHERE u.peran = 'sales'
          AND u.rute = h.rute
        LIMIT 1
      ),
      h.rute
    ),
    h.jumlah_nota,
    h.sudah_siap,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.laba_order,
    h.laba_packed,
    h.laba_actual
  FROM hitung h
  ORDER BY h.rute;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_nota_rute(p_tanggal date, p_rute text)
RETURNS TABLE (
  id_transaksi text,
  id_pelanggan text,
  nama_pelanggan text,
  status text,
  pending boolean,
  waktu_order timestamptz,
  waktu_packed timestamptz,
  waktu_actual timestamptz,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_hidup boolean;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;

  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  IF v_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    t.id_transaksi,
    t.id_pelanggan,
    t.nama_pelanggan,
    t.status,
    t.pending,
    t.waktu_order,
    t.waktu_packed,
    t.waktu_actual,
    coalesce(sum(i.subtotal_jual_order), 0)::bigint,
    coalesce(sum(i.subtotal_jual_packed), 0)::bigint,
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint,
    coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_packed IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
      END
    ), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_actual IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
      END
    ), 0)::bigint
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  WHERE t.rute = p_rute
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
    AND (
      t.id_setoran_buku = v_id
      OR (v_hidup AND t.id_setoran_buku IS NULL)
    )
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.pengirim_kartu_toko(date);
CREATE FUNCTION public.pengirim_kartu_toko(p_tanggal date)
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute_sales text,
  latitude double precision,
  longitude double precision,
  jumlah_nota integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_retur bigint,
  wajib_kunci integer,
  ada_dikirim boolean,
  ada_pending boolean,
  ada_batal boolean,
  ada_terkirim boolean,
  waktu_masuk timestamptz,
  waktu_keluar timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sales text[];
  v_today date;
  v_id_buku bigint;
  v_tgl date;
  v_hidup boolean := false;
  v_grup text;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_sales := public.pengirim_rute_sales();
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_grup := public.pengirim_grup_rute(public.pengirim_rute_saya());
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

  SELECT x.id, x.tanggal, x.hidup INTO v_id_buku, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;

  RETURN QUERY
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND (
        (v_id_buku IS NOT NULL AND t.id_setoran_buku = v_id_buku)
        OR (
          v_hidup
          AND t.status = 'dikirim'
          AND t.id_setoran_buku IS NULL
        )
        OR (
          v_id_buku IS NULL
          AND t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
        )
      )
  ),
  hitung AS (
    SELECT
      n.id_pelanggan,
      max(n.nama_pelanggan) AS nama_pelanggan,
      max(n.rute) AS rute_sales,
      count(*)::integer AS jumlah_nota,
      coalesce(sum((
        SELECT coalesce(sum(i.subtotal_jual_order), 0)
        FROM public.v_transaksi_item i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_order,
      coalesce(sum((
        SELECT coalesce(sum(i.subtotal_jual_packed), 0)
        FROM public.v_transaksi_item i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_packed,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN 0
             ELSE (
               SELECT coalesce(sum(i.subtotal_jual_actual), 0)
               FROM public.v_transaksi_item i
               WHERE i.id_transaksi = n.id_transaksi
             )
        END
      ), 0)::bigint AS omset_actual,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN (
          SELECT coalesce(sum(i.subtotal_jual_packed), 0)
          FROM public.v_transaksi_item i
          WHERE i.id_transaksi = n.id_transaksi
        ) ELSE 0 END
      ), 0)::bigint AS omset_batal,
      count(*) FILTER (
        WHERE n.status = 'dikirim' AND NOT n.pending
      )::integer AS wajib_kunci,
      bool_or(n.status = 'dikirim') AS ada_dikirim,
      bool_or(n.pending) AS ada_pending,
      bool_or(n.status = 'batal') AS ada_batal,
      bool_or(n.status = 'terkirim') AS ada_terkirim
    FROM nota n
    GROUP BY n.id_pelanggan
  ),
  retur AS (
    SELECT
      i.id_pelanggan,
      coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS omset_retur
    FROM public.retur_toko i
    WHERE v_id_buku IS NOT NULL
      AND i.id_setoran_buku = v_id_buku
      AND i.rute_pengirim = v_grup
    GROUP BY i.id_pelanggan
  )
  SELECT
    h.id_pelanggan,
    h.nama_pelanggan,
    h.rute_sales,
    pl.latitude,
    pl.longitude,
    h.jumlah_nota,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.omset_batal,
    coalesce(r.omset_retur, 0)::bigint,
    h.wajib_kunci,
    h.ada_dikirim,
    h.ada_pending,
    h.ada_batal,
    h.ada_terkirim,
    k.waktu_masuk,
    k.waktu_keluar
  FROM hitung h
  LEFT JOIN retur r ON r.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.pelanggan pl ON pl.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.kunjungan_pengirim k
    ON k.id_pelanggan = h.id_pelanggan
   AND k.rute_pengirim = v_grup
   AND (
     (v_tgl IS NOT NULL AND k.tanggal = v_tgl)
     OR (v_hidup AND k.tanggal = v_today)
   )
  ORDER BY lower(h.nama_pelanggan), h.id_pelanggan;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_ringkas_hari(p_tanggal date)
RETURNS TABLE (
  jumlah_toko integer,
  jumlah_nota integer,
  wajib_kunci integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_pending bigint,
  omset_retur bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sales text[];
  v_id_buku bigint;
  v_hidup boolean := false;
  v_rute text;
  v_retur bigint := 0;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_sales := public.pengirim_rute_sales();
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

  SELECT x.id, x.hidup INTO v_id_buku, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;

  IF v_id_buku IS NOT NULL AND v_rute IS NOT NULL THEN
    SELECT coalesce(sum(i.qty * i.harga_jual), 0)::bigint
    INTO v_retur
    FROM public.retur_toko i
    WHERE i.id_setoran_buku = v_id_buku
      AND i.rute_pengirim = v_rute;
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND (
        (v_id_buku IS NOT NULL AND t.id_setoran_buku = v_id_buku)
        OR (
          v_hidup
          AND t.status = 'dikirim'
          AND t.id_setoran_buku IS NULL
        )
        OR (
          v_id_buku IS NULL
          AND t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
        )
      )
  ),
  item AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.status,
      n.pending,
      coalesce(sum(i.subtotal_jual_order), 0) AS jual_order,
      coalesce(sum(i.subtotal_jual_packed), 0) AS jual_packed,
      coalesce(sum(i.subtotal_jual_actual), 0) AS jual_actual,
      coalesce(sum(i.subtotal_beli_order), 0) AS beli_order,
      coalesce(sum(i.subtotal_beli_packed), 0) AS beli_packed,
      coalesce(sum(i.subtotal_beli_actual), 0) AS beli_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.id_transaksi, n.id_pelanggan, n.status, n.pending
  )
  SELECT
    count(DISTINCT i.id_pelanggan)::integer,
    count(*)::integer,
    count(*) FILTER (WHERE i.status = 'dikirim' AND NOT i.pending)::integer,
    coalesce(sum(i.jual_order), 0)::bigint,
    coalesce(sum(i.jual_packed), 0)::bigint,
    coalesce(sum(CASE WHEN i.status = 'batal' THEN 0 ELSE i.jual_actual END), 0)::bigint,
    coalesce(sum(CASE WHEN i.status = 'batal' THEN i.jual_packed ELSE 0 END), 0)::bigint,
    coalesce(sum(CASE WHEN i.pending THEN i.jual_packed ELSE 0 END), 0)::bigint,
    v_retur,
    coalesce(sum(i.jual_order - i.beli_order), 0)::bigint,
    coalesce(sum(i.jual_packed - i.beli_packed), 0)::bigint,
    coalesce(sum(
      CASE WHEN i.status = 'batal' THEN 0 ELSE i.jual_actual - i.beli_actual END
    ), 0)::bigint
  FROM item i;
END;
$$;

DROP FUNCTION IF EXISTS public.pengirim_nota_toko(date, text);
CREATE FUNCTION public.pengirim_nota_toko(
  p_tanggal date,
  p_id_pelanggan text
)
RETURNS TABLE (
  id_transaksi text,
  status text,
  pending boolean,
  waktu_order timestamptz,
  waktu_packed timestamptz,
  waktu_actual timestamptz,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sales text[];
  v_id text;
  v_id_buku bigint;
  v_hidup boolean := false;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  IF p_tanggal IS NULL OR v_id = '' THEN
    RAISE EXCEPTION 'Tanggal dan toko wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  SELECT x.id, x.hidup INTO v_id_buku, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;

  RETURN QUERY
  SELECT
    t.id_transaksi,
    t.status,
    t.pending,
    t.waktu_order,
    t.waktu_packed,
    t.waktu_actual,
    coalesce(sum(i.subtotal_jual_order), 0)::bigint,
    coalesce(sum(i.subtotal_jual_packed), 0)::bigint,
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint,
    coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_packed IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
      END
    ), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_actual IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
      END
    ), 0)::bigint
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  WHERE t.rute = ANY (v_sales)
    AND t.id_pelanggan = v_id
    AND t.waktu_packed IS NOT NULL
    AND (
      (v_id_buku IS NOT NULL AND t.id_setoran_buku = v_id_buku)
      OR (
        v_hidup
        AND t.status = 'dikirim'
        AND t.id_setoran_buku IS NULL
      )
      OR (
        v_id_buku IS NULL
        AND t.status IN ('terkirim', 'batal')
        AND t.waktu_actual IS NOT NULL
        AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
      )
    )
  GROUP BY
    t.id_transaksi, t.status, t.pending, t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_retur_toko_simpan(
  p_tanggal date,
  p_id_pelanggan text,
  p_baris jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_today date;
  v_tgl date;
  v_buku bigint;
  v_hidup boolean := false;
  r jsonb;
  v_kode text;
  v_nama text;
  v_qty integer;
  v_harga integer;
  rec record;
BEGIN
  IF NOT public.pengirim_sedang_login() OR p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  SELECT x.id, x.tanggal, x.hidup INTO v_buku, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  IF NOT COALESCE(v_hidup, false) OR v_buku IS NULL THEN
    RAISE EXCEPTION 'Retur hanya bisa dicatat pada buku yang sedang berjalan.';
  END IF;
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  v_id := nullif(btrim(COALESCE(p_id_pelanggan, '')), '');
  IF v_rute IS NULL OR v_id IS NULL THEN
    RETURN false;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_rute), hashtext(v_buku::text));

  IF NOT EXISTS (
    SELECT 1 FROM public.kunjungan_pengirim k
    WHERE k.id_pelanggan = v_id
      AND k.waktu_masuk IS NOT NULL
      AND public.pengirim_grup_rute(k.rute_pengirim) = v_rute
      AND (
        (v_tgl IS NOT NULL AND k.tanggal = v_tgl)
        OR k.tanggal = v_today
      )
  ) THEN
    RAISE EXCEPTION 'Check-in toko dulu sebelum mencatat retur.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RETURN false;
  END IF;

  CREATE TEMP TABLE tmp_retur_baru (
    kode text PRIMARY KEY,
    nama text,
    qty integer,
    harga integer
  ) ON COMMIT DROP;

  FOR r IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_kode := nullif(btrim(COALESCE(r ->> 'kode_barang', '')), '');
    v_nama := btrim(COALESCE(r ->> 'nama_barang', ''));
    BEGIN
      v_qty := GREATEST(COALESCE((r ->> 'qty')::integer, 0), 0);
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;
    BEGIN
      v_harga := GREATEST(COALESCE((r ->> 'harga_jual')::integer, 0), 0);
    EXCEPTION WHEN OTHERS THEN
      v_harga := 0;
    END;
    IF v_kode IS NULL OR v_qty <= 0 THEN
      CONTINUE;
    END IF;
    IF v_nama = '' OR v_harga <= 0 THEN
      SELECT
        CASE WHEN v_nama = '' THEN COALESCE(NULLIF(btrim(b.nama_barang), ''), v_kode) ELSE v_nama END,
        CASE WHEN v_harga <= 0 THEN COALESCE(b.harga_jual, 0) ELSE v_harga END
      INTO v_nama, v_harga
      FROM public.barang b
      WHERE b.id_barang = v_kode;
      v_nama := COALESCE(v_nama, v_kode);
      v_harga := COALESCE(v_harga, 0);
    END IF;
    INSERT INTO tmp_retur_baru (kode, nama, qty, harga)
    VALUES (v_kode, v_nama, v_qty, v_harga)
    ON CONFLICT (kode) DO UPDATE SET
      qty = EXCLUDED.qty,
      nama = EXCLUDED.nama,
      harga = EXCLUDED.harga;
  END LOOP;

  FOR rec IN
    SELECT
      COALESCE(l.kode_barang, n.kode) AS kode,
      COALESCE(l.qty, 0) AS lama,
      COALESCE(n.qty, 0) AS baru
    FROM (
      SELECT kode_barang, qty
      FROM public.retur_toko
      WHERE id_setoran_buku = v_buku
        AND rute_pengirim = v_rute
        AND id_pelanggan = v_id
    ) l
    FULL JOIN tmp_retur_baru n ON n.kode = l.kode_barang
  LOOP
    IF rec.baru > rec.lama THEN
      PERFORM public.stok_catat_retur(rec.kode, rec.baru - rec.lama);
    ELSIF rec.lama > rec.baru THEN
      PERFORM public.stok_catat_retur(rec.kode, rec.baru - rec.lama);
    END IF;
  END LOOP;

  DELETE FROM public.retur_toko
  WHERE id_setoran_buku = v_buku
    AND rute_pengirim = v_rute
    AND id_pelanggan = v_id;

  INSERT INTO public.retur_toko (
    rute_pengirim, id_pelanggan, kode_barang, nama_barang, qty, harga_jual
  )
  SELECT v_rute, v_id, kode, nama, qty, harga
  FROM tmp_retur_baru;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_buku_untuk_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_untuk_hari(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_buku_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_buku_hari(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_kartu_rute(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_kartu_rute(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_rute(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_rute(date, text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_kartu_toko(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kartu_toko(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_ringkas_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_ringkas_hari(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_nota_toko(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_toko(date, text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_retur_toko_simpan(date, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_retur_toko_simpan(date, text, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
