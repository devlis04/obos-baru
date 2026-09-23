-- Selaras public 099/065/091/100: EC/XC/visit, extra gudang, batal gudang tidak ke pengirim.
-- Helper juga ada di 002. Jangan 001. Jalankan SETELAH 015. Lalu ulang 003.
-- Boleh diulang. 012 tetap setelah tutup buku. App masih public.

CREATE OR REPLACE FUNCTION obos.hari_visit_nama(p_hari date)
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

CREATE OR REPLACE FUNCTION obos.toko_jadwal_pada(
  p_id_pelanggan text,
  p_hari date,
  p_rute text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM obos.pelanggan p
    WHERE p.id_pelanggan = btrim(COALESCE(p_id_pelanggan, ''))
      AND COALESCE(p.aktif, true)
      AND (p_rute IS NULL OR btrim(p.rute) = btrim(p_rute))
      AND btrim(COALESCE(p.visit, '')) = obos.hari_visit_nama(p_hari)
  );
$$;

CREATE OR REPLACE FUNCTION obos.pengirim_bukan_batal_gudang(
  p_status text,
  p_id_transaksi text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT NOT (
    coalesce(p_status, '') = 'batal'
    AND NOT EXISTS (
      SELECT 1
      FROM obos.transaksi_items i
      WHERE i.id_transaksi = btrim(coalesce(p_id_transaksi, ''))
        AND coalesce(i.qty_packed, 0) > 0
    )
  );
$$;

CREATE OR REPLACE FUNCTION obos.nota_gudang_rute(p_tanggal date, p_rute text)
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
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean := false;
  v_hari text;
BEGIN
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;
  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM obos.buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);
  v_hari := obos.hari_visit_nama(v_tgl);

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
  FROM obos.transaksi t
  LEFT JOIN obos.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  LEFT JOIN obos.pelanggan p ON p.id_pelanggan = t.id_pelanggan
  WHERE t.rute = p_rute
    AND obos.nota_ikut_gudang(
      v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
    )
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual, p.visit
  ORDER BY t.waktu_order DESC;
END;
$$;

