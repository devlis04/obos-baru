-- Login tahap 1. Jalankan di SQL Editor project yang SAMA dengan obos_baru.
-- Skema public saja. Jangan ubah skema obos.
-- Setelah ini: buat user di Authentication, lalu sisipkan baris di public.users.

CREATE TABLE IF NOT EXISTS public.users (
  email text PRIMARY KEY,
  nama text NOT NULL,
  peran text NOT NULL,
  rute text NOT NULL DEFAULT '',
  is_login boolean NOT NULL DEFAULT false,
  kunci_hp text,
  sesi_login text,
  CONSTRAINT users_email_chk CHECK (btrim(email) <> ''),
  CONSTRAINT users_nama_chk CHECK (btrim(nama) <> ''),
  CONSTRAINT users_peran_chk CHECK (peran IN ('sales', 'gudang', 'admin', 'pengirim'))
);

COMMENT ON TABLE public.users IS
  'Profil bisnis. Password ada di auth.users, bukan di sini.';
COMMENT ON COLUMN public.users.email IS 'Sama dengan email Auth. Disimpan huruf kecil.';
COMMENT ON COLUMN public.users.peran IS 'sales | gudang | admin | pengirim';
COMMENT ON COLUMN public.users.rute IS 'Kode rute. Kosong jika peran tidak punya rute.';
COMMENT ON COLUMN public.users.is_login IS 'true = slot HP terisi.';
COMMENT ON COLUMN public.users.kunci_hp IS
  'Identitas HP. Sama di HP itu sampai app dihapus. Web admin tidak memakai ini.';
COMMENT ON COLUMN public.users.sesi_login IS
  'session_id JWT yang memegang slot. Web admin tidak memakai ini.';

CREATE UNIQUE INDEX IF NOT EXISTS users_rute_satu_akun_uidx
  ON public.users (lower(btrim(rute)))
  WHERE btrim(rute) <> '';

CREATE OR REPLACE FUNCTION public.users_rapikan()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.email := lower(btrim(NEW.email));
  NEW.nama := btrim(NEW.nama);
  NEW.peran := lower(btrim(NEW.peran));
  NEW.rute := btrim(COALESCE(NEW.rute, ''));
  IF NEW.kunci_hp IS NOT NULL THEN
    NEW.kunci_hp := nullif(btrim(NEW.kunci_hp), '');
  END IF;
  IF NEW.sesi_login IS NOT NULL THEN
    NEW.sesi_login := nullif(btrim(NEW.sesi_login), '');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_rapikan_trg ON public.users;
CREATE TRIGGER users_rapikan_trg
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.users_rapikan();

GRANT SELECT ON TABLE public.users TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.users FROM authenticated;
REVOKE ALL ON TABLE public.users FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.users TO postgres, service_role;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_select_sendiri ON public.users;
CREATE POLICY users_select_sendiri
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    lower(trim(email)) = lower(trim(COALESCE(auth.jwt() ->> 'email', '')))
  );

CREATE OR REPLACE FUNCTION public.email_jwt()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT lower(trim(COALESCE(auth.jwt() ->> 'email', '')));
$$;

CREATE OR REPLACE FUNCTION public.sesi_jwt()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    nullif(btrim(COALESCE(auth.jwt() ->> 'session_id', '')), ''),
    CASE
      WHEN auth.uid() IS NULL THEN ''
      ELSE 'uid:' || auth.uid()::text
    END
  );
$$;

CREATE OR REPLACE FUNCTION public.hp_sedang_login(VARIADIC p_peran text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT u.is_login
        AND u.peran = ANY (p_peran)
        AND u.sesi_login IS NOT NULL
        AND btrim(u.sesi_login) <> ''
        AND u.sesi_login = public.sesi_jwt()
      FROM public.users u
      WHERE lower(trim(u.email)) = public.email_jwt()
        AND public.email_jwt() <> ''
      LIMIT 1
    ),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.sales_sedang_login()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.hp_sedang_login('sales');
