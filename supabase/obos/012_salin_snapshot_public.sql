-- Salin snapshot public → obos. Packing di public tetap jalan.
-- Jalankan SETELAH 014 + ulang 004/005/006/008. Jangan jalankan 001 (DROP).
-- Menghapus isi uji di obos (termasuk 011), lalu isi ulang dari public.
-- Menyalin barang.aktif; qty_batal tidak dipotong packed; pending dipindah.
-- Satu transaksi REPEATABLE READ = foto detik itu. Boleh diulang.

BEGIN;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL session_replication_role = replica;

TRUNCATE TABLE
  obos.mutasi_bank,
  obos.setoran_kartu_simpan,
  obos.setoran_pengirim,
  obos.ongkir,
  obos.barang_masuk,
  obos.retur_toko,
  obos.kunjungan_pengirim,
  obos.kunjungan_sales,
  obos.kasbon,
  obos.stok_opname,
  obos.setoran_buku_pending_foto,
  obos.transaksi_items,
  obos.transaksi,
  obos.absensi,
  obos.setoran_buku,
  obos.supplier_harga,
  obos.barang,
  obos.target_sales,
  obos.pelanggan,
  obos.supplier,
  obos.rute_peta,
  obos.lokasi_gudang,
  obos.users
RESTART IDENTITY CASCADE;

INSERT INTO obos.users (email, nama, peran, rute, is_login, kunci_hp, sesi_login)
SELECT email, nama, peran, rute, is_login, kunci_hp, sesi_login
FROM (
  SELECT
    u.*,
    row_number() OVER (
      PARTITION BY
        CASE
          WHEN btrim(COALESCE(u.rute, '')) = '' THEN 'e:' || lower(u.email)
          ELSE 'r:' || lower(btrim(u.rute))
        END
      ORDER BY u.email
    ) AS rn
  FROM public.users u
  WHERE u.peran IN ('sales', 'gudang', 'admin', 'pengirim')
) x
WHERE rn = 1;

INSERT INTO obos.lokasi_gudang (id, nama, latitude, longitude)
SELECT id, nama, latitude, longitude
FROM public.lokasi_gudang;

INSERT INTO obos.rute_peta (rute_sales, rute_pengirim)
SELECT rute_sales, rute_pengirim
FROM public.rute_peta;

INSERT INTO obos.supplier (id, nama, aktif)
OVERRIDING SYSTEM VALUE
SELECT id, nama, aktif
FROM public.supplier;

INSERT INTO obos.target_sales (email, target_omset, target_persen_laba)
SELECT t.email, GREATEST(t.target_omset, 0), GREATEST(t.target_persen_laba, 0)
FROM public.target_sales t
JOIN obos.users u ON u.email = t.email;

INSERT INTO obos.pelanggan (
  id_pelanggan, nama_pelanggan, rute, visit, urutan, latitude, longitude, aktif
)
SELECT
  id_pelanggan, nama_pelanggan, rute, visit, urutan, latitude, longitude,
  COALESCE(aktif, true)
FROM public.pelanggan;

INSERT INTO obos.barang (
  id_barang, id_grup, nama_barang, kategori, stok,
  harga_beli, harga_jual,
  min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
  min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
  min_strat_5, jual_strat_5, id_supplier_utama, aktif
)
SELECT
  b.id_barang, b.id_grup, b.nama_barang, b.kategori,
  GREATEST(COALESCE(b.stok, 0), 0),
  GREATEST(COALESCE(b.harga_beli, 0), 0),
  GREATEST(COALESCE(b.harga_jual, 0), 0),
  COALESCE(b.min_strat_1, 0), COALESCE(b.jual_strat_1, 0),
  COALESCE(b.min_strat_2, 0), COALESCE(b.jual_strat_2, 0),
  COALESCE(b.min_strat_3, 0), COALESCE(b.jual_strat_3, 0),
  COALESCE(b.min_strat_4, 0), COALESCE(b.jual_strat_4, 0),
  COALESCE(b.min_strat_5, 0), COALESCE(b.jual_strat_5, 0),
  CASE WHEN s.id IS NOT NULL THEN b.id_supplier_utama END,
  COALESCE(b.aktif, true)
FROM public.barang b
LEFT JOIN obos.supplier s ON s.id = b.id_supplier_utama;

INSERT INTO obos.supplier_harga (id_supplier, id_barang, harga_beli)
SELECT h.id_supplier, h.id_barang, GREATEST(COALESCE(h.harga_beli, 0), 0)
FROM public.supplier_harga h
JOIN obos.supplier s ON s.id = h.id_supplier
JOIN obos.barang b ON b.id_barang = h.id_barang;

