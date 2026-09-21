-- Qty packing batal diperlakukan seperti barang masuk:
-- buku terbuka → geser stok_opname (stok_awal / hitung / fisik jika sudah diisi);
-- tanpa buku → barang.stok. Retur pengirim nanti memakai fungsi yang sama.

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

  SELECT t.status, t.pending, t.waktu_actual
  INTO v_status, v_pending, v_actual
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
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
    PERFORM public.barang_masuk_geser_stok(v_sku, v_qty);
  END LOOP;

  UPDATE public.transaksi
  SET
    status = 'batal',
    pending = false
  WHERE id_transaksi = v_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_pending_nota(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_pending_nota(text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_batal_nota(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_batal_nota(text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
