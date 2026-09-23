-- Seed master CONTOH di skema obos. Jalankan SETELAH 010.
-- public tidak diubah. Bukan data hidup. Boleh diulang (ON CONFLICT).
-- Titik gudang + toko berdekatan (~5 m) supaya scan 20 m lolos di SQL Editor.

INSERT INTO obos.lokasi_gudang (id, nama, latitude, longitude)
VALUES ('utama', 'Gudang Utama', -6.200000, 106.816666)
ON CONFLICT (id) DO UPDATE SET
  nama = EXCLUDED.nama,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude;

INSERT INTO obos.users (email, nama, peran, rute) VALUES
  ('uji.admin@obos.local', 'Uji Admin', 'admin', ''),
  ('uji.gudang@obos.local', 'Uji Gudang', 'gudang', ''),
  ('uji.sales01@obos.local', 'Uji Sales 01', 'sales', 'SBGS01'),
  ('uji.sales03@obos.local', 'Uji Sales 03', 'sales', 'SBGS03'),
  ('uji.p01d@obos.local', 'Uji Supir 01', 'pengirim', 'SBGP01D'),
  ('uji.p01h@obos.local', 'Uji Kenek 01', 'pengirim', 'SBGP01H'),
  ('uji.p02d@obos.local', 'Uji Supir 02', 'pengirim', 'SBGP02D'),
  ('uji.p02h@obos.local', 'Uji Kenek 02', 'pengirim', 'SBGP02H')
ON CONFLICT (email) DO UPDATE SET
  nama = EXCLUDED.nama,
  peran = EXCLUDED.peran,
  rute = EXCLUDED.rute,
  is_login = false;

INSERT INTO obos.target_sales (email, target_omset, target_persen_laba) VALUES
  ('uji.sales01@obos.local', 10000000, 10),
  ('uji.sales03@obos.local', 8000000, 10)
ON CONFLICT (email) DO UPDATE SET
  target_omset = EXCLUDED.target_omset,
  target_persen_laba = EXCLUDED.target_persen_laba;

INSERT INTO obos.supplier (nama, aktif)
VALUES ('UJI SUPPLIER', true)
ON CONFLICT (nama) DO UPDATE SET aktif = true;

INSERT INTO obos.pelanggan (
  id_pelanggan, nama_pelanggan, rute, visit, urutan, latitude, longitude, aktif
) VALUES
  (
    'UJI-TOKO1', 'TK UJI SATU', 'SBGS01', 'SENIN', 1,
    -6.200040, 106.816666, true
  ),
  (
    'UJI-TOKO2', 'TK UJI DUA', 'SBGS03', 'SELASA', 1,
    -6.200040, 106.816700, true
  )
ON CONFLICT (id_pelanggan) DO UPDATE SET
  nama_pelanggan = EXCLUDED.nama_pelanggan,
  rute = EXCLUDED.rute,
  visit = EXCLUDED.visit,
  urutan = EXCLUDED.urutan,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude,
  aktif = true;

INSERT INTO obos.barang (
  id_barang, id_grup, nama_barang, kategori, stok,
  harga_beli, harga_jual,
  min_strat_1, jual_strat_1,
  min_strat_2, jual_strat_2,
  id_supplier_utama
)
SELECT
  v.id_barang, v.id_grup, v.nama_barang, v.kategori, v.stok,
  v.harga_beli, v.harga_jual,
  v.min_strat_1, v.jual_strat_1,
  v.min_strat_2, v.jual_strat_2,
  s.id
FROM (
  VALUES
    (
      'UJI-A', 'UJI-GUL', 'Uji Barang A /strip', 'obat', 100::numeric,
      8000, 10000, 10, 9500, 20, 9000
    ),
    (
      'UJI-B', 'UJI-GUL', 'Uji Barang B /strip', 'obat', 100::numeric,
      8000, 10000, 10, 9500, 20, 9000
    ),
    (
      'UJI-C', NULL, 'Uji Barang C /botol', 'obat', 50::numeric,
      15000, 20000, 0, 0, 0, 0
    )
) AS v(
  id_barang, id_grup, nama_barang, kategori, stok,
  harga_beli, harga_jual, min_strat_1, jual_strat_1, min_strat_2, jual_strat_2
)
JOIN obos.supplier s ON s.nama = 'UJI SUPPLIER'
ON CONFLICT (id_barang) DO UPDATE SET
  id_grup = EXCLUDED.id_grup,
  nama_barang = EXCLUDED.nama_barang,
  kategori = EXCLUDED.kategori,
  stok = EXCLUDED.stok,
  harga_beli = EXCLUDED.harga_beli,
  harga_jual = EXCLUDED.harga_jual,
  min_strat_1 = EXCLUDED.min_strat_1,
  jual_strat_1 = EXCLUDED.jual_strat_1,
  min_strat_2 = EXCLUDED.min_strat_2,
  jual_strat_2 = EXCLUDED.jual_strat_2,
  id_supplier_utama = EXCLUDED.id_supplier_utama;

INSERT INTO obos.supplier_harga (id_supplier, id_barang, harga_beli)
SELECT s.id, b.id_barang, b.harga_beli
FROM obos.supplier s
JOIN obos.barang b ON b.id_barang IN ('UJI-A', 'UJI-B', 'UJI-C')
WHERE s.nama = 'UJI SUPPLIER'
ON CONFLICT (id_supplier, id_barang) DO UPDATE SET
  harga_beli = EXCLUDED.harga_beli;

-- Contoh alur (jalankan manual, satu per satu, setelah seed):
-- SELECT obos.scan_absensi('uji.gudang@obos.local', false, -6.200000, 106.816666, NULL);
-- SELECT obos.simpan_order('SBGS01', 'UJI-N1', 'UJI-TOKO1', 'TK UJI SATU',
--   '[{"id_barang":"UJI-A","qty":2},{"id_barang":"UJI-B","qty":8}]'::jsonb);
-- SELECT obos.pack_nota('UJI-N1', '[{"id_barang":"UJI-A","qty_packed":2},{"id_barang":"UJI-B","qty_packed":8}]'::jsonb);
-- SELECT obos.scan_absensi('uji.p01d@obos.local', false, -6.200000, 106.816666, NULL);
-- SELECT obos.kunjungan_pengirim_scan('uji.p01d@obos.local', 'UJI-TOKO1', false, -6.200040, 106.816666, NULL);
-- SELECT obos.kunci_nota('UJI-N1', '[{"id_barang":"UJI-A","qty_actual":2},{"id_barang":"UJI-B","qty_actual":0}]'::jsonb);
-- SELECT obos.order_lihat('UJI-N1');
-- SELECT obos.kartu_setoran(obos.buku_terbuka());
