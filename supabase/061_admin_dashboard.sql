-- Dashboard admin: total + per rute. Minggu Senin–Sabtu (Asia/Jakarta).
-- Omset/laba jual dari v_transaksi_item (strata). Nota batal tidak dihitung.
-- Jalankan SETELAH 060. SQL Editor → Run. Boleh di-Run ulang.

DROP FUNCTION IF EXISTS public.admin_dashboard(date, date);
DROP FUNCTION IF EXISTS public._admin_dashboard_rute(text, text, text, date, date, date, text);
DROP FUNCTION IF EXISTS public._admin_dashboard_capaian(text, date, date, integer);
DROP FUNCTION IF EXISTS public._admin_dashboard_jumlah(jsonb, date, date, date, text);
DROP FUNCTION IF EXISTS public._admin_dashboard_capaian_semua(date, date, integer);

CREATE FUNCTION public._admin_dashboard_capaian(
  p_rute text,
  p_dari date,
  p_sampai date,
  p_toko integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  WITH nota AS (
    SELECT
      t.id_transaksi,
      t.id_pelanggan,
      t.status
    FROM public.transaksi t
    WHERE t.status <> 'batal'
      AND btrim(t.rute) = p_rute
      AND (timezone('Asia/Jakarta', t.waktu_order))::date >= p_dari
      AND (timezone('Asia/Jakarta', t.waktu_order))::date <= p_sampai
  ),
  uang AS (
    SELECT
      COALESCE(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      COALESCE(sum(i.subtotal_beli_order), 0)::bigint AS modal_order,
      COALESCE(sum(i.subtotal_jual_packed), 0)::bigint AS omset_kiriman,
      COALESCE(sum(i.subtotal_beli_packed), 0)::bigint AS modal_kiriman,
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan
    FROM nota n
    WHERE n.status IN ('dikirim', 'terkirim')
       OR EXISTS (
         SELECT 1
         FROM public.transaksi_items i
         WHERE i.id_transaksi = n.id_transaksi
           AND i.qty_packed IS NOT NULL
       )
  ),
  ec AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE btrim(COALESCE(n.id_pelanggan, '')) <> ''
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE btrim(COALESCE(k.id_pelanggan, '')) <> ''
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND btrim(COALESCE(n.id_pelanggan, '')) <> ''
      )::integer AS ec_actual,
      count(*)::integer AS nota_order,
      (SELECT count(*)::integer FROM kirim) AS nota_kiriman,
      count(*) FILTER (WHERE n.status = 'terkirim')::integer AS nota_actual
    FROM nota n
  ),
  visit AS (
    SELECT count(DISTINCT k.id_pelanggan)::integer AS n
    FROM public.kunjungan_sales k
    WHERE btrim(k.rute) = p_rute
      AND k.tanggal >= p_dari
      AND k.tanggal <= p_sampai
      AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
  )
  SELECT jsonb_build_object(
    'omset_order', u.omset_order,
    'laba_order', u.omset_order - u.modal_order,
    'omset_kiriman', u.omset_kiriman,
    'laba_kiriman', u.omset_kiriman - u.modal_kiriman,
    'omset_actual', u.omset_actual,
    'laba_actual', u.omset_actual - u.modal_actual,
    'ec_order', e.ec_order,
    'ec_kiriman', e.ec_kiriman,
    'ec_actual', e.ec_actual,
    'nota_order', e.nota_order,
    'nota_kiriman', e.nota_kiriman,
    'nota_actual', e.nota_actual,
    'visit', v.n,
    'target_visit', GREATEST(p_toko, 1),
    'target_ec', GREATEST(p_toko, 1)
  )
  FROM uang u, ec e, visit v;
$$;