$$;

CREATE OR REPLACE FUNCTION public.gudang_sedang_login()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.hp_sedang_login('gudang', 'admin');
$$;

CREATE OR REPLACE FUNCTION public.pengirim_sedang_login()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.hp_sedang_login('pengirim');
$$;

CREATE OR REPLACE FUNCTION public.admin_sedang_login()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT u.peran = 'admin'
      FROM public.users u
      WHERE lower(trim(u.email)) = public.email_jwt()
        AND public.email_jwt() <> ''
      LIMIT 1
    ),
    false
  );
$$;

COMMENT ON FUNCTION public.admin_sedang_login() IS
  'Web admin. Cek peran saja, tanpa is_login / kunci_hp.';

CREATE OR REPLACE FUNCTION public.hp_apply_is_login(
  p_is_login boolean,
  p_kunci text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_peran text;
  v_kunci text;
  v_sesi text;
  v_login boolean;
  v_hp text;
BEGIN
  v_email := public.email_jwt();
  v_sesi := public.sesi_jwt();
  v_kunci := btrim(COALESCE(p_kunci, ''));
  IF v_email = '' OR v_sesi = '' THEN
    RETURN false;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('public.hp_login:' || v_email));

  SELECT peran, is_login, kunci_hp
  INTO v_peran, v_login, v_hp
  FROM public.users
  WHERE lower(trim(email)) = v_email
  FOR UPDATE;

  IF v_peran IS NULL OR v_peran NOT IN ('sales', 'gudang', 'pengirim', 'admin') THEN
    RETURN false;
  END IF;

  IF COALESCE(p_is_login, false) THEN
    IF v_kunci = '' THEN
      RETURN false;
    END IF;
    IF COALESCE(v_login, false)
       AND v_hp IS NOT NULL
       AND btrim(v_hp) <> ''
       AND btrim(v_hp) IS DISTINCT FROM v_kunci THEN
      RETURN false;
    END IF;
    UPDATE public.users
    SET
      is_login = true,
      kunci_hp = v_kunci,
      sesi_login = v_sesi
    WHERE lower(trim(email)) = v_email;
    RETURN FOUND;
  END IF;

  IF v_hp IS NOT NULL
     AND btrim(v_hp) <> ''
     AND v_kunci <> ''
     AND btrim(v_hp) IS DISTINCT FROM v_kunci THEN
    RETURN false;
  END IF;

  UPDATE public.users
  SET
    is_login = false,
    kunci_hp = NULL,
    sesi_login = NULL
  WHERE lower(trim(email)) = v_email;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_profil()
RETURNS TABLE (
  email text,
  nama text,
  peran text,
  rute text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  RETURN QUERY
  SELECT
    u.email,
    u.nama,
    u.peran,
    COALESCE(u.rute, '')
  FROM public.users u
  WHERE lower(trim(u.email)) = public.email_jwt()
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.email_jwt() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sesi_jwt() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hp_sedang_login(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sales_sedang_login() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gudang_sedang_login() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pengirim_sedang_login() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_sedang_login() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hp_apply_is_login(boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_profil() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.email_jwt() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sesi_jwt() TO authenticated;
GRANT EXECUTE ON FUNCTION public.hp_sedang_login(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sales_sedang_login() TO authenticated;
GRANT EXECUTE ON FUNCTION public.gudang_sedang_login() TO authenticated;
GRANT EXECUTE ON FUNCTION public.pengirim_sedang_login() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_sedang_login() TO authenticated;
GRANT EXECUTE ON FUNCTION public.hp_apply_is_login(boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_profil() TO authenticated;

GRANT EXECUTE ON FUNCTION public.email_jwt() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.sesi_jwt() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.hp_sedang_login(text[]) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.sales_sedang_login() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.gudang_sedang_login() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.pengirim_sedang_login() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_sedang_login() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.hp_apply_is_login(boolean, text) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_profil() TO postgres, service_role;

NOTIFY pgrst, 'reload schema';
