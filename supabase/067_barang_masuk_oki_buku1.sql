-- Pindah barang masuk + ongkir supplier Oki yang tersimpan tanpa buku
-- ke buku id = 1. Tidak menggeser stok lagi (qty sudah masuk katalog
-- saat input tanpa buku; snapshot buku 1 sudah memuatnya).
-- SQL Editor → Run.

DO $$
DECLARE
  v_buku constant bigint := 1;
  v_tgl date;
  v_oki integer;
BEGIN
  SELECT b.tanggal INTO v_tgl
  FROM public.setoran_buku b
  WHERE b.id = v_buku;
  IF v_tgl IS NULL THEN
    RAISE EXCEPTION 'Buku 1 tidak ada.';
  END IF;

  SELECT s.id INTO v_oki
  FROM public.supplier s
  WHERE lower(btrim(s.nama)) IN ('oki', 'ok i')
     OR lower(btrim(s.nama)) LIKE 'oki%'
  ORDER BY s.id
  LIMIT 1;
  IF v_oki IS NULL THEN
    RAISE EXCEPTION 'Supplier Oki tidak ada.';
  END IF;

  UPDATE public.barang_masuk a
  SET
    qty = a.qty + b.qty,
    nilai = a.nilai + b.nilai
  FROM public.barang_masuk b
  WHERE a.id_setoran_buku = v_buku
    AND a.id_supplier = v_oki
    AND b.id_supplier = v_oki
    AND b.id_setoran_buku IS NULL
    AND a.id_barang = b.id_barang;

  DELETE FROM public.barang_masuk b
  WHERE b.id_supplier = v_oki
    AND b.id_setoran_buku IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.barang_masuk a
      WHERE a.id_setoran_buku = v_buku
        AND a.id_supplier = v_oki
        AND a.id_barang = b.id_barang
    );

  UPDATE public.barang_masuk
  SET id_setoran_buku = v_buku, tanggal = v_tgl
  WHERE id_supplier = v_oki
    AND id_setoran_buku IS NULL;

  UPDATE public.ongkir a
  SET jumlah = a.jumlah + b.jumlah
  FROM public.ongkir b
  WHERE a.id_setoran_buku = v_buku
    AND a.id_supplier = v_oki
    AND b.id_supplier = v_oki
    AND b.id_setoran_buku IS NULL;

  DELETE FROM public.ongkir b
  WHERE b.id_supplier = v_oki
    AND b.id_setoran_buku IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.ongkir a
      WHERE a.id_setoran_buku = v_buku
        AND a.id_supplier = v_oki
    );

  UPDATE public.ongkir
  SET id_setoran_buku = v_buku, tanggal = v_tgl
  WHERE id_supplier = v_oki
    AND id_setoran_buku IS NULL;
END;
$$;

NOTIFY pgrst, 'reload schema';
