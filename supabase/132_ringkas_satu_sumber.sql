-- Satu sumber ringkasan: Order/Kiriman = rumus app salesman (tanggal order).
-- Actual omset = terkirim per tanggal buku (margin). EC/visit sama admin gaji.
-- salesman_ringkas memakai fungsi ini. Jalankan SETELAH 131. Boleh diulang.

CREATE OR REPLACE FUNCTION public._admin_dashboard_capaian(
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
      t.status,
      (timezone('Asia/Jakarta', t.waktu_order))::date AS hari_order,
      (
        t.waktu_packed IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM public.transaksi_items x
          WHERE x.id_transaksi = t.id_transaksi
            AND x.qty_packed IS NOT NULL
        )
      ) AS punya_packed,
      (
        t.status = 'batal'
        AND t.waktu_packed IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM public.transaksi_items x
          WHERE x.id_transaksi = t.id_transaksi
            AND coalesce(x.qty_packed, 0) > 0
        )
      ) AS batal_gudang
    FROM public.transaksi t
    WHERE NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
      AND btrim(t.rute) = p_rute
      AND (timezone('Asia/Jakarta', t.waktu_order))::date >= p_dari
      AND (timezone('Asia/Jakarta', t.waktu_order))::date <= p_sampai
  ),
  nota_batal AS (
    SELECT
      t.id_pelanggan,
      (timezone('Asia/Jakarta', t.waktu_order))::date AS hari_order
    FROM public.transaksi t
    WHERE t.status = 'batal'
      AND btrim(t.rute) = p_rute
      AND (timezone('Asia/Jakarta', t.waktu_order))::date >= p_dari
      AND (timezone('Asia/Jakarta', t.waktu_order))::date <= p_sampai
  ),
  uang AS (
    SELECT
      COALESCE(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      COALESCE(sum(i.subtotal_beli_order), 0)::bigint AS modal_order,
      COALESCE(sum(i.subtotal_jual_packed) FILTER (
        WHERE n.punya_packed AND NOT n.batal_gudang
      ), 0)::bigint AS omset_kiriman,
      COALESCE(sum(i.subtotal_beli_packed) FILTER (
        WHERE n.punya_packed AND NOT n.batal_gudang
      ), 0)::bigint AS modal_kiriman,
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  uang_actual AS (
    SELECT
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM public.transaksi t
    JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
    JOIN public.setoran_buku b ON b.id = t.id_setoran_buku
    WHERE t.status = 'terkirim'
      AND t.id_setoran_buku IS NOT NULL
      AND btrim(t.rute) = p_rute
      AND b.tanggal >= p_dari
      AND b.tanggal <= p_sampai
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_order
    FROM nota n
    WHERE n.punya_packed AND NOT n.batal_gudang
  ),
  hitung AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
          )
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE btrim(COALESCE(k.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(k.id_pelanggan, k.hari_order, p_rute)
          )
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
          )
      )::integer AS ec_actual,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS xc_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE NOT public.toko_jadwal_pada(k.id_pelanggan, k.hari_order, p_rute)
      ) AS xc_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS xc_actual,
      (
        SELECT count(DISTINCT b.id_pelanggan)::integer
        FROM nota_batal b
        WHERE NOT public.toko_jadwal_pada(b.id_pelanggan, b.hari_order, p_rute)
      ) AS xc_batal,
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
      AND public.toko_jadwal_pada(k.id_pelanggan, k.tanggal, p_rute)
  )
  SELECT jsonb_build_object(
    'omset_order', u.omset_order,
    'laba_order', u.omset_order - u.modal_order,
    'omset_kiriman', u.omset_kiriman,
    'laba_kiriman', u.omset_kiriman - u.modal_kiriman,
    'omset_actual', a.omset_actual,
    'laba_actual', a.omset_actual - a.modal_actual,
    'ec_order', e.ec_order,
    'ec_kiriman', e.ec_kiriman,
    'ec_actual', e.ec_actual,
    'xc_order', e.xc_order,
    'xc_kiriman', e.xc_kiriman,
    'xc_actual', e.xc_actual,
    'xc_batal', e.xc_batal,
    'nota_order', e.nota_order,
    'nota_kiriman', e.nota_kiriman,
    'nota_actual', e.nota_actual,
    'visit', v.n,
    'target_visit', GREATEST(p_toko, 1),
    'target_ec', GREATEST(p_toko, 1)
  )
  FROM uang u, hitung e, visit v, uang_actual a;
$$;

