-- Patokan minggu: RETURNS TABLE + RPC ringkas gaji (tanpa hari).
-- Perbaiki gaji_target_pada (jangan dobel baris) dan timeout dashboard.
-- Boleh diulang. Tidak mengubah patokan/snapshot.

DROP FUNCTION IF EXISTS public.admin_gaji_setelan_minggu(date);

CREATE FUNCTION public.admin_gaji_setelan_minggu(p_senin date)
RETURNS TABLE (
  id integer,
  bop_mobil bigint,
  ongkir_semua bigint,
  sales_net bigint,
  sales_visit bigint,
  sales_ec bigint,
  pengirim bigint,
  gudang bigint,
  gudang_slot integer,
  admin bigint,
  omset_semua bigint,
  rasio_sales numeric,
  visit_target numeric,
  ec_target numeric
)
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
  RETURN QUERY
  SELECT
    1,
    p.bop_mobil,
    p.ongkir_semua,
    p.sales_net,
    p.sales_visit,
    p.sales_ec,
    p.pengirim,
    p.gudang,
    p.gudang_slot,
    p.admin,
    p.omset_semua,
    p.rasio_sales,
    p.visit_target,
    p.ec_target
  FROM public.gaji_baca_patokan(p_senin) p;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_target_pada(p_rute text, p_senin date)
RETURNS TABLE (omset bigint, rasio numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text := btrim(COALESCE(p_rute, ''));
BEGIN
  IF p_senin IS NOT NULL AND p_senin < DATE '2026-10-12'
     AND EXISTS (
       SELECT 1 FROM public.gaji_target_rute_snap s WHERE s.rute = v_rute
     ) THEN
    RETURN QUERY
    SELECT s.omset, s.rasio
    FROM public.gaji_target_rute_snap s
    WHERE s.rute = v_rute;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    GREATEST(COALESCE(t.target_omset, 0), 0)::bigint,
    GREATEST(COALESCE(t.target_persen_laba, 0), 0)
  FROM public.users u
  LEFT JOIN public.target_sales t ON lower(btrim(t.email)) = lower(btrim(u.email))
  WHERE u.peran = 'sales'
    AND btrim(u.rute) = v_rute
  ORDER BY u.email
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_dashboard_rute(
  p_rute text,
  p_nama text,
  p_email text,
  p_senin date,
  p_sabtu date,
  p_hari date,
  p_nama_hari text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_omset bigint := 0;
  v_persen numeric := 0;
  v_toko integer := 0;
  v_toko_hari integer := 0;
  v_m jsonb;
  v_h jsonb;
BEGIN
  SELECT COALESCE(tg.omset, 0), COALESCE(tg.rasio, 0)
  INTO v_omset, v_persen
  FROM public.gaji_target_pada(p_rute, p_senin) tg
  LIMIT 1;

  v_toko := public.gaji_n_toko_rute(p_rute, p_senin);

  SELECT count(*)::integer
  INTO v_toko_hari
  FROM public.pelanggan p
  WHERE btrim(p.rute) = p_rute
    AND COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(p.visit, '')) = p_nama_hari;

  v_m := public._admin_dashboard_capaian(p_rute, p_senin, p_sabtu, v_toko);
  v_h := public._admin_dashboard_capaian(p_rute, p_hari, p_hari, v_toko_hari);

  RETURN jsonb_build_object(
    'rute', p_rute,
    'nama', p_nama,
    'target_omset', v_omset,
    'target_persen', v_persen,
    'minggu', v_m,
    'hari', v_h
  );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_gaji_rute_minggu(date);

CREATE FUNCTION public.admin_gaji_rute_minggu(p_senin date)
RETURNS TABLE (
  rute text,
  nama text,
  omset bigint,
  rasio numeric,
  visit integer,
  toko integer,
  ec integer
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
    RETURN NEXT;
  END LOOP;
END;
$$;

ALTER FUNCTION public.admin_dashboard(date, date) SET statement_timeout = '60s';

REVOKE ALL ON FUNCTION public.admin_gaji_setelan_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_setelan_minggu(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_target_pada(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_target_pada(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_rute_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_rute_minggu(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
