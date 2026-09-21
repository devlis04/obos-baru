-- Cap buku setoran pada absensi dan nota. Jalankan SETELAH 012.
-- Tabel setoran_buku dan stok_opname BELUM dibuat; kolom bigint tanpa FK.
-- Boleh diulang.

ALTER TABLE public.absensi
  ADD COLUMN IF NOT EXISTS id_setoran_buku bigint;

ALTER TABLE public.transaksi
  ADD COLUMN IF NOT EXISTS id_setoran_buku bigint;

COMMENT ON COLUMN public.absensi.id_setoran_buku IS
  'Buku setoran yang terbuka saat scan masuk. FK ke setoran_buku menyusul. Kosong sampai buku ada.';
COMMENT ON COLUMN public.transaksi.id_setoran_buku IS
  'Buku setoran yang terbuka saat packing. FK ke setoran_buku menyusul. Kosong sampai buku ada.';

CREATE INDEX IF NOT EXISTS absensi_setoran_buku_idx
  ON public.absensi (id_setoran_buku);
CREATE INDEX IF NOT EXISTS transaksi_setoran_buku_idx
  ON public.transaksi (id_setoran_buku);

NOTIFY pgrst, 'reload schema';