CREATE OR REPLACE FUNCTION obos.dashboard_capaian(
  p_rute text,
  p_dari date,
  p_sampai date,
  p_toko integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  WITH nota AS (
    SELECT
      t.id_transaksi,
      t.id_pelanggan,
      t.status,
      obos.hari_jakarta(t.waktu_order) AS hari_order
    FROM obos.transaksi t
    WHERE t.status <> 'batal'
      AND btrim(t.rute) = p_rute
      AND obos.hari_jakarta(t.waktu_order) >= p_dari
      AND obos.hari_jakarta(t.waktu_order) <= p_sampai
  ),
  nota_batal AS (
    SELECT
      t.id_pelanggan,
      obos.hari_jakarta(t.waktu_order) AS hari_order
    FROM obos.transaksi t
    WHERE t.status = 'batal'
      AND btrim(t.rute) = p_rute
      AND obos.hari_jakarta(t.waktu_order) >= p_dari
      AND obos.hari_jakarta(t.waktu_order) <= p_sampai
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
    JOIN obos.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_order
    FROM nota n
    WHERE n.status IN ('dikirim', 'terkirim')
       OR EXISTS (
         SELECT 1
         FROM obos.transaksi_items i
         WHERE i.id_transaksi = n.id_transaksi
           AND i.qty_packed IS NOT NULL
       )
  ),
  hitung AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE obos.toko_jadwal_pada(k.id_pelanggan, k.hari_order, p_rute)
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS ec_actual,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE NOT obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS xc_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE NOT obos.toko_jadwal_pada(k.id_pelanggan, k.hari_order, p_rute)
      ) AS xc_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND NOT obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, p_rute)
      )::integer AS xc_actual,
      (
        SELECT count(DISTINCT b.id_pelanggan)::integer
        FROM nota_batal b
        WHERE NOT obos.toko_jadwal_pada(b.id_pelanggan, b.hari_order, p_rute)
      ) AS xc_batal,
      count(*)::integer AS nota_order,
      (SELECT count(*)::integer FROM kirim) AS nota_kiriman,
      count(*) FILTER (WHERE n.status = 'terkirim')::integer AS nota_actual
    FROM nota n
  ),
  visit AS (
    SELECT count(DISTINCT k.id_pelanggan)::integer AS n
    FROM obos.kunjungan_sales k
    WHERE btrim(k.rute) = p_rute
      AND k.tanggal >= p_dari
      AND k.tanggal <= p_sampai
      AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
      AND obos.toko_jadwal_pada(k.id_pelanggan, k.tanggal, p_rute)
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

CREATE OR REPLACE FUNCTION obos.dashboard_capaian_semua(
  p_dari date,
  p_sampai date,
  p_toko integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  WITH sales AS (
    SELECT btrim(u.rute) AS rute
    FROM obos.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
  ),
  nota AS (
    SELECT
      t.id_transaksi,
      t.id_pelanggan,
      t.status,
      obos.hari_jakarta(t.waktu_order) AS hari_order,
      btrim(t.rute) AS rute
    FROM obos.transaksi t
    WHERE t.status <> 'batal'
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND obos.hari_jakarta(t.waktu_order) >= p_dari
      AND obos.hari_jakarta(t.waktu_order) <= p_sampai
  ),
  nota_batal AS (
    SELECT
      t.id_pelanggan,
      obos.hari_jakarta(t.waktu_order) AS hari_order,
      btrim(t.rute) AS rute
    FROM obos.transaksi t
    WHERE t.status = 'batal'
      AND btrim(t.rute) IN (SELECT rute FROM sales)
      AND obos.hari_jakarta(t.waktu_order) >= p_dari
      AND obos.hari_jakarta(t.waktu_order) <= p_sampai
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
    JOIN obos.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
  ),
  kirim AS (
    SELECT DISTINCT n.id_transaksi, n.id_pelanggan, n.hari_order, n.rute
    FROM nota n
    WHERE n.status IN ('dikirim', 'terkirim')
       OR EXISTS (
         SELECT 1
         FROM obos.transaksi_items i
         WHERE i.id_transaksi = n.id_transaksi
           AND i.qty_packed IS NOT NULL
       )
  ),
  hitung AS (
    SELECT
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS ec_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE obos.toko_jadwal_pada(k.id_pelanggan, k.hari_order, k.rute)
      ) AS ec_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS ec_actual,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE NOT obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS xc_order,
      (
        SELECT count(DISTINCT k.id_pelanggan)::integer
        FROM kirim k
        WHERE NOT obos.toko_jadwal_pada(k.id_pelanggan, k.hari_order, k.rute)
      ) AS xc_kiriman,
      count(DISTINCT n.id_pelanggan) FILTER (
        WHERE n.status = 'terkirim'
          AND NOT obos.toko_jadwal_pada(n.id_pelanggan, n.hari_order, n.rute)
      )::integer AS xc_actual,
      (
        SELECT count(DISTINCT b.id_pelanggan)::integer
        FROM nota_batal b
        WHERE NOT obos.toko_jadwal_pada(b.id_pelanggan, b.hari_order, b.rute)
      ) AS xc_batal,
      count(*)::integer AS nota_order,
      (SELECT count(*)::integer FROM kirim) AS nota_kiriman,
      count(*) FILTER (WHERE n.status = 'terkirim')::integer AS nota_actual
    FROM nota n
  ),
  visit AS (
    SELECT count(DISTINCT k.id_pelanggan)::integer AS n
    FROM obos.kunjungan_sales k
    WHERE k.tanggal >= p_dari
      AND k.tanggal <= p_sampai
      AND btrim(k.rute) IN (SELECT rute FROM sales)
      AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
      AND obos.toko_jadwal_pada(k.id_pelanggan, k.tanggal, btrim(k.rute))
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

DROP FUNCTION IF EXISTS obos.dashboard_toko(date, text);

CREATE FUNCTION obos.dashboard_toko(p_hari date, p_rute text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_hari date;
  v_rute text;
  v_nama_hari text;
  v_toko jsonb;
BEGIN
  v_hari := COALESCE(p_hari, obos.hari_jakarta(clock_timestamp()));
  v_rute := nullif(btrim(coalesce(p_rute, '')), '');
  IF v_rute IS NULL THEN
    RAISE EXCEPTION 'Rute sales wajib.';
  END IF;
  v_nama_hari := obos.hari_visit_nama(v_hari);

  WITH kunci AS (
    SELECT btrim(p.id_pelanggan) AS id_pelanggan
    FROM obos.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(p.id_pelanggan) <> ''
      AND p.id_pelanggan NOT LIKE 'TMP%'
      AND btrim(COALESCE(p.visit, '')) = v_nama_hari
    UNION
    SELECT btrim(k.id_pelanggan)
    FROM obos.kunjungan_sales k
    WHERE btrim(k.rute) = v_rute
      AND k.tanggal = v_hari
      AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
    UNION
    SELECT btrim(t.id_pelanggan)
    FROM obos.transaksi t
    WHERE btrim(t.rute) = v_rute
      AND btrim(COALESCE(t.id_pelanggan, '')) <> ''
      AND obos.hari_jakarta(t.waktu_order) = v_hari
  ),
  nota AS (
    SELECT
      t.id_transaksi,
      btrim(t.id_pelanggan) AS id_pelanggan,
      t.nama_pelanggan,
      t.status,
      t.pending
    FROM obos.transaksi t
    WHERE btrim(t.rute) = v_rute
      AND btrim(COALESCE(t.id_pelanggan, '')) <> ''
      AND obos.hari_jakarta(t.waktu_order) = v_hari
  ),
  omset AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.nama_pelanggan,
      n.status,
      n.pending,
      coalesce(sum(i.subtotal_jual_order), 0)::bigint AS jual_order,
      coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS jual_actual,
      coalesce(sum(i.subtotal_beli_order), 0)::bigint AS beli_order,
      coalesce(sum(i.subtotal_beli_packed), 0)::bigint AS beli_packed,
      coalesce(sum(i.subtotal_beli_actual), 0)::bigint AS beli_actual
    FROM nota n
    JOIN obos.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY
      n.id_transaksi, n.id_pelanggan, n.nama_pelanggan, n.status, n.pending
  ),
  visit AS (
    SELECT DISTINCT ON (btrim(k.id_pelanggan))
      btrim(k.id_pelanggan) AS id_pelanggan,
      k.waktu_masuk,
      k.waktu_keluar
    FROM obos.kunjungan_sales k
    WHERE btrim(k.rute) = v_rute
      AND k.tanggal = v_hari
    ORDER BY btrim(k.id_pelanggan), k.waktu_masuk NULLS LAST
  ),
  jadwal AS (
    SELECT btrim(p.id_pelanggan) AS id_pelanggan
    FROM obos.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(COALESCE(p.visit, '')) = v_nama_hari
      AND p.id_pelanggan NOT LIKE 'TMP%'
  ),
  baris AS (
    SELECT
      k.id_pelanggan,
      coalesce(
        nullif(btrim(p.nama_pelanggan), ''),
        nullif(max(o.nama_pelanggan), ''),
        k.id_pelanggan
      ) AS nama,
      coalesce(sum(o.jual_order), 0)::bigint AS jual_order,
      count(DISTINCT o.id_transaksi)::integer AS n_nota,
      coalesce(sum(o.jual_packed), 0)::bigint AS jual_packed,
      (j.id_pelanggan IS NOT NULL) AS jadwal,
      (j.id_pelanggan IS NULL AND count(DISTINCT o.id_transaksi) > 0) AS extra,
      v.waktu_masuk,
      v.waktu_keluar
    FROM kunci k
    LEFT JOIN obos.pelanggan p ON p.id_pelanggan = k.id_pelanggan
    LEFT JOIN omset o ON o.id_pelanggan = k.id_pelanggan
    LEFT JOIN visit v ON v.id_pelanggan = k.id_pelanggan
    LEFT JOIN jadwal j ON j.id_pelanggan = k.id_pelanggan
    GROUP BY
      k.id_pelanggan, p.nama_pelanggan, j.id_pelanggan,
      v.waktu_masuk, v.waktu_keluar
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_pelanggan', b.id_pelanggan,
        'nama', b.nama,
        'jadwal', b.jadwal,
        'extra', b.extra,
        'nota', b.n_nota,
        'order', b.jual_order,
        'packed', b.jual_packed,
        'visit_masuk', b.waktu_masuk,
        'visit_keluar', b.waktu_keluar
      )
      ORDER BY
        CASE WHEN b.jadwal THEN 0 WHEN b.extra THEN 1 ELSE 2 END,
        b.nama,
        b.id_pelanggan
    ),
    '[]'::jsonb
  )
  INTO v_toko
  FROM baris b;

  RETURN jsonb_build_object(
    'hari', v_hari,
    'rute', v_rute,
    'toko', coalesce(v_toko, '[]'::jsonb)
  );
END;
$$;

DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'obos'
      AND p.proname IN (
        'hari_visit_nama', 'toko_jadwal_pada', 'pengirim_bukan_batal_gudang',
        'nota_gudang_rute', 'dashboard_capaian', 'dashboard_capaian_semua',
        'dashboard_toko'
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION obos.%I(%s) FROM PUBLIC, anon, authenticated',
      f.proname, f.args
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION obos.%I(%s) TO postgres, service_role',
      f.proname, f.args
    );
  END LOOP;
END;
$$;
