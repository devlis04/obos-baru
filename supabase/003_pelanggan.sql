-- Master pelanggan salesman. Jalankan SETELAH 001_login.sql
-- SQL Editor project yang sama dengan obos_baru, skema public. Jangan ubah skema obos.
-- SQL Editor → Run. Boleh di-Run ulang.

CREATE TABLE IF NOT EXISTS public.pelanggan (
  id_pelanggan text PRIMARY KEY,
  nama_pelanggan text NOT NULL,
  rute text,
  visit text,
  urutan integer,
  latitude double precision,
  longitude double precision,
  aktif boolean NOT NULL DEFAULT true,
  CONSTRAINT pelanggan_id_chk CHECK (btrim(id_pelanggan) <> ''),
  CONSTRAINT pelanggan_nama_chk CHECK (btrim(nama_pelanggan) <> '')
);

COMMENT ON TABLE public.pelanggan IS
  'Satu baris = satu toko. Kunjungan harian bukan di sini.';
COMMENT ON COLUMN public.pelanggan.id_pelanggan IS 'Kode SBGO….';
COMMENT ON COLUMN public.pelanggan.rute IS 'Rute salesman pemilik (mis. SBGS01).';
COMMENT ON COLUMN public.pelanggan.visit IS 'Hari kunjungan: Senin … Minggu.';
COMMENT ON COLUMN public.pelanggan.urutan IS 'Urutan di hari kunjungan itu.';
COMMENT ON COLUMN public.pelanggan.aktif IS 'false = disembunyikan dari salesman.';

CREATE INDEX IF NOT EXISTS pelanggan_rute_urutan_idx
  ON public.pelanggan (rute, urutan);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.pelanggan TO postgres, service_role;
GRANT SELECT ON TABLE public.pelanggan TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.pelanggan FROM authenticated;
REVOKE ALL ON TABLE public.pelanggan FROM anon;

ALTER TABLE public.pelanggan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pelanggan FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.rute_sales_saya()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT nullif(btrim(u.rute), '')
  FROM public.users u
  WHERE lower(trim(u.email)) = public.email_jwt()
    AND u.peran = 'sales'
  LIMIT 1;
$$;

DROP POLICY IF EXISTS pelanggan_select_sales ON public.pelanggan;
CREATE POLICY pelanggan_select_sales
  ON public.pelanggan
  FOR SELECT
  TO authenticated
  USING (
    public.rute_sales_saya() IS NOT NULL
    AND rute = public.rute_sales_saya()
    AND COALESCE(aktif, true)
  );

CREATE OR REPLACE FUNCTION public.sales_set_urutan(
  p_visit text,
  p_id text[]
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rute text;
  v_n integer;
  v_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.sales_sedang_login() THEN
    RETURN false;
  END IF;
  IF p_visit IS NULL OR btrim(p_visit) = '' THEN
    RETURN false;
  END IF;
  IF p_id IS NULL OR cardinality(p_id) IS NULL OR cardinality(p_id) = 0 THEN
    RETURN false;
  END IF;

  v_rute := public.rute_sales_saya();
  IF v_rute IS NULL THEN
    RETURN false;
  END IF;

  v_n := cardinality(p_id);
  IF (SELECT COUNT(DISTINCT k) FROM unnest(p_id) AS k) <> v_n THEN
    RETURN false;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.pelanggan
  WHERE rute = v_rute
    AND visit = p_visit
    AND COALESCE(aktif, true);

  IF v_count <> v_n THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(p_id) AS k
    LEFT JOIN public.pelanggan p
      ON p.id_pelanggan = k
     AND p.rute = v_rute
     AND p.visit = p_visit
     AND COALESCE(p.aktif, true)
    WHERE p.id_pelanggan IS NULL
  ) THEN
    RETURN false;
  END IF;

  UPDATE public.pelanggan p
  SET urutan = x.ord::integer
  FROM unnest(p_id) WITH ORDINALITY AS x(id_pelanggan, ord)
  WHERE p.id_pelanggan = x.id_pelanggan
    AND p.rute = v_rute
    AND p.visit = p_visit
    AND COALESCE(p.aktif, true);

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.next_id_pelanggan()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  max_num integer := 0;
  max_lebar integer := 4;
  v_next integer;
  v_lebar integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Tidak terautentikasi';
  END IF;
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;

  PERFORM pg_advisory_xact_lock(872342);

  SELECT
    COALESCE(MAX(NULLIF(substring(id_pelanggan from 5), '')::integer), 0),
    COALESCE(MAX(length(substring(id_pelanggan from 5))), 4)
  INTO max_num, max_lebar
  FROM public.pelanggan
  WHERE id_pelanggan ~ '^SBGO[0-9]+$';

  v_next := max_num + 1;
  v_lebar := GREATEST(max_lebar, length(v_next::text));
  RETURN 'SBGO' || lpad(v_next::text, v_lebar, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.sales_insert_pelanggan(
  p_nama text,
  p_latitude double precision,
  p_longitude double precision,
  p_visit text,
  p_urutan integer
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_nama text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Tidak terautentikasi';
  END IF;
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;

  v_rute := public.rute_sales_saya();
  IF v_rute IS NULL THEN
    RAISE EXCEPTION 'Rute salesman kosong';
  END IF;

  v_nama := upper(btrim(COALESCE(p_nama, '')));
  IF v_nama = '' THEN
    RAISE EXCEPTION 'Nama toko kosong';
  END IF;
  IF p_visit IS NULL OR btrim(p_visit) = '' THEN
    RAISE EXCEPTION 'Hari kunjungan kosong';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'Koordinat toko kosong';
  END IF;

  v_id := public.next_id_pelanggan();

  INSERT INTO public.pelanggan (
    id_pelanggan,
    nama_pelanggan,
    latitude,
    longitude,
    rute,
    visit,
    urutan,
    aktif
  )
  VALUES (
    v_id,
    v_nama,
    p_latitude,
    p_longitude,
    v_rute,
    btrim(p_visit),
    COALESCE(p_urutan, 0),
    true
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.rute_sales_saya() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sales_set_urutan(text, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.next_id_pelanggan() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sales_insert_pelanggan(text, double precision, double precision, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.rute_sales_saya() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sales_set_urutan(text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sales_insert_pelanggan(text, double precision, double precision, text, integer) TO authenticated;

REVOKE ALL ON FUNCTION public.next_id_pelanggan() FROM authenticated;

NOTIFY pgrst, 'reload schema';
