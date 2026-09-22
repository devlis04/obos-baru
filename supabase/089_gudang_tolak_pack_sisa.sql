-- Sisa kiriman buku tutup (foto) tidak boleh packing ulang di buku baru.
-- Jalankan SETELAH 088. Pendek. Boleh diulang.

CREATE OR REPLACE FUNCTION public.gudang_tolak_pack_sisa_foto()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.setoran_buku_pending_foto f
    JOIN public.setoran_buku b ON b.id = f.id_setoran_buku
    WHERE f.id_transaksi = NEW.id_transaksi
      AND b.ditutup
  ) THEN
    RAISE EXCEPTION 'Sisa kiriman buku kemarin tidak di-packing ulang.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trx_item_tolak_pack_sisa_foto ON public.transaksi_items;
CREATE TRIGGER trx_item_tolak_pack_sisa_foto
  BEFORE INSERT OR UPDATE OF qty_packed ON public.transaksi_items
  FOR EACH ROW
  EXECUTE FUNCTION public.gudang_tolak_pack_sisa_foto();
