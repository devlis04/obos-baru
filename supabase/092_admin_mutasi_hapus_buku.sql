-- Hapus mutasi: buku yang sedang dilihat, bukan selalu buku terbuka.
-- Jalankan SETELAH 091. Boleh diulang.

DROP FUNCTION IF EXISTS public.admin_mutasi_hapus();
DROP FUNCTION IF EXISTS public.admin_mutasi_hapus(bigint);

CREATE OR REPLACE FUNCTION public.admin_mutasi_hapus(
  p_id_setoran_buku bigint DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer := 0;
  v_id bigint;
  v_tutup boolean;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh hapus mutasi.';
  END IF;

  SELECT x.id, x.ditutup INTO v_id, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  IF v_id IS NULL THEN
    RETURN 0;
  END IF;
  IF coalesce(v_tutup, false) THEN
    RAISE EXCEPTION 'Buku sudah ditutup. Mutasi tidak diubah.';
  END IF;

  DELETE FROM public.mutasi_bank WHERE id_setoran_buku = v_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mutasi_hapus(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_hapus(bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
