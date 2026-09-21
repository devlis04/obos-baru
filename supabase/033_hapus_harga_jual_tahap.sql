-- Hapus harga_jual_order/packed/actual. Harga baris = strata(harga_jual, qty grup).
-- Jalankan SETELAH 032. Boleh diulang.

ALTER TABLE public.transaksi_items
  DROP CONSTRAINT IF EXISTS transaksi_items_order_chk;
ALTER TABLE public.transaksi_items
  DROP CONSTRAINT IF EXISTS transaksi_items_packed_chk;
ALTER TABLE public.transaksi_items
  DROP CONSTRAINT IF EXISTS transaksi_items_actual_chk;

ALTER TABLE public.transaksi_items DROP COLUMN IF EXISTS harga_jual_order CASCADE;
ALTER TABLE public.transaksi_items DROP COLUMN IF EXISTS harga_jual_packed CASCADE;
ALTER TABLE public.transaksi_items DROP COLUMN IF EXISTS harga_jual_actual CASCADE;

ALTER TABLE public.transaksi_items
  ADD CONSTRAINT transaksi_items_order_chk CHECK (qty_order >= 0);
ALTER TABLE public.transaksi_items
  ADD CONSTRAINT transaksi_items_packed_chk CHECK (
    qty_packed IS NULL OR qty_packed >= 0
  );
ALTER TABLE public.transaksi_items
  ADD CONSTRAINT transaksi_items_actual_chk CHECK (
    qty_actual IS NULL OR qty_actual >= 0
  );

CREATE OR REPLACE VIEW public.v_transaksi_item AS
SELECT
  z.*,
  z.qty_order * z.harga_jual_order AS subtotal_jual_order,
  CASE
    WHEN z.qty_packed IS NULL THEN NULL
    ELSE z.qty_packed * z.harga_jual_packed
  END AS subtotal_jual_packed,
  CASE
    WHEN z.qty_actual IS NULL THEN NULL
    ELSE z.qty_actual * z.harga_jual_actual
  END AS subtotal_jual_actual
FROM (
  SELECT
    i.id,
    i.id_transaksi,
    i.id_barang,
    i.id_grup,
    i.nama_barang,
    i.harga_beli,
    i.harga_jual,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.subtotal_beli_order,
    i.subtotal_beli_packed,
    i.subtotal_beli_actual,
    i.min_strat_1,
    i.jual_strat_1,
    i.min_strat_2,
    i.jual_strat_2,
    i.min_strat_3,
    i.jual_strat_3,
    i.min_strat_4,
    i.jual_strat_4,
    i.min_strat_5,
    i.jual_strat_5,
    public.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(i.qty_order) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5
    ) AS harga_jual_order,
    CASE WHEN i.qty_packed IS NULL THEN NULL ELSE public.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(COALESCE(i.qty_packed, 0)) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5
    ) END AS harga_jual_packed,
    CASE WHEN i.qty_actual IS NULL THEN NULL ELSE public.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(COALESCE(i.qty_actual, 0)) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5
    ) END AS harga_jual_actual
  FROM public.transaksi_items i
  WINDOW w AS (
    PARTITION BY i.id_transaksi,
      COALESCE(NULLIF(btrim(i.id_grup), ''), i.id_barang)
  )
) z;

