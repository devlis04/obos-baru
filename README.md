# Obos

Versi baru empat app. **Project Supabase sama dengan `obos_baru`** (`https://obos1.alhan.web.id/`), skema **public**. App lama tetap skema **obos**.

Jangan jalankan SQL `obos/` ke skema `obos`. Auth (`auth.users`) dipakai bersama.

## Siapkan database (sekali)

Di SQL Editor project lama:

1. `supabase/001_login.sql`
2. `supabase/002_confirm_auth.sql` hanya jika login ditolak karena email belum confirm
3. `supabase/003_pelanggan.sql`

Profil bisnis app baru ada di `public.users`, **bukan** `obos.users`. Sisipkan baris (email harus sama dengan Auth):

```sql
INSERT INTO public.users (email, nama, peran, rute)
VALUES
  ('alhansatu@gmail.com', 'Caca Suryaman', 'sales', 'SBGS01')
ON CONFLICT (email) DO UPDATE
SET nama = EXCLUDED.nama,
    peran = EXCLUDED.peran,
    rute = EXCLUDED.rute;
```

`.env` keempat app sudah menyalin URL + anon key dari `obos_baru`.

## Tahap 2 — pelanggan (salesman)

Setelah login, app salesman membuka daftar toko per hari kunjungan.

1. SQL Editor → jalankan `supabase/003_pelanggan.sql`.
2. Hot restart app salesman.
3. Tambah toko lewat ikon orang di app bar (butuh GPS). Geser kartu untuk urutan. Ikon peta membuka peta hari (OpenStreetMap).
4. SQL Editor → jalankan ulang `supabase/004_kunjungan.sql`.
5. SQL Editor → `supabase/005_barang.sql`, `006_transaksi.sql`, `007_sales_transaksi.sql` untuk outlet (potensi, input order, riwayat). Jika `006` lama sudah jalan, jalankan ulang `006` lalu `007` (`006` menghapus `transaksi_items`).
6. SQL Editor → `supabase/008_stok_desimal.sql` agar kolom `barang.stok` menerima pecahan (jika `005` sudah pernah jalan sebagai integer).
7. SQL Editor → `supabase/009_target_sales.sql`, lalu isi target omset/rasio di `public.target_sales` (email sama dengan akun sales). Drawer salesman → Dashboard Analisis.
8. SQL Editor → `supabase/010_gudang_absensi.sql`, lalu `supabase/011_gudang_scan_alur.sql`. Isi `public.lokasi_gudang` (`id = utama`) dengan GPS gudang. App gudang: login slot HP, lalu scan barcode `OBOS-GUDANG` (masuk/pulang) dengan alur sama seperti scan toko salesman.
9. SQL Editor → `supabase/012_gudang_packing.sql`. Beranda gudang menampilkan kartu rute; packing nota setelah absensi masuk. Cetak thermal menyusul.
10. SQL Editor → `supabase/013_id_setoran_buku.sql` (kolom `id_setoran_buku` di `absensi` dan `transaksi`).
11. SQL Editor → `supabase/014_setoran_buku.sql` (satu buku setoran + `stok_opname`). Scan masuk / packing pertama membuka buku dan mengisi snapshot SKU. Tutup buku dari admin.
12. SQL Editor → `supabase/015_admin_opname_kartu.sql`. Web admin: `cd apps/admin && flutter run -d chrome` — login, beranda kartu stok opname (cek selisih / konfirmasi fisik).
13. SQL Editor → `supabase/016_barang_stok_tahan.sql`. `barang.stok` tidak ikut packing; baru berubah saat semua staf gudang pulang, atau admin konfirmasi/tutup buku.
14. SQL Editor → `supabase/017_konfirmasi_dan_tutup_buku.sql`. Web admin: konfirmasi fisik di kartu opname; tutup buku di AppBar.
15. SQL Editor → `supabase/018_gudang_opname.sql`. App gudang (setelah scan masuk): drawer **Stok opname** untuk isi `stok_fisik`. Buku tidak tertutup otomatis.
16. SQL Editor → `supabase/019_admin_opname_realtime.sql`. Web admin: kartu opname ikut berubah saat gudang mengisi fisik / packing / tutup buku (tanpa wajib Segarkan). Realtime harus nyala di project.
17. SQL Editor → `supabase/020_opname_kasbon_margin.sql`. Web admin: selisih kurang → kasbon ke karyawan atau potong margin; selisih lebih → tambah margin saat tutup buku. Tutup buku ditolak jika kurang belum diputuskan.
18. SQL Editor → `supabase/021_opname_toko_packed.sql`. Dialog selisih: kolom tengah menampilkan toko yang packed SKU itu di buku yang sama.
19. SQL Editor → `supabase/022_barang_masuk.sql`. Web admin: kartu **Barang masuk** di bawah opname. Ada buku → geser `stok_opname`; tanpa buku → tulis `barang.stok`. SKU baru dari kartu. Ongkir per supplier. CSV menyusul. Jika `022` sudah pernah jalan, jalankan `supabase/023_barang_masuk_chip.sql` agar kartu menampilkan per baris supplier (SKU / total / ongkir) plus jumlah di bawah.
20. SQL Editor → `supabase/024_barang_masuk_csv.sql`. Dialog barang masuk: unduh/unggah CSV katalog + qty.
21. SQL Editor → `supabase/025_pengirim.sql`. App pengirim: login slot HP → scan barcode `OBOS-GUDANG` (GPS 20 m, sama seperti gudang) → beranda kartu toko packed dari rute sales yang dipetakan (`rute_peta`, grup SBGP tanpa D/H). Scan toko, kunci, setoran, retur menyusul.
22. SQL Editor → `supabase/026_pengirim_kunjungan.sql`. App pengirim: kartu seperti app lama (ikon lokasi + QR). Scan toko memakai pola salesman baru. Kunci nota menyusul. Jika `026` sudah pernah jalan, jalankan ulang.
23. SQL Editor → `supabase/027_pengirim_nota_item.sql`. Ketuk nota di toko/outlet: bottom sheet rincian barang. Jalankan ulang agar strata tebus ikut dari `transaksi_items`.
24. SQL Editor → `supabase/028_pengirim_pending_batal.sql`. Bottom sheet nota dikirim: tombol Pending + Batal; nota pending: Batal saja. Qty batal/retur diperlakukan seperti barang masuk: buku terbuka → `stok_opname` (`stok_awal` / hitung / fisik jika sudah diisi); tanpa buku → `barang.stok`.
25. SQL Editor → `supabase/029_setoran_pengirim.sql`. Tabel `setoran_pengirim`: uang setor + kasbon per mobil per buku. Layar setor menyusul.
26. SQL Editor → `supabase/030_pengirim_kunci.sql`. Outlet: konfirmasi / ubah tebus / kunci hasil toko. Sisa packed−actual seperti barang masuk. Retur menyusul.
27. SQL Editor → `supabase/031_transaksi_harga_jual.sql`. Kunci `harga_jual` katalog ke `transaksi_items` (dasar strata). Packing/tebus/kunci hitung dari kolom itu, bukan dari harga order/packed.
28. SQL Editor → `supabase/032_gudang_nota_harga_jual.sql`. App gudang: preview packing memakai `harga_jual` + strata di `transaksi_items`.
29. SQL Editor → `supabase/033_hapus_harga_jual_tahap.sql`. Hapus kolom `harga_jual_order` / `packed` / `actual`. Omset dan harga baris dihitung dari `harga_jual` + qty grup + strata (`v_transaksi_item`).
30. SQL Editor → `supabase/034_gudang_sembunyi_batal_sales.sql`. Daftar packing gudang tidak menampilkan nota batal sales (belum packing). Batal setelah packing tetap tampil.
31. SQL Editor → `supabase/035_pengirim_nota_laba.sql`. Kartu nota pengirim: laba order/packed/actual untuk rasio % (sama seperti sales/gudang).
32. SQL Editor → `supabase/036_pengirim_batal_tetap_tampil.sql`. Batal pengirim mengisi `waktu_actual` + `qty_actual` 0 supaya nota tetap di daftar (chip Batal).
33. SQL Editor → `supabase/037_pengirim_item_harga_beli.sql`. Item nota pengirim menyertakan `harga_beli` agar rasio profit actual/tebus bisa dihitung.
34. SQL Editor → `supabase/038_stok_kembali_packing.sql`. Sisa/batal pengirim mengurangi `stok_opname.qty_packed` (bukan menambah `stok_awal`). Rapikan opname yang sudah salah.

