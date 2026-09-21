-- Reset histori operasional di server.
-- Jalankan di SQL Editor (role postgres). TIDAK bisa di-undo.
--
-- Dihapus:
--   nota + item, kunjungan sales/pengirim, absensi,
--   buku setoran, opname, kasbon, setoran pengirim,
--   barang masuk, ongkir, dan barang.stok (kembali 0).
--
-- Tidak diubah:
--   users, pelanggan, barang (katalog/harga/strata), supplier,
--   supplier_harga, rute_peta, lokasi_gudang, target_sales, Auth.

BEGIN;

SET LOCAL row_security = off;
SELECT set_config('obos.boleh_tulis_stok', 'on', true);

TRUNCATE TABLE
  public.transaksi_items,
  public.transaksi,
  public.kunjungan_sales,
  public.kunjungan_pengirim,
  public.kasbon,
  public.setoran_pengirim,
  public.stok_opname,
  public.barang_masuk,
  public.ongkir,
  public.absensi,
  public.setoran_buku
RESTART IDENTITY CASCADE;

UPDATE public.barang
SET stok = 0;

COMMIT;
