-- Kunci Benefit Senin–Sabtu saat buku Sabtu ditutup.
-- Hitung minggu beku hanya baca snapshot. Jangan UPDATE pelanggan.
-- Jalankan SETELAH 165. Boleh diulang: snapshot tidak ditimpa.

CREATE TABLE IF NOT EXISTS public.gaji_minggu_patokan (
  senin date PRIMARY KEY,
  sabtu date NOT NULL,
  id_buku bigint,
  waktu timestamptz NOT NULL DEFAULT clock_timestamp(),
  bop_mobil bigint NOT NULL DEFAULT 0,
  ongkir_semua bigint NOT NULL DEFAULT 0,
  sales_net bigint NOT NULL DEFAULT 0,
  sales_visit bigint NOT NULL DEFAULT 0,
  sales_ec bigint NOT NULL DEFAULT 0,
  pengirim bigint NOT NULL DEFAULT 0,
  gudang bigint NOT NULL DEFAULT 0,
  gudang_slot integer NOT NULL DEFAULT 1,
  admin bigint NOT NULL DEFAULT 0,
  omset_semua bigint NOT NULL DEFAULT 0,
  rasio_sales numeric NOT NULL DEFAULT 0,
  visit_target numeric NOT NULL DEFAULT 0,
  ec_target numeric NOT NULL DEFAULT 0,
  insentif bigint NOT NULL DEFAULT 0,
  net_min numeric NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.gaji_minggu_rute (
  senin date NOT NULL REFERENCES public.gaji_minggu_patokan (senin)
    ON DELETE CASCADE,
  rute text NOT NULL,
  nama text NOT NULL DEFAULT '',
  omset bigint NOT NULL DEFAULT 0,
  rasio numeric NOT NULL DEFAULT 0,
  visit integer NOT NULL DEFAULT 0,
  toko integer NOT NULL DEFAULT 0,
  ec integer NOT NULL DEFAULT 0,
  omset_actual bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (senin, rute)
);

COMMENT ON TABLE public.gaji_minggu_patokan IS
  'Patokan Benefit dikunci saat tutup buku Sabtu. Senin = awal minggu.';
COMMENT ON TABLE public.gaji_minggu_rute IS
  'Target, kolam toko, visit, EC, omset actual per rute untuk minggu beku.';

ALTER TABLE public.gaji_minggu_patokan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gaji_minggu_patokan FORCE ROW LEVEL SECURITY;
ALTER TABLE public.gaji_minggu_rute ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gaji_minggu_rute FORCE ROW LEVEL SECURITY;

GRANT SELECT ON TABLE public.gaji_minggu_patokan
  TO authenticated, postgres, service_role;
GRANT SELECT ON TABLE public.gaji_minggu_rute
  TO authenticated, postgres, service_role;
GRANT INSERT, UPDATE, DELETE ON TABLE public.gaji_minggu_patokan
  TO postgres, service_role;
GRANT INSERT, UPDATE, DELETE ON TABLE public.gaji_minggu_rute
  TO postgres, service_role;
REVOKE ALL ON TABLE public.gaji_minggu_patokan FROM anon;
REVOKE ALL ON TABLE public.gaji_minggu_rute FROM anon;

DROP POLICY IF EXISTS gaji_minggu_patokan_select ON public.gaji_minggu_patokan;
CREATE POLICY gaji_minggu_patokan_select
  ON public.gaji_minggu_patokan
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS gaji_minggu_rute_select ON public.gaji_minggu_rute;
CREATE POLICY gaji_minggu_rute_select
  ON public.gaji_minggu_rute
  FOR SELECT TO authenticated
  USING (true);

CREATE OR REPLACE FUNCTION public.gaji_minggu_senin(p_hari date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_hari IS NULL THEN NULL
    ELSE p_hari - ((EXTRACT(ISODOW FROM p_hari)::integer) - 1)
  END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_id_buku_sabtu_tutup(p_senin date)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_senin date;
  v_sabtu date;
  v_id bigint;
BEGIN
  v_senin := public.gaji_minggu_senin(p_senin);
  IF v_senin IS NULL THEN
    RETURN NULL;
  END IF;
  v_sabtu := v_senin + 5;

  SELECT b.id INTO v_id
  FROM public.setoran_buku b
  WHERE b.ditutup
    AND (
      b.tanggal = v_sabtu
      OR (b.waktu_tutup AT TIME ZONE 'Asia/Jakarta')::date = v_sabtu
    )
  ORDER BY
    CASE WHEN b.tanggal = v_sabtu THEN 0 ELSE 1 END,
    b.id DESC
  LIMIT 1;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_kunci_minggu(p_senin date, p_id_buku bigint)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
SET row_security = off
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
  v_senin := public.gaji_minggu_senin(p_senin);
  IF v_senin IS NULL OR v_senin < DATE '2026-10-12' THEN
    RETURN false;
  END IF;
  v_sabtu := v_senin + 5;

  PERFORM pg_advisory_xact_lock(hashtext('gaji_kunci:' || v_senin::text));

  IF EXISTS (
    SELECT 1 FROM public.gaji_minggu_patokan k WHERE k.senin = v_senin
  ) THEN
    RETURN true;
  END IF;

  INSERT INTO public.gaji_minggu_patokan (
    senin, sabtu, id_buku,
    bop_mobil, ongkir_semua, sales_net, sales_visit, sales_ec,
    pengirim, gudang, gudang_slot, admin, omset_semua, rasio_sales,
    visit_target, ec_target, insentif, net_min
  )
  SELECT
    v_senin, v_sabtu, p_id_buku,
    p.bop_mobil, p.ongkir_semua, p.sales_net, p.sales_visit, p.sales_ec,
    p.pengirim, p.gudang, p.gudang_slot, p.admin, p.omset_semua, p.rasio_sales,
    p.visit_target, p.ec_target, p.insentif, p.net_min
  FROM public.gaji_baca_patokan(v_senin) p;

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
    INSERT INTO public.gaji_minggu_rute (
      senin, rute, nama, omset, rasio, visit, toko, ec, omset_actual
    ) VALUES (
      v_senin,
      r.rute,
      COALESCE(r.nama, ''),
      COALESCE(v_omset, 0),
      COALESCE(v_rasio, 0),
      COALESCE((v_cap->>'visit')::integer, 0),
      GREATEST(COALESCE(v_toko, 0), 0),
      COALESCE((v_cap->>'ec_actual')::integer, 0),
      COALESCE((v_cap->>'omset_actual')::bigint, 0)
    )
    ON CONFLICT (senin, rute) DO NOTHING;
  END LOOP;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_kunci_minggu_otomatis(p_senin date)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_senin date;
  v_id bigint;
BEGIN
  v_senin := public.gaji_minggu_senin(p_senin);
  IF v_senin IS NULL OR v_senin < DATE '2026-10-12' THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.gaji_minggu_patokan k WHERE k.senin = v_senin
  ) THEN
    RETURN true;
  END IF;
  v_id := public.gaji_id_buku_sabtu_tutup(v_senin);
  IF v_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.gaji_kunci_minggu(v_senin, v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_setelah_buku_tutup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sabtu date;
BEGIN
  IF NOT (NEW.ditutup AND NOT COALESCE(OLD.ditutup, false)) THEN
    RETURN NEW;
  END IF;
  v_sabtu := NEW.tanggal;
  IF EXTRACT(ISODOW FROM v_sabtu)::integer IS DISTINCT FROM 6 THEN
    v_sabtu := (COALESCE(NEW.waktu_tutup, clock_timestamp())
      AT TIME ZONE 'Asia/Jakarta')::date;
  END IF;
  IF EXTRACT(ISODOW FROM v_sabtu)::integer = 6 THEN
    PERFORM public.gaji_kunci_minggu_otomatis(v_sabtu - 5);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS gaji_kunci_saat_buku_tutup ON public.setoran_buku;
CREATE TRIGGER gaji_kunci_saat_buku_tutup
  AFTER UPDATE OF ditutup ON public.setoran_buku
  FOR EACH ROW
  EXECUTE FUNCTION public.gaji_setelah_buku_tutup();

CREATE OR REPLACE FUNCTION public.gaji_baca_patokan(p_senin date)
RETURNS TABLE (
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
  ec_target numeric,
  insentif bigint,
  net_min numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_senin date;
BEGIN
  v_senin := public.gaji_minggu_senin(p_senin);

  IF v_senin IS NOT NULL AND v_senin < DATE '2026-10-12' THEN
    RETURN QUERY
    SELECT
      s.bop_mobil, s.ongkir_semua, s.sales_net, s.sales_visit, s.sales_ec,
      s.pengirim, s.gudang, s.gudang_slot, s.admin, s.omset_semua, s.rasio_sales,
      s.visit_target, s.ec_target, s.insentif, s.net_min
    FROM public.gaji_setelan_snap s
    WHERE s.id = 1;
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;

  IF v_senin IS NOT NULL THEN
    RETURN QUERY
    SELECT
      k.bop_mobil, k.ongkir_semua, k.sales_net, k.sales_visit, k.sales_ec,
      k.pengirim, k.gudang, k.gudang_slot, k.admin, k.omset_semua, k.rasio_sales,
      k.visit_target, k.ec_target, k.insentif, k.net_min
    FROM public.gaji_minggu_patokan k
    WHERE k.senin = v_senin;
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    g.bop_mobil, g.ongkir_semua, g.sales_net, g.sales_visit, g.sales_ec,
    g.pengirim, g.gudang, g.gudang_slot, g.admin, g.omset_semua, g.rasio_sales,
    g.visit_target, g.ec_target, g.insentif, g.net_min
  FROM public.gaji_setelan g
  WHERE g.id = 1;
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
  v_senin date;
BEGIN
  v_senin := public.gaji_minggu_senin(p_senin);

  IF v_senin IS NOT NULL AND v_senin < DATE '2026-10-12'
     AND EXISTS (
       SELECT 1 FROM public.gaji_target_rute_snap s WHERE s.rute = v_rute
     ) THEN
    RETURN QUERY
    SELECT s.omset, s.rasio
    FROM public.gaji_target_rute_snap s
    WHERE s.rute = v_rute;
    RETURN;
  END IF;

  IF v_senin IS NOT NULL THEN
    RETURN QUERY
    SELECT s.omset, s.rasio
    FROM public.gaji_minggu_rute s
    WHERE s.senin = v_senin AND s.rute = v_rute;
    IF FOUND THEN
      RETURN;
    END IF;
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

CREATE OR REPLACE FUNCTION public.gaji_n_toko_rute(p_rute text, p_senin date)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer;
  v_hari date;
  v_senin date;
  v_as_of date;
  v_kode text;
BEGIN
  v_kode := btrim(COALESCE(p_rute, ''));
  IF v_kode = '' THEN
    RETURN 0;
  END IF;

  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_senin := public.gaji_minggu_senin(COALESCE(p_senin, v_hari));
  v_as_of := LEAST(v_hari, v_senin + 5);

  IF v_senin < DATE '2026-10-12' THEN
    SELECT s.n_toko INTO v_n
    FROM public.gaji_toko_rute_snap s
    WHERE s.rute = v_kode;
    IF FOUND THEN
      RETURN GREATEST(COALESCE(v_n, 0), 0);
    END IF;
  END IF;

  SELECT s.toko INTO v_n
  FROM public.gaji_minggu_rute s
  WHERE s.senin = v_senin AND s.rute = v_kode;
  IF FOUND THEN
    RETURN GREATEST(COALESCE(v_n, 0), 0);
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(
      public.gaji_rute_toko_pada(p.id_pelanggan, v_as_of, v_senin),
      ''
    )) = v_kode;
  RETURN GREATEST(COALESCE(v_n, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_n_toko_semua(p_senin date)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer;
  v_hari date;
  v_senin date;
  v_as_of date;
BEGIN
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_senin := public.gaji_minggu_senin(COALESCE(p_senin, v_hari));
  v_as_of := LEAST(v_hari, v_senin + 5);

  IF v_senin < DATE '2026-10-12' THEN
    SELECT coalesce(sum(s.n_toko), 0)::integer INTO v_n
    FROM public.gaji_toko_rute_snap s
    WHERE s.rute IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );
    IF COALESCE(v_n, 0) > 0 THEN
      RETURN v_n;
    END IF;
  END IF;

  SELECT coalesce(sum(s.toko), 0)::integer INTO v_n
  FROM public.gaji_minggu_rute s
  WHERE s.senin = v_senin;
  IF COALESCE(v_n, 0) > 0 THEN
    RETURN v_n;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(
      public.gaji_rute_toko_pada(p.id_pelanggan, v_as_of, v_senin),
      ''
    )) IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );
  RETURN GREATEST(COALESCE(v_n, 0), 0);
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
  ec integer,
  omset_actual bigint
)
LANGUAGE plpgsql
VOLATILE
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

  v_senin := public.gaji_minggu_senin(
    COALESCE(p_senin, (timezone('Asia/Jakarta', now()))::date)
  );
  v_sabtu := v_senin + 5;

  IF public.gaji_kunci_minggu_otomatis(v_senin) THEN
    RETURN QUERY
    SELECT
      s.rute, s.nama, s.omset, s.rasio, s.visit, s.toko, s.ec, s.omset_actual
    FROM public.gaji_minggu_rute s
    WHERE s.senin = v_senin
    ORDER BY s.rute;
    RETURN;
  END IF;

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

REVOKE ALL ON FUNCTION public.gaji_minggu_senin(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_minggu_senin(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_id_buku_sabtu_tutup(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_id_buku_sabtu_tutup(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_kunci_minggu(date, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_kunci_minggu(date, bigint)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_kunci_minggu_otomatis(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_kunci_minggu_otomatis(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_baca_patokan(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_baca_patokan(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_target_pada(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_target_pada(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_n_toko_rute(text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_n_toko_rute(text, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_n_toko_rute(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_n_toko_semua(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_n_toko_semua(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_n_toko_semua(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_rute_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_rute_minggu(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_gaji_rute_minggu(date) IS
  'Benefit rute: hidup jika buku Sabtu belum tutup; beku setelah snapshot.';

NOTIFY pgrst, 'reload schema';
