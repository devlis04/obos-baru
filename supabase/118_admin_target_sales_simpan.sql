-- Admin ubah target omset / rasio per rute (tabel target_sales).
-- Jalankan SETELAH 009. Boleh diulang.

ALTER TABLE public.target_sales
  ALTER COLUMN target_omset TYPE bigint;

COMMENT ON COLUMN public.target_sales.target_omset IS
  'Target omset mingguan (rupiah). 0 = tidak ada target.';
COMMENT ON COLUMN public.target_sales.target_persen_laba IS
  'Target rasio laba (%). 0 = tidak ada target.';

DROP FUNCTION IF EXISTS public.admin_target_sales_simpan(jsonb);
CREATE FUNCTION public.admin_target_sales_simpan(p_isi jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  el jsonb;
  v_rute text;
  v_email text;
  v_omset bigint;
  v_rasio numeric;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_isi IS NULL OR jsonb_typeof(p_isi) <> 'array' THEN
    RAISE EXCEPTION 'Isi target sales tidak sah.';
  END IF;

  FOR el IN SELECT jsonb_array_elements(p_isi)
  LOOP
    v_rute := btrim(COALESCE(el ->> 'rute', ''));
    IF v_rute = '' THEN
      RAISE EXCEPTION 'Rute target sales kosong.';
    END IF;
    v_omset := GREATEST(COALESCE((el ->> 'omset')::bigint, 0), 0);
    v_rasio := GREATEST(COALESCE((el ->> 'rasio')::numeric, 0), 0);

    SELECT u.email
    INTO v_email
    FROM public.users u
    WHERE u.peran = 'sales'
      AND btrim(u.rute) = v_rute
    ORDER BY u.email
    LIMIT 1;

    IF v_email IS NULL THEN
      RAISE EXCEPTION 'Tidak ada akun sales untuk rute %.', v_rute;
    END IF;

    INSERT INTO public.target_sales (email, target_omset, target_persen_laba)
    VALUES (v_email, v_omset, v_rasio)
    ON CONFLICT (email) DO UPDATE SET
      target_omset = EXCLUDED.target_omset,
      target_persen_laba = EXCLUDED.target_persen_laba;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_target_sales_simpan(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_target_sales_simpan(jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
