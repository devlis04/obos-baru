-- EC minggu = toko unik yang transaksi di rentang (tanpa jadwal visit).
-- EC hari = toko unik yang transaksi di hari itu sesuai jadwal visit.
-- XC tetap toko luar jadwal. Visit tetap scan GPS toko jadwal.
-- Rentang satu hari (p_dari = p_sampai) = sisi harian. Selain itu = minggu.
-- Jalankan SETELAH 099. Boleh diulang.

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
      (timezone('Asia/Jakarta', t.waktu_order))::date AS hari_order
    FROM public.transaksi t
    WHERE t.status <> 'batal'
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
      COALESCE(sum(i.subtotal_jual_packed), 0)::bigint AS omset_kiriman,
      COALESCE(sum(i.subtotal_beli_packed), 0)::bigint AS modal_kiriman,
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_order
    FROM nota n
    WHERE n.status IN ('dikirim', 'terkirim')
       OR EXISTS (
         SELECT 1
         FROM public.transaksi_items i
         WHERE i.id_transaksi = n.id_transaksi
           AND i.qty_packed IS NOT NULL
       )
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
    'omset_actual', u.omset_actual,
    'laba_actual', u.omset_actual - u.modal_actual,
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
  FROM uang u, hitung e, visit v;
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
      btrim(t.rute) AS rute
    FROM public.transaksi t
    WHERE t.status <> 'batal'
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
      COALESCE(sum(i.subtotal_jual_packed), 0)::bigint AS omset_kiriman,
      COALESCE(sum(i.subtotal_beli_packed), 0)::bigint AS modal_kiriman,
      COALESCE(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_order, n.rute
    FROM nota n
    WHERE n.status IN ('dikirim', 'terkirim')
       OR EXISTS (
         SELECT 1
         FROM public.transaksi_items i
         WHERE i.id_transaksi = n.id_transaksi
           AND i.qty_packed IS NOT NULL
       )
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
    'omset_actual', u.omset_actual,
    'laba_actual', u.omset_actual - u.modal_actual,
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
  FROM uang u, hitung e, visit v;
$$;

COMMENT ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) IS
  'EC hari = toko jadwal. EC minggu = toko transaksi tanpa jadwal. XC luar jadwal.';

NOTIFY pgrst, 'reload schema';
