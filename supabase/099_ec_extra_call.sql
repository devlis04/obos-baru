-- EC = toko jadwal hari itu yang order (bukan batal).
-- Extra call = toko luar jadwal yang order. Visit = scan GPS toko jadwal hari itu.
-- Omset tetap semua nota bukan batal.
-- Batal sales (belum packing) tidak di daftar packing; uang kartu di 100.
-- Jalankan SETELAH 098, lalu ulang 065. SQL Editor → Run. Boleh di-Run ulang.

CREATE OR REPLACE FUNCTION public.hari_visit_nama(p_hari date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE EXTRACT(ISODOW FROM p_hari)::integer
    WHEN 1 THEN 'Senin'
    WHEN 2 THEN 'Selasa'
    WHEN 3 THEN 'Rabu'
    WHEN 4 THEN 'Kamis'
    WHEN 5 THEN 'Jumat'
    WHEN 6 THEN 'Sabtu'
    ELSE 'Minggu'
  END;
$$;

CREATE OR REPLACE FUNCTION public.toko_jadwal_pada(
  p_id_pelanggan text,
  p_hari date,
  p_rute text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pelanggan p
    WHERE p.id_pelanggan = btrim(COALESCE(p_id_pelanggan, ''))
      AND COALESCE(p.aktif, true)
      AND (p_rute IS NULL OR btrim(p.rute) = btrim(p_rute))
      AND btrim(COALESCE(p.visit, '')) = public.hari_visit_nama(p_hari)
  );
$$;

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
        WHERE public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE public.toko_jadwal_pada(k.id_pelanggan, k.hari_order, p_rute)
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
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
        WHERE public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE public.toko_jadwal_pada(k.id_pelanggan, k.hari_order, k.rute)
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND public.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
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

CREATE OR REPLACE FUNCTION public.gudang_kartu_rute(p_tanggal date)
RETURNS TABLE (
  rute text,
  nama_sales text,
  jumlah_nota integer,
  sudah_siap integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM public.transaksi t
    WHERE public.gudang_nota_ikut_buku(
      v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
    )
      AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  ),
  hitung AS (
    SELECT
      n.rute,
      count(DISTINCT n.id_transaksi)::integer AS jumlah_nota,
      count(DISTINCT n.id_transaksi) FILTER (
        WHERE n.status IN ('dikirim', 'terkirim') OR n.waktu_packed IS NOT NULL
      )::integer AS sudah_siap,
      coalesce(sum(i.subtotal_jual_order) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_order,
      coalesce(sum(i.subtotal_jual_packed) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_packed,
      coalesce(sum(i.subtotal_jual_actual) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_actual,
      coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS laba_order,
      coalesce(sum(
        CASE
          WHEN i.qty_packed IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
        END
      ) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS laba_packed,
      coalesce(sum(
        CASE
          WHEN i.qty_actual IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
        END
      ) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS laba_actual
    FROM nota n
    LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.rute
  )
  SELECT
    h.rute,
    coalesce(
      (
        SELECT u.nama
        FROM public.users u
        WHERE u.peran = 'sales'
          AND u.rute = h.rute
        LIMIT 1
      ),
      h.rute
    ),
    h.jumlah_nota,
    h.sudah_siap,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.laba_order,
    h.laba_packed,
    h.laba_actual
  FROM hitung h
  ORDER BY h.rute;
END;
$$;

DROP FUNCTION IF EXISTS public.gudang_nota_rute(date, text);

CREATE FUNCTION public.gudang_nota_rute(p_tanggal date, p_rute text)
RETURNS TABLE (
  id_transaksi text,
  id_pelanggan text,
  nama_pelanggan text,
  status text,
  pending boolean,
  waktu_order timestamptz,
  waktu_packed timestamptz,
  waktu_actual timestamptz,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint,
  extra boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean;
  v_hari text;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;

  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);
  v_hari := public.hari_visit_nama(v_tgl);

  RETURN QUERY
  SELECT
    t.id_transaksi,
    t.id_pelanggan,
    t.nama_pelanggan,
    t.status,
    t.pending,
    t.waktu_order,
    t.waktu_packed,
    t.waktu_actual,
    coalesce(sum(i.subtotal_jual_order), 0)::bigint,
    coalesce(sum(i.subtotal_jual_packed), 0)::bigint,
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint,
    coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_packed IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
      END
    ), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_actual IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
      END
    ), 0)::bigint,
    (btrim(COALESCE(p.visit, '')) IS DISTINCT FROM v_hari) AS extra
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  LEFT JOIN public.pelanggan p ON p.id_pelanggan = t.id_pelanggan
  WHERE t.rute = p_rute
    AND public.gudang_nota_ikut_buku(
      v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
    )
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual, p.visit
  ORDER BY t.waktu_order DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.hari_visit_nama(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hari_visit_nama(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.toko_jadwal_pada(text, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.toko_jadwal_pada(text, date, text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_capaian(text, date, date, integer)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public._admin_dashboard_capaian_semua(date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._admin_dashboard_capaian_semua(date, date, integer)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_kartu_rute(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_kartu_rute(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_rute(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_rute(date, text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
