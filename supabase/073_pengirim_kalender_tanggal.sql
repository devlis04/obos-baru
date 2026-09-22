-- Kalender pengirim: tanggal yang dipilih = data hari itu, bukan dialihkan ke buku terbuka.
-- Jalankan SETELAH 072. Boleh diulang.

CREATE OR REPLACE FUNCTION public.pengirim_nota_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_order timestamptz,
  p_waktu_actual timestamptz,
  p_tanggal_lihat date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (
      p_id_buku IS NOT NULL
      AND p_id_setoran_buku = p_id_buku
    )
    OR (
      p_tgl IS NOT NULL
      AND p_waktu_order IS NOT NULL
      AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      AND p_id_setoran_buku IS NULL
      AND p_status = 'dikirim'
      AND (p_id_buku IS NULL OR coalesce(p_hidup, false))
    )
    OR (
      p_id_buku IS NULL
      AND p_id_setoran_buku IS NULL
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    );
$$;

CREATE OR REPLACE FUNCTION public.pengirim_kartu_toko(p_tanggal date)
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
  v_grup := public.pengirim_grup_rute(public.pengirim_rute_saya());
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

  SELECT x.id, x.tanggal, x.hidup INTO v_id_buku, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  RETURN QUERY
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND public.pengirim_nota_ikut_buku(
        v_id_buku, v_tgl, v_hidup, t.id_setoran_buku,
        t.status, t.waktu_order, t.waktu_actual, p_tanggal
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
   AND k.tanggal = p_tanggal
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
  v_tgl date;
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

  SELECT x.id, x.tanggal, x.hidup INTO v_id_buku, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

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
      AND public.pengirim_nota_ikut_buku(
        v_id_buku, v_tgl, v_hidup, t.id_setoran_buku,
        t.status, t.waktu_order, t.waktu_actual, p_tanggal
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

CREATE OR REPLACE FUNCTION public.pengirim_nota_toko(
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
  v_tgl date;
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

  SELECT x.id, x.tanggal, x.hidup INTO v_id_buku, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

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
    AND public.pengirim_nota_ikut_buku(
      v_id_buku, v_tgl, v_hidup, t.id_setoran_buku,
      t.status, t.waktu_order, t.waktu_actual, p_tanggal
    )
  GROUP BY
    t.id_transaksi, t.status, t.pending, t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date)
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

NOTIFY pgrst, 'reload schema';
