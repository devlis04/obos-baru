-- Reset data aplikasi. Sisakan isi tabel users saja.
-- Barang, pelanggan, supplier, nota, buku, absensi, dll. dikosongkan.
-- Anda isi barang & pelanggan langsung di server.
--
-- Tidak dihapus: public.users (akun), Auth (password).
-- Sesi HP di users dilepas (is_login / kunci_hp / sesi_login).
-- rute_peta dan lokasi_gudang dikosongkan lalu diisi ulang peta default
-- supaya sales/pengirim/absensi gudang tetap punya rute & titik scan.
--
-- SQL Editor (postgres). TIDAK bisa di-undo. Jalankan sekali.

BEGIN;

SET LOCAL row_security = off;
SELECT set_config('obos.boleh_tulis_stok', 'on', true);

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname AS tbl
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname <> 'users'
    ORDER BY c.relname
  LOOP
    EXECUTE format(
      'TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE',
      r.tbl
    );
  END LOOP;
END;
$$;

INSERT INTO public.lokasi_gudang (id, nama, latitude, longitude)
VALUES ('utama', 'Gudang Utama', NULL, NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.rute_peta (rute_sales, rute_pengirim) VALUES
  ('SBGS01', 'SBGP01'),
  ('SBGS02', 'SBGP01'),
  ('SBGS03', 'SBGP02'),
  ('SBGS04', 'SBGP02'),
  ('SBGS05', 'SBGP03'),
  ('SBGS06', 'SBGP03'),
  ('SBGS07', 'SBGP04'),
  ('SBGS08', 'SBGP04')
ON CONFLICT (rute_sales) DO NOTHING;

UPDATE public.users
SET
  is_login = false,
  kunci_hp = NULL,
  sesi_login = NULL;

COMMIT;
