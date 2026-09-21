-- Target omset / rasio laba salesman. Jalankan SETELAH 001_login.sql.
-- Isi angka di Table Editor (public.target_sales). Aplikasi hanya membaca.

CREATE TABLE IF NOT EXISTS public.target_sales (
  email text PRIMARY KEY REFERENCES public.users (email) ON DELETE CASCADE,
  target_omset integer NOT NULL DEFAULT 0,
  target_persen_laba numeric NOT NULL DEFAULT 0,
  CONSTRAINT target_sales_email_chk CHECK (btrim(email) <> ''),
  CONSTRAINT target_sales_omset_chk CHECK (target_omset >= 0),
  CONSTRAINT target_sales_persen_chk CHECK (target_persen_laba >= 0)
);

COMMENT ON TABLE public.target_sales IS
  'Satu baris = target dashboard satu akun sales. Terpisah dari users.';
COMMENT ON COLUMN public.target_sales.email IS
  'Kunci akun. Sama dengan public.users.email.';
COMMENT ON COLUMN public.target_sales.target_omset IS
  'Target omset mingguan (rupiah).';
COMMENT ON COLUMN public.target_sales.target_persen_laba IS
  'Target rasio laba (%).';

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.target_sales
  TO postgres, service_role;
GRANT SELECT ON TABLE public.target_sales TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.target_sales FROM authenticated;
REVOKE ALL ON TABLE public.target_sales FROM anon;

ALTER TABLE public.target_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_sales FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS target_sales_select ON public.target_sales;
CREATE POLICY target_sales_select
  ON public.target_sales
  FOR SELECT
  TO authenticated
  USING (
    lower(btrim(email)) = lower(btrim(COALESCE(auth.jwt() ->> 'email', '')))
  );

NOTIFY pgrst, 'reload schema';