CREATE FUNCTION public._admin_dashboard_capaian_semua(
  p_dari date,
  p_sampai date,
  p_toko integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  WITH sales AS (
    SELECT btrim(u.rute) AS rute
    FROM public.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
  ),
  nota AS (
    SELECT
      t.id_transaksi,
      t.id_pelanggan,
      t.status
    FROM public.transaksi t
    WHERE t.status <> 'batal'
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND (timezone('Asia/Jakarta', t.waktu_order))::date >= p_dari
      AND (timezone('Asia/Jakarta', t.waktu_order))::date <= p_sampai
  ),
  uang AS (
    SELECT
      COALESCE(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      COALESCE(sum(i.subtotal_beli_order), 0)::bigint AS modal_order,
      COALESCE(sum(i.subtotal_jual_packed), 0)::bigint AS omset_kiriman,
      COALESCE(sum(i.subtotal_beli_packed), 0)::bigint AS modal_kiriman,
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan
    FROM nota n
    WHERE n.status IN ('dikirim', 'terkirim')
       OR EXISTS (
         SELECT 1
         FROM public.transaksi_items i
         WHERE i.id_transaksi = n.id_transaksi
           AND i.qty_packed IS NOT NULL
       )
  ),
  ec AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE btrim(COALESCE(n.id_pelanggan, '')) <> ''
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE btrim(COALESCE(k.id_pelanggan, '')) <> ''
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND btrim(COALESCE(n.id_pelanggan, '')) <> ''
      )::integer AS ec_actual,
      count(*)::integer AS nota_order,
      (SELECT count(*)::integer FROM kirim) AS nota_kiriman,
      count(*) FILTER (WHERE n.status = 'terkirim')::integer AS nota_actual
    FROM nota n
  ),
  visit AS (
    SELECT count(DISTINCT k.id_pelanggan)::integer AS n
    FROM public.kunjungan_sales k
    WHERE k.tanggal >= p_dari
      AND k.tanggal <= p_sampai
      AND btrim(k.rute) IN (SELECT rute FROM sales)
      AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
  )
  SELECT jsonb_build_object(
    'omset_order', u.omset_order,
    'laba_order', u.omset_order - u.modal_order,
    'omset_kiriman', u.omset_kiriman,
    'laba_kiriman', u.omset_kiriman - u.modal_kiriman,
    'omset_actual', u.omset_actual,
    'laba_actual', u.omset_actual - u.modal_actual,
    'ec_order', e.ec_order,
    'ec_kiriman', e.ec_kiriman,
    'ec_actual', e.ec_actual,
    'nota_order', e.nota_order,
    'nota_kiriman', e.nota_kiriman,
    'nota_actual', e.nota_actual,
    'visit', v.n,
    'target_visit', GREATEST(p_toko, 1),
    'target_ec', GREATEST(p_toko, 1)
  )
  FROM uang u, ec e, visit v;
$$;

