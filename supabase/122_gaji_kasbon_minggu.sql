-- Overlay kasbon gaji per orang per minggu Senin.
-- Tidak menulis setoran_pengirim / public.kasbon (opname).
-- Nilai 0 tetap disimpan supaya menimpa angka lapangan.
-- Jalankan SETELAH 119. Boleh diulang.

CREATE TABLE IF NOT EXISTS public.gaji_kasbon_minggu (
  senin date NOT NULL,
  email text NOT NULL,
  nilai bigint NOT NULL DEFAULT 0 CHECK (nilai >= 0),
  PRIMARY KEY (senin, email),
  CONSTRAINT gaji_kasbon_minggu_email_chk CHECK (btrim(email) <> '')
);

COMMENT ON TABLE public.gaji_kasbon_minggu IS
  'Kasbon tampil di dialog gaji. Arsip payroll, bukan utang opname.';

ALTER TABLE public.gaji_kasbon_minggu ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gaji_kasbon_minggu FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.gaji_kasbon_minggu FROM PUBLIC;
REVOKE ALL ON TABLE public.gaji_kasbon_minggu FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.gaji_kasbon_minggu
  TO postgres, service_role;

DROP FUNCTION IF EXISTS public.admin_gaji_kasbon_minggu(date);
CREATE FUNCTION public.admin_gaji_kasbon_minggu(p_senin date)
RETURNS TABLE (email text, nilai bigint)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_senin IS NULL THEN
    RAISE EXCEPTION 'Senin minggu kosong.';
  END IF;

  RETURN QUERY
  SELECT lower(btrim(g.email)), g.nilai
  FROM public.gaji_kasbon_minggu g
  WHERE g.senin = p_senin;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_gaji_kasbon_minggu_simpan(date, jsonb);
CREATE FUNCTION public.admin_gaji_kasbon_minggu_simpan(p_senin date, p_isi jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  el jsonb;
  v_email text;
  v_nilai bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_senin IS NULL THEN
    RAISE EXCEPTION 'Senin minggu kosong.';
  END IF;
  IF p_isi IS NULL OR jsonb_typeof(p_isi) <> 'array' THEN
    RAISE EXCEPTION 'Isi kasbon gaji tidak sah.';
  END IF;

  FOR el IN SELECT jsonb_array_elements(p_isi)
  LOOP
    v_email := lower(btrim(COALESCE(el ->> 'email', '')));
    IF v_email = '' THEN
      CONTINUE;
    END IF;
    v_nilai := GREATEST(COALESCE((el ->> 'nilai')::bigint, 0), 0);

    INSERT INTO public.gaji_kasbon_minggu (senin, email, nilai)
    VALUES (p_senin, v_email, v_nilai)
    ON CONFLICT (senin, email) DO UPDATE SET
      nilai = EXCLUDED.nilai;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gaji_kasbon_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon_minggu(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_kasbon_minggu_simpan(date, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon_minggu_simpan(date, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
