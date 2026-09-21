-- Sisa/batal pengirim: barang kembali dari jalan → kurangi stok_opname.qty_packed.
-- Jangan naikkkan stok_awal (itu khusus barang masuk admin).
-- Tanpa buku terbuka → tulis barang.stok.

CREATE OR REPLACE FUNCTION public.stok_kembali_packing(
  p_id_barang text,
  p_qty numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_qty numeric(14, 4);
  v_lama numeric(14, 4);
BEGIN
  v_qty := round(GREATEST(COALESCE(p_qty, 0), 0), 4);
  IF v_qty = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang
    SET stok = COALESCE(stok, 0) + v_qty
    WHERE id_barang = p_id_barang;
    RETURN;
  END IF;

  SELECT so.qty_packed INTO v_lama
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_buku
    AND so.id_barang = p_id_barang
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_qty > COALESCE(v_lama, 0) THEN
    v_qty := COALESCE(v_lama, 0);
  END IF;
  IF v_qty = 0 THEN
    RETURN;
  END IF;

  UPDATE public.stok_opname
  SET
    qty_packed = qty_packed - v_qty,
    stok_fisik = CASE
      WHEN stok_fisik IS NULL THEN NULL
      ELSE stok_fisik + v_qty
    END
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_batal_nota(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_sales text[];
  v_status text;
  v_actual timestamptz;
  v_sku text;
  v_qty integer;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.waktu_actual
  INTO v_status, v_actual
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_status = 'batal' THEN
    RAISE EXCEPTION 'Nota sudah batal.';
  END IF;
  IF v_status <> 'dikirim' OR v_actual IS NOT NULL THEN
    RAISE EXCEPTION 'Hanya nota sedang dikirim atau pending yang bisa dibatalkan.';
  END IF;

  FOR v_sku, v_qty IN
    SELECT i.id_barang, COALESCE(i.qty_packed, 0)
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
      AND COALESCE(i.qty_packed, 0) > 0
    FOR UPDATE
  LOOP
    PERFORM public.stok_kembali_packing(v_sku, v_qty);
  END LOOP;

  UPDATE public.transaksi_items
  SET qty_actual = 0
  WHERE id_transaksi = v_id;

  UPDATE public.transaksi
  SET
    status = 'batal',
    pending = false,
    waktu_actual = clock_timestamp()
  WHERE id_transaksi = v_id;

  RETURN true;
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
      PERFORM public.stok_kembali_packing(
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

REVOKE ALL ON FUNCTION public.stok_kembali_packing(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stok_kembali_packing(text, numeric)
  TO authenticated, postgres, service_role;

-- Rapikan opname: qty_packed = yang masih di jalan / sudah terjual, bukan yang sudah kembali.
-- stok_awal dikurangi selisih yang sempat ditambah sebagai "barang masuk" palsu.
WITH benar AS (
  SELECT
    t.id_setoran_buku,
    i.id_barang,
    SUM(
      CASE
        WHEN t.status = 'dikirim' THEN COALESCE(i.qty_packed, 0)
        WHEN t.status = 'terkirim' THEN COALESCE(i.qty_actual, 0)
        WHEN t.status = 'batal' THEN COALESCE(i.qty_actual, 0)
        ELSE 0
      END
    )::numeric(14, 4) AS qty_packed_benar
  FROM public.transaksi t
  JOIN public.transaksi_items i ON i.id_transaksi = t.id_transaksi
  WHERE t.id_setoran_buku IS NOT NULL
    AND t.waktu_packed IS NOT NULL
  GROUP BY t.id_setoran_buku, i.id_barang
)
UPDATE public.stok_opname so
SET
  stok_awal = GREATEST(0, so.stok_awal - GREATEST(0, so.qty_packed - b.qty_packed_benar)),
  qty_packed = b.qty_packed_benar,
  stok_fisik = CASE
    WHEN so.stok_fisik IS NULL THEN NULL
    ELSE GREATEST(0, so.stok_fisik + GREATEST(0, so.qty_packed - b.qty_packed_benar))
  END
FROM benar b
WHERE so.id_setoran_buku = b.id_setoran_buku
  AND so.id_barang = b.id_barang
  AND so.qty_packed IS DISTINCT FROM b.qty_packed_benar;