CREATE OR REPLACE FUNCTION public._admin_dashboard_capaian_semua(
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
      t.status,
      (timezone('Asia/Jakarta', t.waktu_order))::date AS hari_order,
      btrim(t.rute) AS rute,
      (
        t.waktu_packed IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM public.transaksi_items x
          WHERE x.id_transaksi = t.id_transaksi
            AND x.qty_packed IS NOT NULL
        )
      ) AS punya_packed,
      (
        t.status = 'batal'
        AND t.waktu_packed IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM public.transaksi_items x
          WHERE x.id_transaksi = t.id_transaksi
            AND coalesce(x.qty_packed, 0) > 0
        )
      ) AS batal_gudang
    FROM public.transaksi t
    WHERE NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND (timezone('Asia/Jakarta', t.waktu_order))::date >= p_dari
      AND (timezone('Asia/Jakarta', t.waktu_order))::date <= p_sampai
  ),
  nota_batal AS (
    SELECT
      t.id_pelanggan,
      (timezone('Asia/Jakarta', t.waktu_order))::date AS hari_order,
      btrim(t.rute) AS rute
    FROM public.transaksi t
    WHERE t.status = 'batal'
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND (timezone('Asia/Jakarta', t.waktu_order))::date >= p_dari
      AND (timezone('Asia/Jakarta', t.waktu_order))::date <= p_sampai
  ),
  uang AS (
    SELECT
      COALESCE(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      COALESCE(sum(i.subtotal_beli_order), 0)::bigint AS modal_order,
      COALESCE(sum(i.subtotal_jual_packed) FILTER (
        WHERE n.punya_packed AND NOT n.batal_gudang
      ), 0)::bigint AS omset_kiriman,
      COALESCE(sum(i.subtotal_beli_packed) FILTER (
        WHERE n.punya_packed AND NOT n.batal_gudang
      ), 0)::bigint AS modal_kiriman,
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  uang_actual AS (
    SELECT
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM public.transaksi t
    JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
    JOIN public.setoran_buku b ON b.id = t.id_setoran_buku
    WHERE t.status = 'terkirim'
      AND t.id_setoran_buku IS NOT NULL
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND b.tanggal >= p_dari
      AND b.tanggal <= p_sampai
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_order, n.rute
    FROM nota n
    WHERE n.punya_packed AND NOT n.batal_gudang
  ),
  hitung AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
          )
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE btrim(COALESCE(k.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(k.id_pelanggan, k.hari_order, k.rute)
          )
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
          )
      )::integer AS ec_actual,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS xc_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE NOT public.toko_jadwal_pada(k.id_pelanggan, k.hari_order, k.rute)
      ) AS xc_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS xc_actual,
      (
        SELECT count(DISTINCT b.id_pelanggan)::integer
        FROM nota_batal b
        WHERE NOT public.toko_jadwal_pada(b.id_pelanggan, b.hari_order, b.rute)
      ) AS xc_batal,
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
      AND public.toko_jadwal_pada(k.id_pelanggan, k.tanggal, btrim(k.rute))
  )
  SELECT jsonb_build_object(
    'omset_order', u.omset_order,
    'laba_order', u.omset_order - u.modal_order,
    'omset_kiriman', u.omset_kiriman,
    'laba_kiriman', u.omset_kiriman - u.modal_kiriman,
    'omset_actual', a.omset_actual,
    'laba_actual', a.omset_actual - a.modal_actual,
    'ec_order', e.ec_order,
    'ec_kiriman', e.ec_kiriman,
    'ec_actual', e.ec_actual,
    'xc_order', e.xc_order,
    'xc_kiriman', e.xc_kiriman,
    'xc_actual', e.xc_actual,
    'xc_batal', e.xc_batal,
    'nota_order', e.nota_order,
    'nota_kiriman', e.nota_kiriman,
    'nota_actual', e.nota_actual,
    'visit', v.n,
    'target_visit', GREATEST(p_toko, 1),
    'target_ec', GREATEST(p_toko, 1)
  )
  FROM uang u, hitung e, visit v, uang_actual a;
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

DROP FUNCTION IF EXISTS public.salesman_ringkas(date, date);
CREATE FUNCTION public.salesman_ringkas(p_dari date, p_sampai date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_nama text;
  v_email text;
  v_toko integer := 1;
  v_omset bigint := 0;
  v_persen numeric := 0;
  v_cap jsonb;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun sales yang boleh melihat ringkasan ini.';
  END IF;
  IF p_dari IS NULL OR p_sampai IS NULL OR p_sampai < p_dari THEN
    RAISE EXCEPTION 'Rentang tanggal ringkasan tidak sah.';
  END IF;

  SELECT
    btrim(u.rute),
    coalesce(nullif(btrim(u.nama), ''), btrim(u.email)),
    lower(btrim(u.email))
  INTO v_rute, v_nama, v_email
  FROM public.users u
  WHERE u.peran = 'sales'
    AND lower(btrim(u.email)) = public.email_jwt()
  LIMIT 1;

  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Akun sales belum punya rute.';
  END IF;

  SELECT COALESCE(t.target_omset, 0), COALESCE(t.target_persen_laba, 0)
  INTO v_omset, v_persen
  FROM public.target_sales t
  WHERE lower(trim(t.email)) = v_email;

  IF p_dari IS NOT DISTINCT FROM p_sampai THEN
    SELECT count(*)::integer
    INTO v_toko
    FROM public.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(p.id_pelanggan) <> ''
      AND p.id_pelanggan NOT LIKE 'TMP%'
      AND btrim(COALESCE(p.visit, '')) = public.hari_visit_nama(p_dari);
  ELSE
    SELECT count(*)::integer
    INTO v_toko
    FROM public.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(p.id_pelanggan) <> ''
      AND p.id_pelanggan NOT LIKE 'TMP%';
  END IF;
  v_toko := GREATEST(COALESCE(v_toko, 0), 1);

  v_cap := public._admin_dashboard_capaian(v_rute, p_dari, p_sampai, v_toko);

  RETURN coalesce(v_cap, '{}'::jsonb) || jsonb_build_object(
    'rute', v_rute,
    'nama', v_nama,
    'target_omset', v_omset,
    'target_persen', COALESCE(v_persen, 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.salesman_ringkas(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.salesman_ringkas(date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.salesman_ringkas(date, date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) IS
  'Satu sumber ringkasan: Order/Kiriman rumus salesman; Actual omset per buku.';

COMMENT ON FUNCTION public.salesman_ringkas(date, date) IS
  'Ringkasan penjualan rute login. Sama angka dengan dashboard admin untuk rute itu.';

NOTIFY pgrst, 'reload schema';
