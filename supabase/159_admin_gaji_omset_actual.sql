-- Insentif omset admin: pakai omset actual cap buku Senin–Sabtu
-- (bukan omset margin yang bisa beda). Jalankan SETELAH 150. Jangan UPDATE pelanggan.

DROP FUNCTION IF EXISTS public.admin_gaji_rute_minggu(date);

CREATE FUNCTION public.admin_gaji_rute_minggu(p_senin date)
RETURNS TABLE (
  rute text,
  nama text,
  omset bigint,
  rasio numeric,
  visit integer,
  toko integer,
  ec integer,
  omset_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
SET statement_timeout = '60s'
AS $$
DECLARE
  v_senin date;
  v_sabtu date;
  r record;
  v_omset bigint;
  v_rasio numeric;
  v_toko integer;
  v_cap jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_senin := COALESCE(p_senin, (timezone('Asia/Jakarta', now()))::date);
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::integer) - 1);
  v_sabtu := v_senin + 5;

  FOR r IN
    SELECT btrim(u.rute) AS rute, btrim(u.nama) AS nama
    FROM public.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
    ORDER BY u.rute
  LOOP
    SELECT COALESCE(tg.omset, 0), COALESCE(tg.rasio, 0)
    INTO v_omset, v_rasio
    FROM public.gaji_target_pada(r.rute, v_senin) tg
    LIMIT 1;
    v_toko := public.gaji_n_toko_rute(r.rute, v_senin);
    v_cap := public._admin_dashboard_capaian(r.rute, v_senin, v_sabtu, v_toko);
    rute := r.rute;
    nama := r.nama;
    omset := COALESCE(v_omset, 0);
    rasio := COALESCE(v_rasio, 0);
    visit := COALESCE((v_cap->>'visit')::integer, 0);
    toko := GREATEST(COALESCE(v_toko, 0), 0);
    ec := COALESCE((v_cap->>'ec_actual')::integer, 0);
    omset_actual := COALESCE((v_cap->>'omset_actual')::bigint, 0);
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gaji_rute_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_rute_minggu(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_gaji_rute_minggu(date) IS
  'Target + visit/EC + omset actual minggu untuk insentif omset.';

NOTIFY pgrst, 'reload schema';
