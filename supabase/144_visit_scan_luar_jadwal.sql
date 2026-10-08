-- Visit = toko unik yang discan, termasuk luar jadwal (hari scan ≠ pelanggan.visit).
-- Gaji Visit ikut naik. EC/XC tidak diubah.
-- Jalankan SETELAH 138. Boleh diulang.

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
      t.hari_label AS hari_buku,
      (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date AS hari_ketik,
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
    FROM public.v_transaksi_hari_label t
    WHERE btrim(t.rute) = p_rute
      AND t.hari_label >= p_dari
      AND t.hari_label <= p_sampai
  ),
  nota_batal AS (
    SELECT
      t.id_pelanggan,
      t.hari_label AS hari_buku
    FROM public.v_transaksi_hari_label t
    WHERE t.status = 'batal'
      AND btrim(t.rute) = p_rute
      AND t.hari_label >= p_dari
      AND t.hari_label <= p_sampai
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
      COALESCE(sum(i.subtotal_jual_actual) FILTER (
        WHERE n.status = 'terkirim'
      ), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual) FILTER (
        WHERE n.status = 'terkirim'
      ), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_buku, n.hari_ketik
    FROM nota n
    WHERE n.punya_packed AND NOT n.batal_gudang
  ),
  hitung AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, p_rute)
          )
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE btrim(COALESCE(k.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(k.id_pelanggan, k.hari_buku, p_rute)
          )
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, p_rute)
          )
      )::integer AS ec_actual,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, p_rute)
          AND coalesce(n.hari_ketik, n.hari_buku) >= n.hari_buku
      )::integer AS xc_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE NOT public.toko_jadwal_pada(k.id_pelanggan, k.hari_buku, p_rute)
          AND coalesce(k.hari_ketik, k.hari_buku) >= k.hari_buku
      ) AS xc_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, p_rute)
          AND coalesce(n.hari_ketik, n.hari_buku) >= n.hari_buku
      )::integer AS xc_actual,
      (
        SELECT count(DISTINCT b.id_pelanggan)::integer
        FROM nota_batal b
        WHERE NOT public.toko_jadwal_pada(b.id_pelanggan, b.hari_buku, p_rute)
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
      t.hari_label AS hari_buku,
      btrim(t.rute) AS rute,
      (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date AS hari_ketik,
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
    FROM public.v_transaksi_hari_label t
    WHERE btrim(t.rute) IN (SELECT rute FROM sales)
      AND t.hari_label >= p_dari
      AND t.hari_label <= p_sampai
  ),
  nota_batal AS (
    SELECT
      t.id_pelanggan,
      t.hari_label AS hari_buku,
      btrim(t.rute) AS rute
    FROM public.v_transaksi_hari_label t
    WHERE t.status = 'batal'
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND t.hari_label >= p_dari
      AND t.hari_label <= p_sampai
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
      COALESCE(sum(i.subtotal_jual_actual) FILTER (
        WHERE n.status = 'terkirim'
      ), 0)::bigint AS omset_actual,
      COALESCE(sum(i.subtotal_beli_actual) FILTER (
        WHERE n.status = 'terkirim'
      ), 0)::bigint AS modal_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_buku, n.rute, n.hari_ketik
    FROM nota n
    WHERE n.punya_packed AND NOT n.batal_gudang
  ),
  hitung AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, n.rute)
          )
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE btrim(COALESCE(k.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(k.id_pelanggan, k.hari_buku, k.rute)
          )
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND btrim(COALESCE(n.id_pelanggan, '')) <> ''
          AND (
            p_dari IS DISTINCT FROM p_sampai
            OR public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, n.rute)
          )
      )::integer AS ec_actual,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, n.rute)
          AND coalesce(n.hari_ketik, n.hari_buku) >= n.hari_buku
      )::integer AS xc_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE NOT public.toko_jadwal_pada(k.id_pelanggan, k.hari_buku, k.rute)
          AND coalesce(k.hari_ketik, k.hari_buku) >= k.hari_buku
      ) AS xc_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND NOT public.toko_jadwal_pada(n.id_pelanggan, n.hari_buku, n.rute)
          AND coalesce(n.hari_ketik, n.hari_buku) >= n.hari_buku
      )::integer AS xc_actual,
      (
        SELECT count(DISTINCT b.id_pelanggan)::integer
        FROM nota_batal b
        WHERE NOT public.toko_jadwal_pada(b.id_pelanggan, b.hari_buku, b.rute)
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

REVOKE ALL ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian_semua(date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_capaian_semua(date, date, integer)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) IS
  'Visit = scan unik termasuk luar jadwal. EC/XC tetap.';

NOTIFY pgrst, 'reload schema';