INSERT INTO obos.setoran_buku (id, tanggal, waktu_buka, waktu_tutup, ditutup)
OVERRIDING SYSTEM VALUE
SELECT
  id, tanggal, waktu_buka,
  CASE WHEN ditutup THEN COALESCE(waktu_tutup, waktu_buka) ELSE waktu_tutup END,
  ditutup
FROM public.setoran_buku;

INSERT INTO obos.absensi (
  id, email, peran, rute, tanggal, waktu_masuk, waktu_keluar, id_setoran_buku
)
OVERRIDING SYSTEM VALUE
SELECT
  a.id, a.email, a.peran, a.rute, a.tanggal, a.waktu_masuk, a.waktu_keluar,
  CASE WHEN b.id IS NOT NULL THEN a.id_setoran_buku END
FROM public.absensi a
JOIN obos.users u ON u.email = a.email
LEFT JOIN obos.setoran_buku b ON b.id = a.id_setoran_buku
WHERE a.peran IN ('gudang', 'pengirim', 'admin')
  AND a.waktu_masuk IS NOT NULL
  AND a.waktu_keluar IS NOT NULL
  AND a.waktu_keluar >= a.waktu_masuk;

INSERT INTO obos.absensi (
  id, email, peran, rute, tanggal, waktu_masuk, waktu_keluar, id_setoran_buku
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (lower(a.email))
  a.id, a.email, a.peran, a.rute, a.tanggal, a.waktu_masuk, NULL,
  CASE WHEN b.id IS NOT NULL THEN a.id_setoran_buku END
FROM public.absensi a
JOIN obos.users u ON u.email = a.email
LEFT JOIN obos.setoran_buku b ON b.id = a.id_setoran_buku
WHERE a.peran IN ('gudang', 'pengirim', 'admin')
  AND a.waktu_masuk IS NOT NULL
  AND a.waktu_keluar IS NULL
ORDER BY lower(a.email), a.waktu_masuk DESC, a.id DESC;

INSERT INTO obos.transaksi (
  id_transaksi, id_pelanggan, nama_pelanggan, rute, status,
  waktu_order, waktu_packed, waktu_actual, pending, id_setoran_buku
)
SELECT
  t.id_transaksi,
  t.id_pelanggan,
  t.nama_pelanggan,
  t.rute,
  t.status,
  t.waktu_order,
  t.waktu_packed,
  t.waktu_actual,
  CASE
    WHEN t.status = 'dikirim' AND t.waktu_actual IS NULL THEN COALESCE(t.pending, false)
    ELSE false
  END,
  CASE WHEN b.id IS NOT NULL THEN t.id_setoran_buku END
FROM public.transaksi t
JOIN obos.pelanggan p ON p.id_pelanggan = t.id_pelanggan
LEFT JOIN obos.setoran_buku b ON b.id = t.id_setoran_buku
WHERE t.status IN ('diproses', 'dikirim', 'terkirim', 'batal');

INSERT INTO obos.transaksi_items (
  id, id_transaksi, id_barang, id_grup, nama_barang,
  harga_beli, harga_jual, qty_order, qty_packed, qty_actual,
  min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
  min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
  min_strat_5, jual_strat_5
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (i.id_transaksi, i.id_barang)
  i.id, i.id_transaksi, i.id_barang, i.id_grup, i.nama_barang,
  GREATEST(COALESCE(i.harga_beli, 0), 0),
  GREATEST(COALESCE(i.harga_jual, 0), 0),
  GREATEST(COALESCE(i.qty_order, 0), 0),
  CASE WHEN i.qty_packed IS NULL THEN NULL ELSE GREATEST(i.qty_packed, 0) END,
  CASE WHEN i.qty_actual IS NULL THEN NULL ELSE GREATEST(i.qty_actual, 0) END,
  COALESCE(i.min_strat_1, 0), COALESCE(i.jual_strat_1, 0),
  COALESCE(i.min_strat_2, 0), COALESCE(i.jual_strat_2, 0),
  COALESCE(i.min_strat_3, 0), COALESCE(i.jual_strat_3, 0),
  COALESCE(i.min_strat_4, 0), COALESCE(i.jual_strat_4, 0),
  COALESCE(i.min_strat_5, 0), COALESCE(i.jual_strat_5, 0)
FROM public.transaksi_items i
JOIN obos.transaksi t ON t.id_transaksi = i.id_transaksi
JOIN obos.barang b ON b.id_barang = i.id_barang
ORDER BY i.id_transaksi, i.id_barang, i.id;

INSERT INTO obos.setoran_buku_pending_foto (id_setoran_buku, id_transaksi)
SELECT f.id_setoran_buku, f.id_transaksi
FROM public.setoran_buku_pending_foto f
JOIN obos.setoran_buku b ON b.id = f.id_setoran_buku
JOIN obos.transaksi t ON t.id_transaksi = f.id_transaksi
ON CONFLICT DO NOTHING;

INSERT INTO obos.stok_opname (
  id, id_setoran_buku, tanggal, id_barang, nama_barang,
  stok_awal, qty_masuk, qty_packed, qty_batal, qty_retur, stok_fisik,
  dicek_stok_oleh, putusan, nilai_putusan, harga_beli_putusan,
  qty_selisih_putusan, kasbon_email, kasbon_nama, waktu_putusan
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (so.id_setoran_buku, so.id_barang)
  so.id, so.id_setoran_buku, so.tanggal, so.id_barang, so.nama_barang,
  GREATEST(COALESCE(so.stok_awal, 0), 0),
  GREATEST(COALESCE(so.qty_masuk, 0), 0),
  q.v_packed,
  GREATEST(COALESCE(so.qty_batal, 0), 0),
  GREATEST(COALESCE(so.qty_retur, 0), 0),
  CASE WHEN so.stok_fisik IS NULL THEN NULL ELSE GREATEST(so.stok_fisik, 0) END,
  so.dicek_stok_oleh,
  CASE
    WHEN so.putusan = 'kasbon'
      AND btrim(COALESCE(so.kasbon_email, '')) <> ''
      AND btrim(COALESCE(so.kasbon_nama, '')) <> ''
      THEN 'kasbon'
    WHEN so.putusan IN ('beban', 'margin_plus') THEN so.putusan
  END,
  CASE
    WHEN so.putusan = 'kasbon'
      AND btrim(COALESCE(so.kasbon_email, '')) <> ''
      AND btrim(COALESCE(so.kasbon_nama, '')) <> ''
      THEN GREATEST(COALESCE(so.nilai_putusan, 0), 0)
    WHEN so.putusan IN ('beban', 'margin_plus')
      THEN GREATEST(COALESCE(so.nilai_putusan, 0), 0)
  END,
  CASE
    WHEN so.putusan = 'kasbon'
      AND btrim(COALESCE(so.kasbon_email, '')) <> ''
      AND btrim(COALESCE(so.kasbon_nama, '')) <> ''
      THEN GREATEST(COALESCE(so.harga_beli_putusan, 0), 0)
    WHEN so.putusan IN ('beban', 'margin_plus')
      THEN GREATEST(COALESCE(so.harga_beli_putusan, 0), 0)
  END,
  so.qty_selisih_putusan,
  CASE
    WHEN so.putusan = 'kasbon'
      AND btrim(COALESCE(so.kasbon_email, '')) <> ''
      THEN so.kasbon_email
  END,
  CASE
    WHEN so.putusan = 'kasbon'
      AND btrim(COALESCE(so.kasbon_nama, '')) <> ''
      THEN so.kasbon_nama
  END,
  so.waktu_putusan
FROM public.stok_opname so
JOIN obos.setoran_buku b ON b.id = so.id_setoran_buku
JOIN obos.barang g ON g.id_barang = so.id_barang
CROSS JOIN LATERAL (
  SELECT GREATEST(COALESCE(so.qty_packed, 0), 0) AS v_packed
) q
ORDER BY so.id_setoran_buku, so.id_barang, so.id;

INSERT INTO obos.kasbon (id, email, nama, nilai, id_setoran_buku, id_barang, waktu)
OVERRIDING SYSTEM VALUE
SELECT k.id, k.email, k.nama, k.nilai, k.id_setoran_buku, k.id_barang, k.waktu
FROM public.kasbon k
JOIN obos.users u ON u.email = k.email
JOIN obos.setoran_buku b ON b.id = k.id_setoran_buku
WHERE k.nilai > 0;

INSERT INTO obos.kunjungan_sales (
  id, id_pelanggan, rute, tanggal, waktu_masuk, waktu_keluar, jarak
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (k.id_pelanggan, k.tanggal)
  k.id, k.id_pelanggan, k.rute, k.tanggal, k.waktu_masuk, k.waktu_keluar,
  GREATEST(COALESCE(k.jarak, 0), 0)
FROM public.kunjungan_sales k
JOIN obos.pelanggan p ON p.id_pelanggan = k.id_pelanggan
WHERE btrim(k.rute) <> ''
ORDER BY k.id_pelanggan, k.tanggal, k.id;

INSERT INTO obos.kunjungan_pengirim (
  id, id_pelanggan, rute_pengirim, rute_sales, tanggal,
  waktu_masuk, waktu_keluar, jarak
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (k.rute_pengirim, k.id_pelanggan, k.tanggal)
  k.id, k.id_pelanggan, k.rute_pengirim, k.rute_sales, k.tanggal,
  k.waktu_masuk, k.waktu_keluar, GREATEST(COALESCE(k.jarak, 0), 0)
FROM public.kunjungan_pengirim k
JOIN obos.pelanggan p ON p.id_pelanggan = k.id_pelanggan
WHERE btrim(k.rute_pengirim) <> '' AND btrim(k.rute_sales) <> ''
ORDER BY k.rute_pengirim, k.id_pelanggan, k.tanggal, k.id;

INSERT INTO obos.retur_toko (
  id, id_setoran_buku, tanggal, rute_pengirim, id_pelanggan,
  kode_barang, nama_barang, qty, harga_jual, waktu_catat
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (r.id_setoran_buku, r.rute_pengirim, r.id_pelanggan, r.kode_barang)
  r.id, r.id_setoran_buku, r.tanggal, r.rute_pengirim, r.id_pelanggan,
  r.kode_barang, COALESCE(r.nama_barang, ''), r.qty,
  GREATEST(COALESCE(r.harga_jual, 0), 0), r.waktu_catat
FROM public.retur_toko r
JOIN obos.setoran_buku b ON b.id = r.id_setoran_buku
WHERE r.qty > 0
ORDER BY r.id_setoran_buku, r.rute_pengirim, r.id_pelanggan, r.kode_barang, r.id;

INSERT INTO obos.barang_masuk (
  id, tanggal, id_supplier, id_barang, qty, nilai, id_setoran_buku
)
OVERRIDING SYSTEM VALUE
SELECT
  m.id, m.tanggal, m.id_supplier, m.id_barang, m.qty, GREATEST(m.nilai, 0),
  CASE WHEN b.id IS NOT NULL THEN m.id_setoran_buku END
FROM public.barang_masuk m
JOIN obos.supplier s ON s.id = m.id_supplier
JOIN obos.barang g ON g.id_barang = m.id_barang
LEFT JOIN obos.setoran_buku b ON b.id = m.id_setoran_buku
WHERE m.qty > 0;

INSERT INTO obos.ongkir (id, tanggal, id_supplier, jumlah, id_setoran_buku)
OVERRIDING SYSTEM VALUE
SELECT
  o.id, o.tanggal, o.id_supplier, GREATEST(o.jumlah, 0),
  CASE WHEN b.id IS NOT NULL THEN o.id_setoran_buku END
FROM public.ongkir o
JOIN obos.supplier s ON s.id = o.id_supplier
LEFT JOIN obos.setoran_buku b ON b.id = o.id_setoran_buku;

INSERT INTO obos.setoran_pengirim (
  id, rute_pengirim, id_setoran_buku,
  jumlah_transfer, jumlah_tunai, jumlah_bop, kasbon_supir, kasbon_kenek,
  waktu_setor, dicatat_oleh, dicatat_rute
)
OVERRIDING SYSTEM VALUE
SELECT DISTINCT ON (s.rute_pengirim, s.id_setoran_buku)
  s.id, s.rute_pengirim, s.id_setoran_buku,
  GREATEST(s.jumlah_transfer, 0),
  GREATEST(s.jumlah_tunai, 0),
  LEAST(GREATEST(s.jumlah_bop, 0), 170000),
  GREATEST(s.kasbon_supir, 0),
  GREATEST(s.kasbon_kenek, 0),
  s.waktu_setor, COALESCE(s.dicatat_oleh, ''), COALESCE(s.dicatat_rute, '')
FROM public.setoran_pengirim s
JOIN obos.setoran_buku b ON b.id = s.id_setoran_buku
WHERE btrim(s.rute_pengirim) <> ''
ORDER BY s.rute_pengirim, s.id_setoran_buku, s.id DESC;

INSERT INTO obos.setoran_kartu_simpan (
  id_setoran_buku, isi, waktu_simpan, dicatat_oleh
)
SELECT s.id_setoran_buku, s.isi, s.waktu_simpan, s.dicatat_oleh
FROM public.setoran_kartu_simpan s
JOIN obos.setoran_buku b ON b.id = s.id_setoran_buku;

INSERT INTO obos.mutasi_bank (
  id, id_setoran_buku, tanggal, tanggal_mutasi, rekening_alias,
  jumlah, berita, rute_pengirim, status_cocok, nama_berkas, dicatat_oleh, waktu_unggah
)
OVERRIDING SYSTEM VALUE
SELECT
  m.id, m.id_setoran_buku, m.tanggal, m.tanggal_mutasi, m.rekening_alias,
  GREATEST(COALESCE(m.jumlah, 0), 0), m.berita, m.rute_pengirim,
  CASE
    WHEN m.status_cocok IN ('cocok', 'manual', 'tidak_cocok') THEN m.status_cocok
    ELSE 'tidak_cocok'
  END,
  m.nama_berkas, m.dicatat_oleh, m.waktu_unggah
FROM public.mutasi_bank m
JOIN obos.setoran_buku b ON b.id = m.id_setoran_buku;

SELECT setval(pg_get_serial_sequence('obos.supplier', 'id'),
  COALESCE((SELECT max(id) FROM obos.supplier), 1), true);
SELECT setval(pg_get_serial_sequence('obos.setoran_buku', 'id'),
  COALESCE((SELECT max(id) FROM obos.setoran_buku), 1), true);
SELECT setval(pg_get_serial_sequence('obos.absensi', 'id'),
  COALESCE((SELECT max(id) FROM obos.absensi), 1), true);
SELECT setval(pg_get_serial_sequence('obos.transaksi_items', 'id'),
  COALESCE((SELECT max(id) FROM obos.transaksi_items), 1), true);
SELECT setval(pg_get_serial_sequence('obos.stok_opname', 'id'),
  COALESCE((SELECT max(id) FROM obos.stok_opname), 1), true);
SELECT setval(pg_get_serial_sequence('obos.kasbon', 'id'),
  COALESCE((SELECT max(id) FROM obos.kasbon), 1), true);
SELECT setval(pg_get_serial_sequence('obos.kunjungan_sales', 'id'),
  COALESCE((SELECT max(id) FROM obos.kunjungan_sales), 1), true);
SELECT setval(pg_get_serial_sequence('obos.kunjungan_pengirim', 'id'),
  COALESCE((SELECT max(id) FROM obos.kunjungan_pengirim), 1), true);
SELECT setval(pg_get_serial_sequence('obos.retur_toko', 'id'),
  COALESCE((SELECT max(id) FROM obos.retur_toko), 1), true);
SELECT setval(pg_get_serial_sequence('obos.barang_masuk', 'id'),
  COALESCE((SELECT max(id) FROM obos.barang_masuk), 1), true);
SELECT setval(pg_get_serial_sequence('obos.ongkir', 'id'),
  COALESCE((SELECT max(id) FROM obos.ongkir), 1), true);
SELECT setval(pg_get_serial_sequence('obos.setoran_pengirim', 'id'),
  COALESCE((SELECT max(id) FROM obos.setoran_pengirim), 1), true);
SELECT setval(pg_get_serial_sequence('obos.mutasi_bank', 'id'),
  COALESCE((SELECT max(id) FROM obos.mutasi_bank), 1), true);

DO $$
DECLARE
  v_lama bigint;
  v_baru bigint;
BEGIN
  SELECT b.id INTO v_baru
  FROM obos.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;
  FOR v_lama IN
    SELECT b.id FROM obos.setoran_buku b WHERE b.ditutup ORDER BY b.id
  LOOP
    PERFORM obos.foto_catat(v_lama);
  END LOOP;
  IF v_baru IS NOT NULL THEN
    PERFORM obos.foto_pindah(v_baru);
  END IF;
END;
$$;

COMMIT;

SELECT
  'users' AS tabel,
  (SELECT count(*) FROM public.users) AS public_n,
  (SELECT count(*) FROM obos.users) AS obos_n
UNION ALL SELECT 'pelanggan',
  (SELECT count(*) FROM public.pelanggan), (SELECT count(*) FROM obos.pelanggan)
UNION ALL SELECT 'barang',
  (SELECT count(*) FROM public.barang), (SELECT count(*) FROM obos.barang)
UNION ALL SELECT 'setoran_buku',
  (SELECT count(*) FROM public.setoran_buku), (SELECT count(*) FROM obos.setoran_buku)
UNION ALL SELECT 'transaksi',
  (SELECT count(*) FROM public.transaksi), (SELECT count(*) FROM obos.transaksi)
UNION ALL SELECT 'transaksi_items',
  (SELECT count(*) FROM public.transaksi_items), (SELECT count(*) FROM obos.transaksi_items)
UNION ALL SELECT 'stok_opname',
  (SELECT count(*) FROM public.stok_opname), (SELECT count(*) FROM obos.stok_opname)
UNION ALL SELECT 'buku_terbuka',
  (SELECT count(*) FROM public.setoran_buku WHERE NOT ditutup),
  (SELECT count(*) FROM obos.setoran_buku WHERE NOT ditutup);
