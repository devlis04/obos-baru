-- Dua perbaikan public (095 opname SKU aktif, 096 pindah pending) untuk skema obos.
-- 001–010 yang sudah di-Run belum punya barang.aktif / pindah saat buku sudah terbuka.
-- Jangan jalankan 001 (DROP CASCADE). SQL Editor → Run 013, lalu ulang 004, 006, 008.
-- 011/012 belum wajib. 012 nanti menyalin aktif dari public + pindah pending.

ALTER TABLE obos.barang
  ADD COLUMN IF NOT EXISTS aktif boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN obos.barang.aktif IS
  'false = disembunyikan dari katalog lapangan dan opname gudang. Tidak dihapus (FK nota).';
