-- Kunci aplikasi salesman LAMA (skema obos).
-- App baru memakai public; file ini tidak mengubah public.
-- Login slot sales lama dilepas. Simpan nota / scan / urutan toko ditolak.
-- Keluar (apply_own_is_login false) masih boleh.
-- SQL Editor (postgres). Boleh di-Run ulang.

CREATE OR REPLACE FUNCTION obos.sales_sedang_login()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = obos
AS $$
BEGIN
  RAISE EXCEPTION
    'Aplikasi salesman lama sudah ditutup. Pakai aplikasi baru.';
END;
$$;

REVOKE ALL ON FUNCTION obos.sales_sedang_login() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION obos.sales_sedang_login() TO authenticated;

CREATE OR REPLACE FUNCTION obos.apply_own_is_login(p_is_login boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = obos
AS $$
DECLARE
  v_email text;
  v_peran text;
BEGIN
  IF COALESCE(p_is_login, false) THEN
    RAISE EXCEPTION
      'Aplikasi salesman lama sudah ditutup. Pakai aplikasi baru.';
  END IF;

  v_email := lower(trim(COALESCE(auth.jwt() ->> 'email', '')));
  IF v_email = '' THEN
    RETURN false;
  END IF;

  SELECT peran INTO v_peran
  FROM obos.users
  WHERE lower(trim(email)) = v_email;

  IF v_peran IS DISTINCT FROM 'sales' THEN
    RETURN false;
  END IF;

  UPDATE obos.users
  SET is_login = false
  WHERE lower(trim(email)) = v_email;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION obos.apply_own_is_login(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION obos.apply_own_is_login(boolean) TO authenticated;

UPDATE obos.users
SET is_login = false
WHERE peran = 'sales';

NOTIFY pgrst, 'reload schema';
