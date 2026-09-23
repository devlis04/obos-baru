-- Batal/sisa tebus sisa kiriman buku kemarin: qty_batal tidak boleh dipotong
-- sampai qty_packed buku hari ini. TK BUDI Hemaviton packed 2, opname 22 hanya 1
-- karena BR151 packed hari itu cuma 1.
-- Jalankan SETELAH 096. SQL Editor → Run. Boleh di-Run ulang.
-- Tidak menutup buku.

ALTER TABLE public.stok_opname
  DROP CONSTRAINT IF EXISTS stok_opname_angka_chk;
ALTER TABLE public.stok_opname
  ADD CONSTRAINT stok_opname_angka_chk CHECK (
    stok_awal >= 0
    AND qty_masuk >= 0
    AND qty_packed >= 0
    AND qty_batal >= 0
    AND qty_retur >= 0
    AND (stok_fisik IS NULL OR stok_fisik >= 0)
  );

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

  SELECT so.qty_batal
  INTO v_batal
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

-- Karton ke-2 sudah masuk fisik buku terbuka (selisih +1). Pulihkan hitung.
UPDATE public.stok_opname so
SET qty_batal = so.qty_batal + 1
FROM public.setoran_buku b
WHERE so.id_setoran_buku = b.id
  AND NOT b.ditutup
  AND so.id_barang = 'BR151'
  AND so.qty_batal = 0
  AND COALESCE(so.selisih, 0) >= 1;

REVOKE ALL ON FUNCTION public.stok_catat_batal(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stok_catat_batal(text, numeric)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
