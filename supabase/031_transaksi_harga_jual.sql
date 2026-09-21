-- Kunci harga jual katalog ke transaksi_items (dasar strata).
-- Jalankan SETELAH 030. Boleh diulang.

ALTER TABLE public.transaksi_items
  ADD COLUMN IF NOT EXISTS harga_jual integer;

UPDATE public.transaksi_items i
SET harga_jual = COALESCE(
  (
    SELECT b.harga_jual
    FROM public.barang b
    WHERE b.id_barang = i.id_barang
  ),
  i.harga_jual_order,
  0
)
WHERE i.harga_jual IS NULL OR i.harga_jual = 0;

ALTER TABLE public.transaksi_items
  ALTER COLUMN harga_jual SET DEFAULT 0;

ALTER TABLE public.transaksi_items
  ALTER COLUMN harga_jual SET NOT NULL;

ALTER TABLE public.transaksi_items
  DROP CONSTRAINT IF EXISTS transaksi_items_harga_jual_chk;
ALTER TABLE public.transaksi_items
  ADD CONSTRAINT transaksi_items_harga_jual_chk CHECK (harga_jual >= 0);

COMMENT ON COLUMN public.transaksi_items.harga_jual IS
  'Harga jual katalog terkunci saat salesman simpan. Dasar strata; order/packed/actual hasil hitung.';

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
    harga_jual_order,
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
  ),
  baris AS (
    SELECT
      p.id_barang,
      p.qty,
      NULLIF(btrim(COALESCE(b.id_grup, '')), '') AS id_grup,
      b.nama_barang,
      COALESCE(b.harga_beli, 0) AS harga_beli,
      COALESCE(b.harga_jual, 0) AS harga_jual,
      COALESCE(b.min_strat_1, 0) AS min_strat_1,
      COALESCE(b.jual_strat_1, 0) AS jual_strat_1,
      COALESCE(b.min_strat_2, 0) AS min_strat_2,
      COALESCE(b.jual_strat_2, 0) AS jual_strat_2,
      COALESCE(b.min_strat_3, 0) AS min_strat_3,
      COALESCE(b.jual_strat_3, 0) AS jual_strat_3,
      COALESCE(b.min_strat_4, 0) AS min_strat_4,
      COALESCE(b.jual_strat_4, 0) AS jual_strat_4,
      COALESCE(b.min_strat_5, 0) AS min_strat_5,
      COALESCE(b.jual_strat_5, 0) AS jual_strat_5,
      COALESCE(NULLIF(btrim(COALESCE(b.id_grup, '')), ''), b.id_barang) AS kunci_grup
    FROM pesan p
    JOIN public.barang b ON b.id_barang = p.id_barang
  ),
  grup AS (
    SELECT kunci_grup, SUM(qty)::integer AS qty_grup
    FROM baris
    GROUP BY kunci_grup
  )
  SELECT
    p_id,
    baris.id_barang,
    baris.id_grup,
    baris.nama_barang,
    baris.harga_beli,
    baris.harga_jual,
    baris.qty,
    public.harga_jual_strata(
      baris.harga_jual,
      grup.qty_grup,
      baris.min_strat_1,
      baris.jual_strat_1,
      baris.min_strat_2,
      baris.jual_strat_2,
      baris.min_strat_3,
      baris.jual_strat_3,
      baris.min_strat_4,
      baris.jual_strat_4,
      baris.min_strat_5,
      baris.jual_strat_5
    ),
    baris.min_strat_1,
    baris.jual_strat_1,
    baris.min_strat_2,
    baris.jual_strat_2,
    baris.min_strat_3,
    baris.jual_strat_3,
    baris.min_strat_4,
    baris.jual_strat_4,
    baris.min_strat_5,
    baris.jual_strat_5
  FROM baris
  JOIN grup ON grup.kunci_grup = baris.kunci_grup;

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
        qty_order, harga_jual_order,
        qty_packed, harga_jual_packed,
        min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
        min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
        min_strat_5, jual_strat_5
      ) VALUES (
        p_id_transaksi, v_sku, v_grup, v_nama, v_beli, v_jual,
        0, v_jual,
        v_qty, v_jual,
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
      SET
        qty_packed = v_qty,
        harga_jual_packed = COALESCE(harga_jual_packed, harga_jual_order, v_jual, 0)
      WHERE id_transaksi = p_id_transaksi
        AND id_barang = v_sku;
    END IF;
  END LOOP;

  UPDATE public.transaksi_items i
  SET
    qty_packed = 0,
    harga_jual_packed = COALESCE(i.harga_jual_order, 0)
  WHERE i.id_transaksi = p_id_transaksi
    AND i.qty_packed IS NULL;

  UPDATE public.transaksi_items i
  SET harga_jual_packed = public.harga_jual_strata(
    COALESCE(i.harga_jual, 0),
    (
      SELECT COALESCE(sum(x.qty_packed), 0)::integer
      FROM public.transaksi_items x
      WHERE x.id_transaksi = i.id_transaksi
        AND COALESCE(NULLIF(btrim(x.id_grup), ''), x.id_barang)
          = COALESCE(NULLIF(btrim(i.id_grup), ''), i.id_barang)
    ),
    i.min_strat_1, i.jual_strat_1,
    i.min_strat_2, i.jual_strat_2,
    i.min_strat_3, i.jual_strat_3,
    i.min_strat_4, i.jual_strat_4,
    i.min_strat_5, i.jual_strat_5
  )
  WHERE i.id_transaksi = p_id_transaksi
    AND i.qty_packed IS NOT NULL;

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
  FROM public.transaksi_items i
  WHERE i.id_transaksi = v_id
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_nota_item(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_item(text)
  TO authenticated, postgres, service_role;

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
      COALESCE(i.qty_packed, 0) AS qty_packed,
      COALESCE(i.harga_beli, 0) AS beli,
      COALESCE(i.harga_jual_packed, i.harga_jual_order, 0) AS jual
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
  LOOP
    IF rec.qty > rec.qty_packed THEN
      RAISE EXCEPTION 'Qty tebus melebihi packed (SKU %).', rec.id_barang;
    END IF;

    UPDATE public.transaksi_items
    SET
      qty_actual = rec.qty,
      harga_jual_actual = rec.jual
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
  SET
    qty_actual = 0,
    harga_jual_actual = COALESCE(harga_jual_packed, harga_jual_order, 0)
  WHERE id_transaksi = v_id
    AND qty_actual IS NULL;

  UPDATE public.transaksi_items i
  SET harga_jual_actual = public.harga_jual_strata(
    COALESCE(i.harga_jual, i.harga_jual_order, i.harga_jual_packed, 0),
    (
      SELECT COALESCE(sum(x.qty_actual), 0)::integer
      FROM public.transaksi_items x
      WHERE x.id_transaksi = i.id_transaksi
        AND COALESCE(NULLIF(btrim(x.id_grup), ''), x.id_barang)
          = COALESCE(NULLIF(btrim(i.id_grup), ''), i.id_barang)
    ),
    i.min_strat_1, i.jual_strat_1,
    i.min_strat_2, i.jual_strat_2,
    i.min_strat_3, i.jual_strat_3,
    i.min_strat_4, i.jual_strat_4,
    i.min_strat_5, i.jual_strat_5
  )
  WHERE i.id_transaksi = v_id
    AND COALESCE(i.qty_actual, 0) > 0;

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

REVOKE ALL ON FUNCTION public.pengirim_kunci_nota(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kunci_nota(text, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