## Tahap 1 — login

- HP: Auth email+sandi, slot `public.users` (`hp_apply_is_login`).
- Admin web: Auth + `admin_profil`. Tanpa slot HP.

## Jalanin app

```text
cd apps/salesman && flutter run
cd apps/gudang && flutter run
cd apps/pengirim && flutter run
cd apps/admin && flutter run -d chrome
```

## Admin web di GitHub Pages

Sama pola app lama (`obos-baru-admin`), untuk app admin **baru**.

1. Buat repo GitHub (contoh `obos-admin`), lalu push isi folder `obos` ini.
2. Repo → **Settings → Secrets and variables → Actions**, tambah:
   - `SUPABASE_URL` (contoh `https://obos1.alhan.web.id`)
   - `SUPABASE_ANON_KEY`
3. **Settings → Pages**: Source = branch `gh-pages`, folder `/ (root)`.
4. Setiap push ke `main` / `master`, workflow `.github/workflows/deploy-admin-web.yml` membangun `apps/admin` dan menerbitkan ke Pages.

Alamat: `https://<user>.github.io/<nama-repo>/`  
Contoh jika repo `obos-admin` milik `devlis04`: `https://devlis04.github.io/obos-admin/`

`.env` tidak ikut git. CI menulis `apps/admin/assets/.env` dari secret saat build.

Package ID Android beda dari app lama (`com.obos.salesman`, `com.obos.gudang`, `com.obos.pengirim`) supaya bisa terpasang bersamaan.

## Folder

```text
apps/          salesman, gudang, pengirim, admin
packages/      obos_core, obos_auth
supabase/      SQL public
```