CREATE FUNCTION public._admin_dashboard_rute(
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
  v_omset integer := 0;
  v_persen numeric := 0;
  v_toko integer := 0;
  v_toko_hari integer := 0;
  v_m jsonb;
  v_h jsonb;
BEGIN
  SELECT
    COALESCE(t.target_omset, 0),
    COALESCE(t.target_persen_laba, 0)
  INTO v_omset, v_persen
  FROM public.target_sales t
  WHERE lower(trim(t.email)) = p_email;

  IF NOT FOUND THEN
    v_omset := 0;
    v_persen := 0;
  END IF;

  SELECT count(*)::integer
  INTO v_toko
  FROM public.pelanggan p
  WHERE btrim(p.rute) = p_rute
    AND COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%';

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

CREATE FUNCTION public._admin_dashboard_jumlah(
  p_rute jsonb,
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
  v_bobot numeric := 0;
  v_persen numeric := 0;
  v_n integer := 0;
  v_toko integer := 0;
  v_toko_hari integer := 0;
  v_m jsonb;
  v_h jsonb;
  el jsonb;
BEGIN
  FOR el IN SELECT jsonb_array_elements(COALESCE(p_rute, '[]'::jsonb))
  LOOP
    v_n := v_n + 1;
    v_omset := v_omset + COALESCE((el ->> 'target_omset')::bigint, 0);
    v_bobot := v_bobot
      + COALESCE((el ->> 'target_omset')::numeric, 0)
      * COALESCE((el ->> 'target_persen')::numeric, 0);
    v_persen := v_persen + COALESCE((el ->> 'target_persen')::numeric, 0);
  END LOOP;

  IF v_omset > 0 THEN
    v_persen := v_bobot / v_omset;
  ELSIF v_n > 0 THEN
    v_persen := v_persen / v_n;
  ELSE
    v_persen := 0;
  END IF;

  SELECT count(*)::integer
  INTO v_toko
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(p.rute, '')) IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );

  SELECT count(*)::integer
  INTO v_toko_hari
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(p.visit, '')) = p_nama_hari
    AND btrim(COALESCE(p.rute, '')) IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );

  v_m := public._admin_dashboard_capaian_semua(p_senin, p_sabtu, v_toko);
  v_h := public._admin_dashboard_capaian_semua(p_hari, p_hari, v_toko_hari);

  RETURN jsonb_build_object(
    'rute', '',
    'nama', 'Total',
    'target_omset', v_omset,
    'target_persen', v_persen,
    'minggu', v_m,
    'hari', v_h
  );
END;
$$;

CREATE FUNCTION public.admin_dashboard(
  p_senin date DEFAULT NULL,
  p_hari date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hari date;
  v_senin date;
  v_sabtu date;
  v_nama_hari text;
  v_rute jsonb := '[]'::jsonb;
  v_satu jsonb;
  v_tot jsonb;
  r record;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_hari := COALESCE(p_hari, (timezone('Asia/Jakarta', now()))::date);
  v_senin := COALESCE(p_senin, v_hari);
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::integer) - 1);
  v_sabtu := v_senin + 5;
  IF v_hari < v_senin THEN
    v_hari := v_senin;
  ELSIF v_hari > v_sabtu THEN
    v_hari := v_sabtu;
  END IF;
  v_nama_hari := CASE EXTRACT(ISODOW FROM v_hari)::integer
    WHEN 1 THEN 'Senin'
    WHEN 2 THEN 'Selasa'
    WHEN 3 THEN 'Rabu'
    WHEN 4 THEN 'Kamis'
    WHEN 5 THEN 'Jumat'
    WHEN 6 THEN 'Sabtu'
    ELSE 'Minggu'
  END;

  FOR r IN
    SELECT
      btrim(u.rute) AS rute,
      btrim(u.nama) AS nama,
      lower(trim(u.email)) AS email
    FROM public.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
    ORDER BY u.rute
  LOOP
    v_satu := public._admin_dashboard_rute(
      r.rute,
      r.nama,
      r.email,
      v_senin,
      v_sabtu,
      v_hari,
      v_nama_hari
    );
    v_rute := v_rute || jsonb_build_array(v_satu);
  END LOOP;

  v_tot := public._admin_dashboard_jumlah(v_rute, v_senin, v_sabtu, v_hari, v_nama_hari);

  RETURN jsonb_build_object(
    'senin', v_senin,
    'sabtu', v_sabtu,
    'hari', v_hari,
    'total', v_tot,
    'rute', v_rute
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._admin_dashboard_rute(text, text, text, date, date, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._admin_dashboard_jumlah(jsonb, date, date, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian_semua(date, date, integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.admin_dashboard(date, date) FROM authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_rute(text, text, text, date, date, date, text) FROM authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) FROM authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_jumlah(jsonb, date, date, date, text) FROM authenticated;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian_semua(date, date, integer) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.admin_dashboard(date, date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_dashboard(date, date) IS
  'Ringkasan dashboard admin (total + rute). Minggu Senin–Sabtu. Order/Kiriman/Actual.';

NOTIFY pgrst, 'reload schema';
