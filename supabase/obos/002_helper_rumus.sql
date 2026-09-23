-- Helper rumus skema obos. Jalankan SETELAH 001_skema_tabel.sql.
-- public tidak diubah. Tidak migrasi. Tidak untuk app/API. Boleh diulang.

CREATE OR REPLACE FUNCTION obos.hari_jakarta(p timestamptz)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (p AT TIME ZONE 'Asia/Jakarta')::date;
$$;

CREATE OR REPLACE FUNCTION obos.grup_rute(p_rute text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(upper(btrim(COALESCE(p_rute, ''))), '[DH]$', '');
$$;

CREATE OR REPLACE FUNCTION obos.harga_jual_strata(
  p_dasar integer,
  p_qty integer,
  p_min1 integer,
  p_jual1 integer,
  p_min2 integer,
  p_jual2 integer,
  p_min3 integer,
  p_jual3 integer,
  p_min4 integer,
  p_jual4 integer,
  p_min5 integer,
  p_jual5 integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    (
      SELECT s.jual
      FROM (
        VALUES
          (p_min5, p_jual5),
          (p_min4, p_jual4),
          (p_min3, p_jual3),
          (p_min2, p_jual2),
          (p_min1, p_jual1)
      ) AS s(min, jual)
      WHERE COALESCE(p_qty, 0) >= s.min
        AND s.min > 0
        AND s.jual > 0
      ORDER BY s.min DESC
      LIMIT 1
    ),
    GREATEST(COALESCE(p_dasar, 0), 0)
  );
$$;

-- Nota batal = packed penuh. Terkirim = sisa tebus (packed − actual). Selain itu 0.
CREATE OR REPLACE FUNCTION obos.omset_batal(
  p_status text,
  p_packed numeric,
  p_actual numeric
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_status = 'batal' THEN round(coalesce(p_packed, 0))::bigint
    WHEN p_status = 'terkirim' THEN
      greatest(round(coalesce(p_packed, 0) - coalesce(p_actual, 0)), 0)::bigint
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION obos.qty_batal(
  p_status text,
  p_packed numeric,
  p_actual numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_status = 'batal' THEN coalesce(p_packed, 0)
    WHEN p_status = 'terkirim' THEN
      greatest(coalesce(p_packed, 0) - coalesce(p_actual, 0), 0)
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION obos.omset_pending(
  p_pending boolean,
  p_packed numeric
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN coalesce(p_pending, false) THEN round(coalesce(p_packed, 0))::bigint
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION obos.omset_actual(
  p_status text,
  p_actual numeric
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_status = 'batal' THEN 0
    ELSE round(coalesce(p_actual, 0))::bigint
  END;
$$;

-- Kartu admin: cap buku ini, atau (buku hidup) packed belum ber-id.
CREATE OR REPLACE FUNCTION obos.nota_ikut_admin(
  p_id_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_id_buku IS NOT NULL
    AND (
      p_id_setoran_buku = p_id_buku
      OR (
        p_id_setoran_buku IS NULL
        AND NOT coalesce(p_tutup, false)
        AND (
          p_status = 'dikirim'
          OR (
            p_status IN ('terkirim', 'batal')
            AND p_waktu_actual IS NOT NULL
            AND obos.hari_jakarta(p_waktu_actual) = p_tgl
          )
        )
      )
    );
$$;

-- Packing layar: hari order Jakarta, sama sales. Cap buku tidak dipakai untuk daftar.
CREATE OR REPLACE FUNCTION obos.nota_ikut_gudang(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_waktu_order timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_tgl IS NOT NULL
    AND p_waktu_order IS NOT NULL
    AND obos.hari_jakarta(p_waktu_order) = p_tgl;
$$;

CREATE OR REPLACE FUNCTION obos.nota_ikut_pengirim(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_order timestamptz,
  p_waktu_actual timestamptz,
  p_tanggal_lihat date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (
      p_id_buku IS NOT NULL
      AND p_id_setoran_buku = p_id_buku
    )
    OR (
      p_tgl IS NOT NULL
      AND p_waktu_order IS NOT NULL
      AND obos.hari_jakarta(p_waktu_order) = p_tgl
      AND p_id_setoran_buku IS NULL
      AND p_status = 'dikirim'
      AND (p_id_buku IS NULL OR coalesce(p_hidup, false))
    )
    OR (
      p_id_buku IS NULL
      AND p_id_setoran_buku IS NULL
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND obos.hari_jakarta(p_waktu_actual) = p_tanggal_lihat
    );
$$;

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

CREATE OR REPLACE FUNCTION obos.pending_halaman(p_pending boolean)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(p_pending, false);
$$;

CREATE OR REPLACE FUNCTION obos.pending_di_foto(
  p_id_buku bigint,
  p_id_transaksi text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM obos.setoran_buku_pending_foto f
    WHERE f.id_setoran_buku = p_id_buku
      AND f.id_transaksi = p_id_transaksi
  );
$$;

CREATE OR REPLACE VIEW obos.v_transaksi_item AS
SELECT
  z.*,
  z.qty_order * z.harga_jual_order AS subtotal_jual_order,
  CASE
    WHEN z.qty_packed IS NULL THEN NULL
    ELSE z.qty_packed * z.harga_jual_packed
  END AS subtotal_jual_packed,
  CASE
    WHEN z.qty_actual IS NULL THEN NULL
    ELSE z.qty_actual * z.harga_jual_actual
  END AS subtotal_jual_actual
FROM (
  SELECT
    i.id,
    i.id_transaksi,
    i.id_barang,
    i.id_grup,
    i.nama_barang,
    i.harga_beli,
    i.harga_jual,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.subtotal_beli_order,
    i.subtotal_beli_packed,
    i.subtotal_beli_actual,
    i.min_strat_1,
    i.jual_strat_1,
    i.min_strat_2,
    i.jual_strat_2,
    i.min_strat_3,
    i.jual_strat_3,
    i.min_strat_4,
    i.jual_strat_4,
    i.min_strat_5,
    i.jual_strat_5,
    obos.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(i.qty_order) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5
    ) AS harga_jual_order,
    CASE WHEN i.qty_packed IS NULL THEN NULL ELSE obos.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(COALESCE(i.qty_packed, 0)) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5
    ) END AS harga_jual_packed,
    CASE WHEN i.qty_actual IS NULL THEN NULL ELSE obos.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(COALESCE(i.qty_actual, 0)) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5
    ) END AS harga_jual_actual
  FROM obos.transaksi_items i
  WINDOW w AS (
    PARTITION BY i.id_transaksi,
      COALESCE(NULLIF(btrim(i.id_grup), ''), i.id_barang)
  )
) z;

CREATE OR REPLACE VIEW obos.v_omset_nota AS
SELECT
  t.id_transaksi,
  t.id_pelanggan,
  t.nama_pelanggan,
  t.rute,
  t.status,
  t.pending,
  t.waktu_order,
  t.waktu_packed,
  t.waktu_actual,
  t.id_setoran_buku,
  coalesce(sum(i.subtotal_jual_order), 0)::bigint AS jual_order,
  coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed,
  coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS jual_actual,
  obos.omset_batal(
    t.status,
    coalesce(sum(i.subtotal_jual_packed), 0),
    coalesce(sum(i.subtotal_jual_actual), 0)
  ) AS jual_batal,
  obos.omset_pending(
    t.pending,
    coalesce(sum(i.subtotal_jual_packed), 0)
  ) AS jual_pending,
  obos.omset_actual(
    t.status,
    coalesce(sum(i.subtotal_jual_actual), 0)
  ) AS jual_actual_kartu
FROM obos.transaksi t
LEFT JOIN obos.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
GROUP BY
  t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.rute,
  t.status, t.pending, t.waktu_order, t.waktu_packed, t.waktu_actual,
  t.id_setoran_buku;

GRANT SELECT ON obos.v_transaksi_item TO postgres, service_role;
GRANT SELECT ON obos.v_omset_nota TO postgres, service_role;
REVOKE ALL ON obos.v_transaksi_item FROM PUBLIC, anon, authenticated;
REVOKE ALL ON obos.v_omset_nota FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'obos'
      AND p.proname <> 'users_rapikan'
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
