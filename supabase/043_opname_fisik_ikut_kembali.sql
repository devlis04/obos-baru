-- Jika stok_fisik sudah terisi, ikut geser saat masuk / batal / retur
-- (master nanti menimpa fisik). Fisik kosong → hanya hitung.
-- Jalankan SETELAH 041. Boleh diulang.

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
  v_packed numeric(14, 4);
  v_batal numeric(14, 4);
  v_sisa numeric(14, 4);
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

  SELECT so.qty_packed, so.qty_batal
  INTO v_packed, v_batal
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_buku
    AND so.id_barang = p_id_barang
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_sisa := GREATEST(COALESCE(v_packed, 0) - COALESCE(v_batal, 0), 0);
  IF v_qty > v_sisa THEN
    v_qty := v_sisa;
  END IF;
  IF v_qty = 0 THEN
    RETURN;
  END IF;

  UPDATE public.stok_opname
  SET
    qty_batal = qty_batal + v_qty,
    stok_fisik = CASE
      WHEN stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, stok_fisik + v_qty)
    END
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
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
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang
    SET stok = GREATEST(0, COALESCE(stok, 0) + v_qty)
    WHERE id_barang = p_id_barang;
    RETURN;
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

NOTIFY pgrst, 'reload schema';