GRANT SELECT ON public.v_transaksi_item TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.sales_isi_item_order(p_id text, p_items jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  n integer;
BEGIN
  INSERT INTO public.transaksi_items (
    id_transaksi,
    id_barang,
    id_grup,
    nama_barang,
    harga_beli,
    harga_jual,
    qty_order,
    min_strat_1,
    jual_strat_1,
    min_strat_2,
    jual_strat_2,
    min_strat_3,
    jual_strat_3,
    min_strat_4,
    jual_strat_4,
    min_strat_5,
    jual_strat_5
  )
  WITH pesan AS (
    SELECT
      btrim(e->>'id_barang') AS id_barang,
      SUM((e->>'qty')::integer) AS qty
    FROM jsonb_array_elements(p_items) AS e
    WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
      AND COALESCE((e->>'qty')::integer, 0) > 0
    GROUP BY 1
  )
  SELECT
    p_id,
    p.id_barang,
    NULLIF(btrim(COALESCE(b.id_grup, '')), ''),
    b.nama_barang,
    COALESCE(b.harga_beli, 0),
    COALESCE(b.harga_jual, 0),
    p.qty,
    COALESCE(b.min_strat_1, 0),
    COALESCE(b.jual_strat_1, 0),
    COALESCE(b.min_strat_2, 0),
    COALESCE(b.jual_strat_2, 0),
    COALESCE(b.min_strat_3, 0),
    COALESCE(b.jual_strat_3, 0),
    COALESCE(b.min_strat_4, 0),
    COALESCE(b.jual_strat_4, 0),
    COALESCE(b.min_strat_5, 0),
    COALESCE(b.jual_strat_5, 0)
  FROM pesan p
  JOIN public.barang b ON b.id_barang = p.id_barang;

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN COALESCE(n, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_pack_nota(
  p_id_transaksi text,
  p_baris jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_status text;
  v_actual timestamptz;
  v_cap bigint;
  v_tutup boolean;
  v_buku bigint;
  v_tgl date;
  v_item jsonb;
  v_sku text;
  v_qty integer;
  v_sisa numeric;
  v_maks numeric;
  v_lama integer;
  v_delta integer;
  v_jual integer;
  v_beli integer;
  v_nama text;
  v_grup text;
  v_min1 integer; v_jual1 integer;
  v_min2 integer; v_jual2 integer;
  v_min3 integer; v_jual3 integer;
  v_min4 integer; v_jual4 integer;
  v_min5 integer; v_jual5 integer;
  v_ada boolean;
  v_ada_isi boolean;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.gudang_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  IF btrim(COALESCE(p_id_transaksi, '')) = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar packing wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_actual, v_cap
  FROM public.transaksi t
  WHERE t.id_transaksi = p_id_transaksi
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada.';
  END IF;
  IF v_status = 'batal' THEN
    RAISE EXCEPTION 'Nota batal tidak bisa di packing.';
  END IF;
  IF v_actual IS NOT NULL OR v_status = 'terkirim' THEN
    RAISE EXCEPTION 'Nota sudah terkunci. Packing tidak bisa diubah.';
  END IF;

  IF v_cap IS NOT NULL THEN
    SELECT b.ditutup, b.tanggal INTO v_tutup, v_tgl
    FROM public.setoran_buku b
    WHERE b.id = v_cap;
    IF COALESCE(v_tutup, true) THEN
      RAISE EXCEPTION 'Nota sudah di buku tertutup. Packing tidak bisa diubah.';
    END IF;
    v_buku := v_cap;
  ELSE
    v_buku := public.setoran_buka_jika_perlu();
    SELECT b.tanggal INTO v_tgl FROM public.setoran_buku b WHERE b.id = v_buku;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_sku := btrim(COALESCE(v_item ->> 'id_barang', ''));
    IF v_sku = '' THEN
      CONTINUE;
    END IF;
    v_qty := COALESCE((v_item ->> 'qty_packed')::integer, 0);
    IF v_qty < 0 THEN
      RAISE EXCEPTION 'Qty packing tidak boleh negatif (SKU %).', v_sku;
    END IF;

    SELECT
      b.id_barang,
      b.nama_barang,
      COALESCE(b.harga_jual, 0),
      GREATEST(COALESCE(b.harga_beli, 0), 0),
      b.id_grup,
      b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
      b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
      b.min_strat_5, b.jual_strat_5
    INTO
      v_sku, v_nama, v_jual, v_beli, v_grup,
      v_min1, v_jual1, v_min2, v_jual2,
      v_min3, v_jual3, v_min4, v_jual4,
      v_min5, v_jual5
    FROM public.barang b
    WHERE lower(b.id_barang) = lower(v_sku)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SKU % tidak ada di barang.', v_sku;
    END IF;

    SELECT true, i.qty_packed INTO v_ada, v_lama
    FROM public.transaksi_items i
    WHERE i.id_transaksi = p_id_transaksi
      AND i.id_barang = v_sku
    FOR UPDATE;
    IF NOT FOUND THEN
      v_ada := false;
      v_lama := 0;
      IF v_qty <= 0 THEN
        CONTINUE;
      END IF;
    END IF;

    INSERT INTO public.stok_opname (
      id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
    )
    SELECT
      v_buku,
      v_tgl,
      v_sku,
      v_nama,
      GREATEST(COALESCE(b.stok, 0), 0),
      0
    FROM public.barang b
    WHERE b.id_barang = v_sku
      AND NOT EXISTS (
        SELECT 1
        FROM public.stok_opname so
        WHERE so.id_setoran_buku = v_buku
          AND so.id_barang = v_sku
      );

    SELECT so.stok_hitung INTO v_sisa
    FROM public.stok_opname so
    WHERE so.id_setoran_buku = v_buku
      AND so.id_barang = v_sku
    FOR UPDATE;

    v_sisa := COALESCE(v_sisa, 0);
    v_maks := v_sisa + COALESCE(v_lama, 0);
    IF v_maks < COALESCE(v_lama, 0) THEN
      v_maks := COALESCE(v_lama, 0);
    END IF;
    IF v_qty > v_maks THEN
      RAISE EXCEPTION 'Sisa stok tidak cukup (SKU %).', v_sku;
    END IF;

    IF NOT v_ada THEN
      INSERT INTO public.transaksi_items (
        id_transaksi, id_barang, id_grup, nama_barang, harga_beli, harga_jual,
        qty_order, qty_packed,
        min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
        min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
        min_strat_5, jual_strat_5
      ) VALUES (
        p_id_transaksi, v_sku, v_grup, v_nama, v_beli, v_jual,
        0, v_qty,
        COALESCE(v_min1, 0), COALESCE(v_jual1, 0),
        COALESCE(v_min2, 0), COALESCE(v_jual2, 0),
        COALESCE(v_min3, 0), COALESCE(v_jual3, 0),
        COALESCE(v_min4, 0), COALESCE(v_jual4, 0),
        COALESCE(v_min5, 0), COALESCE(v_jual5, 0)
      );
    END IF;

    v_delta := v_qty - COALESCE(v_lama, 0);
    IF v_delta <> 0 THEN
      UPDATE public.stok_opname
      SET
        qty_packed = qty_packed + v_delta,
        stok_fisik = CASE
          WHEN stok_fisik IS NULL THEN NULL
          ELSE GREATEST(0, stok_fisik - v_delta)
        END
      WHERE id_setoran_buku = v_buku
        AND id_barang = v_sku;
    END IF;

    IF v_ada THEN
      UPDATE public.transaksi_items
      SET qty_packed = v_qty
      WHERE id_transaksi = p_id_transaksi
        AND id_barang = v_sku;
    END IF;
  END LOOP;

  UPDATE public.transaksi_items i
  SET qty_packed = 0
  WHERE i.id_transaksi = p_id_transaksi
    AND i.qty_packed IS NULL;

  SELECT EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    WHERE i.id_transaksi = p_id_transaksi
      AND COALESCE(i.qty_packed, 0) > 0
  ) INTO v_ada_isi;

  IF v_ada_isi THEN
    UPDATE public.transaksi
    SET
      waktu_packed = COALESCE(waktu_packed, clock_timestamp()),
      status = CASE WHEN status = 'diproses' THEN 'dikirim' ELSE status END,
      id_setoran_buku = COALESCE(id_setoran_buku, v_buku)
    WHERE id_transaksi = p_id_transaksi;
  ELSE
    UPDATE public.transaksi
    SET
      status = 'batal',
      pending = false,
      waktu_packed = COALESCE(waktu_packed, clock_timestamp()),
      id_setoran_buku = COALESCE(id_setoran_buku, v_buku)
    WHERE id_transaksi = p_id_transaksi;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_kunci_nota(
  p_id_transaksi text,
  p_baris jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_status text;
  v_sales text[];
  v_item jsonb;
  v_sku text;
  v_qty integer;
  v_ada_isi boolean;
  rec record;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  v_sales := public.pengirim_rute_sales();
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar tebus wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  DROP TABLE IF EXISTS pengirim_qty_baru;

  SELECT t.status INTO v_status
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_status IS DISTINCT FROM 'dikirim' THEN
    RAISE EXCEPTION 'Nota sudah terkunci atau belum dikirim.';
  END IF;

  CREATE TEMP TABLE pengirim_qty_baru (
    id_barang text PRIMARY KEY,
    qty integer NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_sku := btrim(COALESCE(v_item ->> 'id_barang', ''));
    IF v_sku = '' THEN
      CONTINUE;
    END IF;
    v_qty := COALESCE((v_item ->> 'qty_actual')::integer, 0);
    IF v_qty < 0 THEN
      RAISE EXCEPTION 'Qty tebus tidak boleh negatif (SKU %).', v_sku;
    END IF;
    INSERT INTO pengirim_qty_baru (id_barang, qty)
    VALUES (v_sku, v_qty)
    ON CONFLICT (id_barang) DO UPDATE SET qty = EXCLUDED.qty;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pengirim_qty_baru n
    LEFT JOIN public.transaksi_items i
      ON i.id_transaksi = v_id
     AND i.id_barang = n.id_barang
    WHERE i.id_barang IS NULL
  ) THEN
    RAISE EXCEPTION 'Ada SKU yang tidak ada di nota.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
      AND n.id_barang IS NULL
      AND COALESCE(i.qty_packed, 0) > 0
  ) THEN
    RAISE EXCEPTION 'Semua SKU packed harus diisi qty tebus.';
  END IF;

  FOR rec IN
    SELECT
      i.id_barang,
      COALESCE(n.qty, 0) AS qty,
      COALESCE(i.qty_packed, 0) AS qty_packed
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
  LOOP
    IF rec.qty > rec.qty_packed THEN
      RAISE EXCEPTION 'Qty tebus melebihi packed (SKU %).', rec.id_barang;
    END IF;

    UPDATE public.transaksi_items
    SET qty_actual = rec.qty
    WHERE id_transaksi = v_id
      AND id_barang = rec.id_barang;

    IF rec.qty_packed - rec.qty > 0 THEN
      PERFORM public.barang_masuk_geser_stok(
        rec.id_barang,
        rec.qty_packed - rec.qty
      );
    END IF;
  END LOOP;

  UPDATE public.transaksi_items
  SET qty_actual = 0
  WHERE id_transaksi = v_id
    AND qty_actual IS NULL;

  SELECT EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
      AND COALESCE(i.qty_actual, 0) > 0
  ) INTO v_ada_isi;

  UPDATE public.transaksi
  SET
    pending = false,
    waktu_actual = clock_timestamp(),
    status = CASE WHEN v_ada_isi THEN 'terkirim' ELSE 'batal' END
  WHERE id_transaksi = v_id
    AND status = 'dikirim';
END;
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
BEGIN
  IF auth.uid() IS NULL OR NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM public.transaksi t
    WHERE (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
      AND t.status IS DISTINCT FROM 'batal'
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
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
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
  WHERE (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
    AND t.rute = p_rute
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_nota_item(p_id_transaksi text)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  qty_order integer,
  qty_packed integer,
  qty_actual integer,
  harga_jual_order integer,
  harga_beli_order integer,
  harga_jual_packed integer,
  harga_beli_packed integer,
  harga_jual_actual integer,
  harga_beli_actual integer,
  subtotal_order integer,
  subtotal_packed integer,
  subtotal_actual integer,
  id_grup_kunci text,
  harga_jual_kunci integer,
  min_strat_1 integer,
  jual_strat_1 integer,
  min_strat_2 integer,
  jual_strat_2 integer,
  min_strat_3 integer,
  jual_strat_3 integer,
  min_strat_4 integer,
  jual_strat_4 integer,
  min_strat_5 integer,
  jual_strat_5 integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF btrim(COALESCE(p_id_transaksi, '')) = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;

  RETURN QUERY
  SELECT
    i.id_barang,
    i.nama_barang,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.harga_jual_order,
    i.harga_beli,
    i.harga_jual_packed,
    i.harga_beli,
    i.harga_jual_actual,
    i.harga_beli,
    i.subtotal_jual_order,
    i.subtotal_jual_packed,
    i.subtotal_jual_actual,
    i.id_grup,
    i.harga_jual,
    i.min_strat_1,
    i.jual_strat_1,
    i.min_strat_2,
    i.jual_strat_2,
    i.min_strat_3,
    i.jual_strat_3,
    i.min_strat_4,
    i.jual_strat_4,
    i.min_strat_5,
    i.jual_strat_5
  FROM public.v_transaksi_item i
  WHERE i.id_transaksi = p_id_transaksi
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
$$;

DROP FUNCTION IF EXISTS public.pengirim_nota_item(text);

CREATE OR REPLACE FUNCTION public.pengirim_nota_item(p_id_transaksi text)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  id_grup text,
  harga_jual integer,
  qty_order integer,
  qty_packed integer,
  qty_actual integer,
  harga_jual_order integer,
  harga_jual_packed integer,
  harga_jual_actual integer,
  subtotal_order integer,
  subtotal_packed integer,
  subtotal_actual integer,
  min_strat_1 integer,
  jual_strat_1 integer,
  min_strat_2 integer,
  jual_strat_2 integer,
  min_strat_3 integer,
  jual_strat_3 integer,
  min_strat_4 integer,
  jual_strat_4 integer,
  min_strat_5 integer,
  jual_strat_5 integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_sales text[];
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();
  IF NOT EXISTS (
    SELECT 1 FROM public.transaksi t
    WHERE t.id_transaksi = v_id
      AND t.rute = ANY (v_sales)
  ) THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;

  RETURN QUERY
  SELECT
    i.id_barang,
    i.nama_barang,
    i.id_grup,
    i.harga_jual,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.harga_jual_order,
    i.harga_jual_packed,
    i.harga_jual_actual,
    i.subtotal_jual_order,
    i.subtotal_jual_packed,
    i.subtotal_jual_actual,
    i.min_strat_1,
    i.jual_strat_1,
    i.min_strat_2,
    i.jual_strat_2,
    i.min_strat_3,
    i.jual_strat_3,
    i.min_strat_4,
    i.jual_strat_4,
    i.min_strat_5,
    i.jual_strat_5
  FROM public.v_transaksi_item i
  WHERE i.id_transaksi = v_id
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
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
  v_hari date;
  v_today date;
  v_id_buku bigint;
  v_id_buka bigint;
  v_tgl_buka date;
  v_grup text;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_sales := public.pengirim_rute_sales();
  v_hari := p_tanggal;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_grup := public.pengirim_grup_rute(public.pengirim_rute_saya());
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

  SELECT b.id, b.tanggal INTO v_id_buka, v_tgl_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  LIMIT 1;
  IF v_id_buka IS NOT NULL AND (v_hari = v_today OR v_hari = v_tgl_buka) THEN
    v_id_buku := v_id_buka;
  ELSE
    SELECT b.id INTO v_id_buku
    FROM public.setoran_buku b
    WHERE b.tanggal = v_hari
    ORDER BY b.id DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND (
        (t.status = 'dikirim' AND v_hari = v_today)
        OR (
          t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND CASE
            WHEN v_id_buku IS NOT NULL THEN t.id_setoran_buku = v_id_buku
            ELSE (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
          END
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
    h.wajib_kunci,
    h.ada_dikirim,
    h.ada_pending,
    h.ada_batal,
    h.ada_terkirim,
    k.waktu_masuk,
    k.waktu_keluar
  FROM hitung h
  LEFT JOIN public.pelanggan pl ON pl.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.kunjungan_pengirim k
    ON k.id_pelanggan = h.id_pelanggan
   AND k.rute_pengirim = v_grup
   AND k.tanggal = v_hari
  ORDER BY lower(h.nama_pelanggan), h.id_pelanggan;
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
  omset_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sales text[];
  v_hari date;
  v_today date;
  v_id text;
  v_id_buku bigint;
  v_id_buka bigint;
  v_tgl_buka date;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  IF p_tanggal IS NULL OR v_id = '' THEN
    RAISE EXCEPTION 'Tanggal dan toko wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();
  v_hari := p_tanggal;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;

  SELECT b.id, b.tanggal INTO v_id_buka, v_tgl_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  LIMIT 1;
  IF v_id_buka IS NOT NULL AND (v_hari = v_today OR v_hari = v_tgl_buka) THEN
    v_id_buku := v_id_buka;
  ELSE
    SELECT b.id INTO v_id_buku
    FROM public.setoran_buku b
    WHERE b.tanggal = v_hari
    ORDER BY b.id DESC
    LIMIT 1;
  END IF;

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
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  WHERE t.rute = ANY (v_sales)
    AND t.id_pelanggan = v_id
    AND t.waktu_packed IS NOT NULL
    AND (
      (t.status = 'dikirim' AND v_hari = v_today)
      OR (
        t.status IN ('terkirim', 'batal')
        AND t.waktu_actual IS NOT NULL
        AND CASE
          WHEN v_id_buku IS NOT NULL THEN t.id_setoran_buku = v_id_buku
          ELSE (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
        END
      )
    )
  GROUP BY
    t.id_transaksi, t.status, t.pending, t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_nota_item(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_item(text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_kunci_nota(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kunci_nota(text, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
