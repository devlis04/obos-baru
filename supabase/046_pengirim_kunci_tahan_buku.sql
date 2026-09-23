-- Buku ditutup: pengirim tidak boleh kunci / batal / pending,
-- dan sisa/retur tidak boleh jatuh ke barang.stok.
-- Jalankan SETELAH 045. Boleh diulang.

CREATE OR REPLACE FUNCTION public.stok_catat_batal(
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
  v_packed numeric(14, 4);
  v_batal numeric(14, 4);
  v_baru numeric(14, 4);
  v_geser numeric(14, 4);
BEGIN
  v_qty := round(COALESCE(p_qty, 0), 4);
  IF v_qty = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Stok batal/sisa tidak bisa diubah.';
  END IF;

  SELECT so.qty_packed, so.qty_batal
  INTO v_packed, v_batal
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_buku
    AND so.id_barang = p_id_barang
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_baru := GREATEST(0, COALESCE(v_batal, 0) + v_qty);
  v_geser := v_baru - COALESCE(v_batal, 0);
  IF v_geser = 0 THEN
    RETURN;
  END IF;

  UPDATE public.stok_opname
  SET
    qty_batal = v_baru,
    stok_fisik = CASE
      WHEN stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, stok_fisik + v_geser)
    END
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
END;
$$;

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
BEGIN
  PERFORM public.stok_catat_batal(p_id_barang, GREATEST(COALESCE(p_qty, 0), 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.stok_catat_retur(
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
BEGIN
  v_qty := round(COALESCE(p_qty, 0), 4);
  IF v_qty = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Retur tidak bisa diubah.';
  END IF;

  UPDATE public.stok_opname
  SET
    qty_retur = GREATEST(0, qty_retur + v_qty),
    stok_fisik = CASE
      WHEN stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, stok_fisik + (GREATEST(0, qty_retur + v_qty) - qty_retur))
    END
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_pending_nota(p_id_transaksi text)
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
  v_pending boolean;
  v_actual timestamptz;
  v_buku bigint;
  v_buku_nota bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa diubah.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.pending, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_pending, v_actual, v_buku_nota
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_buku_nota IS NOT NULL AND v_buku_nota IS DISTINCT FROM v_buku THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF v_status <> 'dikirim' OR v_actual IS NOT NULL THEN
    RAISE EXCEPTION 'Hanya nota sedang dikirim yang bisa di-pending.';
  END IF;
  IF v_pending THEN
    RAISE EXCEPTION 'Nota sudah pending.';
  END IF;

  UPDATE public.transaksi
  SET pending = true
  WHERE id_transaksi = v_id;

  RETURN true;
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
  v_buku bigint;
  v_buku_nota bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa diubah.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_actual, v_buku_nota
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_buku_nota IS NOT NULL AND v_buku_nota IS DISTINCT FROM v_buku THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
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
  v_buku bigint;
  v_buku_nota bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa dikunci.';
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

  SELECT t.status, t.id_setoran_buku
  INTO v_status, v_buku_nota
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_buku_nota IS NOT NULL AND v_buku_nota IS DISTINCT FROM v_buku THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF v_status IN ('terkirim', 'batal') THEN
    PERFORM public.pengirim_buka_kunci_nota(v_id);
    v_status := 'dikirim';
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

NOTIFY pgrst, 'reload schema';
