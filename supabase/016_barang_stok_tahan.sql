-- barang.stok tidak ikut packing. Master hanya berubah jika:
--   1. semua staff gudang/admin sudah scan pulang, atau
--   2. admin konfirmasi opname / tutup buku.
-- Packing hanya menggeser stok_opname.qty_packed / stok_hitung.
-- Jalankan SETELAH 014 (dan 015 jika sudah). Boleh diulang.

CREATE OR REPLACE FUNCTION public.barang_tahan_stok_buku()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.stok IS DISTINCT FROM OLD.stok
     AND current_setting('obos.boleh_tulis_stok', true) IS DISTINCT FROM 'on' THEN
    NEW.stok := OLD.stok;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS barang_tahan_stok_buku ON public.barang;
CREATE TRIGGER barang_tahan_stok_buku
  BEFORE UPDATE OF stok ON public.barang
  FOR EACH ROW
  EXECUTE FUNCTION public.barang_tahan_stok_buku();

CREATE OR REPLACE FUNCTION public.serahkan_stok_jika_gudang_kosong()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.absensi a
    WHERE a.waktu_keluar IS NULL
      AND a.peran IN ('gudang', 'admin')
  ) THEN
    RETURN;
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;
END;
$$;

DROP TRIGGER IF EXISTS absensi_pulang_serahkan_stok ON public.absensi;
CREATE OR REPLACE FUNCTION public.absensi_pulang_serahkan_stok()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NEW.waktu_keluar IS NOT NULL
     AND OLD.waktu_keluar IS NULL
     AND NEW.peran IN ('gudang', 'admin') THEN
    PERFORM public.serahkan_stok_jika_gudang_kosong();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER absensi_pulang_serahkan_stok
  AFTER UPDATE OF waktu_keluar ON public.absensi
  FOR EACH ROW
  EXECUTE FUNCTION public.absensi_pulang_serahkan_stok();

CREATE OR REPLACE FUNCTION public.admin_konfirmasi_opname(p_id_setoran_buku bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer := 0;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh konfirmasi opname.';
  END IF;
  IF p_id_setoran_buku IS NULL THEN
    RAISE EXCEPTION 'Buku kosong.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);
  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, so.stok_fisik)
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = p_id_setoran_buku
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_tutup_setoran_buku()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menutup buku.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  UPDATE public.setoran_buku
  SET
    ditutup = true,
    waktu_tutup = clock_timestamp()
  WHERE id = v_id
    AND NOT ditutup;

  RETURN v_id;
END;
$$;

-- Pulihkan master yang sudah terpotong packing, selama masih ada orang di gudang.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.absensi a
    WHERE a.waktu_keluar IS NULL
      AND a.peran IN ('gudang', 'admin')
  ) THEN
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang b
    SET stok = GREATEST(0, so.stok_awal)
    FROM public.stok_opname so
    JOIN public.setoran_buku sb
      ON sb.id = so.id_setoran_buku
     AND NOT sb.ditutup
    WHERE so.id_barang = b.id_barang;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.serahkan_stok_jika_gudang_kosong() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.serahkan_stok_jika_gudang_kosong()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_konfirmasi_opname(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_konfirmasi_opname(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_tutup_setoran_buku() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tutup_setoran_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
