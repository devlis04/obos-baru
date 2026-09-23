-- RPC baca kartu. Jalankan SETELAH 002_helper_rumus.sql.
-- Uji di SQL Editor (postgres). Tidak cek sesi HP. public/app tidak diubah.

CREATE OR REPLACE FUNCTION obos.buku_terbuka()
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT b.id
  FROM obos.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION obos.buku_untuk_hari(p_tanggal date DEFAULT NULL)
RETURNS TABLE (
  id bigint,
  tanggal date,
  ditutup boolean,
  hidup boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_buka bigint;
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
BEGIN
  v_buka := obos.buku_terbuka();

  IF p_tanggal IS NULL THEN
    IF v_buka IS NULL THEN
      RETURN;
    END IF;
    SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
    FROM obos.setoran_buku b
    WHERE b.id = v_buka;
    id := v_id;
    tanggal := v_tgl;
    ditutup := COALESCE(v_tutup, false);
    hidup := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_buka IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
    FROM obos.setoran_buku b
    WHERE b.id = v_buka;
    IF v_tgl = p_tanggal THEN
      id := v_id;
      tanggal := v_tgl;
      ditutup := COALESCE(v_tutup, false);
      hidup := true;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.tanggal = p_tanggal
  ORDER BY b.id DESC
  LIMIT 1;
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  id := v_id;
  tanggal := v_tgl;
  ditutup := COALESCE(v_tutup, false);
  hidup := (v_buka IS NOT NULL AND v_id = v_buka);
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION obos.pending_kartu(
  p_tutup boolean,
  p_id_buku bigint,
  p_id_transaksi text,
  p_pending boolean
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT CASE
    WHEN coalesce(p_tutup, false) THEN
      obos.pending_di_foto(p_id_buku, p_id_transaksi)
    ELSE
      obos.pending_halaman(p_pending)
  END;
$$;

CREATE OR REPLACE FUNCTION obos.kartu_setoran(p_id_buku bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_baris jsonb;
BEGIN
  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = p_id_buku;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'rute', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(q.baris ORDER BY q.rute_pengirim), '[]'::jsonb)
  INTO v_baris
  FROM (
    SELECT
      p.rute_pengirim,
      jsonb_build_object(
        'rute_pengirim', p.rute_pengirim,
        'kiriman', coalesce(o.kiriman, 0),
        'batal', coalesce(o.batal, 0),
        'pending', coalesce(o.pending, 0),
        'actual', coalesce(o.actual, 0),
        'wajib_kunci', coalesce(o.wajib_kunci, 0),
        'transfer', coalesce(s.jumlah_transfer, 0),
        'tunai', coalesce(s.jumlah_tunai, 0),
        'bop', coalesce(s.jumlah_bop, 0),
        'kasbon', coalesce(s.kasbon_supir, 0) + coalesce(s.kasbon_kenek, 0),
        'kasbon_supir', coalesce(s.kasbon_supir, 0),
        'kasbon_kenek', coalesce(s.kasbon_kenek, 0),
        'nama_supir', coalesce(nm.nama_supir, ''),
        'nama_kenek', coalesce(nm.nama_kenek, ''),
        'retur', coalesce(r.nilai, 0),
        'sudah_setor', s.id IS NOT NULL
      ) AS baris
    FROM (SELECT DISTINCT rute_pengirim FROM obos.rute_peta) p
    LEFT JOIN (
      SELECT
        rp.rute_pengirim,
        coalesce(sum(o.jual_packed), 0)::bigint AS kiriman,
        coalesce(sum(
          CASE
            WHEN obos.pending_kartu(v_tutup, v_id, o.id_transaksi, o.pending)
              THEN 0
            ELSE o.jual_batal
          END
        ), 0)::bigint AS batal,
        coalesce(sum(
          CASE
            WHEN obos.pending_kartu(v_tutup, v_id, o.id_transaksi, o.pending)
              THEN o.jual_packed
            ELSE 0
          END
        ), 0)::bigint AS pending,
        coalesce(sum(
          CASE
            WHEN obos.pending_kartu(v_tutup, v_id, o.id_transaksi, o.pending)
              THEN 0
            ELSE o.jual_actual_kartu
          END
        ), 0)::bigint AS actual,
        count(*) FILTER (
          WHERE o.status = 'dikirim' AND NOT o.pending
        )::integer AS wajib_kunci
      FROM obos.v_omset_nota o
      JOIN obos.rute_peta rp ON rp.rute_sales = o.rute
      WHERE o.waktu_packed IS NOT NULL
        AND obos.nota_ikut_admin(
          v_id, v_tgl, v_tutup, o.id_setoran_buku, o.status, o.waktu_actual
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN obos.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        obos.grup_rute(u.rute) AS rute_pengirim,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'D' THEN u.nama END) AS nama_supir,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'H' THEN u.nama END) AS nama_kenek
      FROM obos.users u
      WHERE u.peran = 'pengirim'
      GROUP BY obos.grup_rute(u.rute)
    ) nm ON nm.rute_pengirim = p.rute_pengirim
    LEFT JOIN (
      SELECT
        i.rute_pengirim,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM obos.retur_toko i
      WHERE i.id_setoran_buku = v_id
      GROUP BY i.rute_pengirim
    ) r ON r.rute_pengirim = p.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', v_tutup,
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.kartu_gudang(p_tanggal date)
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
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean := false;
BEGIN
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;
  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM obos.buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM obos.transaksi t
    WHERE obos.nota_ikut_gudang(
        v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
      )
      AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  )
  SELECT
    h.rute,
    coalesce(
      (
        SELECT u.nama
        FROM obos.users u
        WHERE u.peran = 'sales' AND u.rute = h.rute
        LIMIT 1
      ),
      ''
    ) AS nama_sales,
    h.jumlah_nota,
    h.sudah_siap,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.laba_order,
    h.laba_packed,
    h.laba_actual
  FROM (
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
    LEFT JOIN obos.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.rute
  ) h
  ORDER BY h.rute;
END;
$$;

CREATE OR REPLACE FUNCTION obos.kartu_pengirim(
  p_tanggal date,
  p_rute_pengirim text DEFAULT NULL
)
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute_sales text,
  latitude double precision,
  longitude double precision,
  jumlah_nota integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_retur bigint,
  wajib_kunci integer,
  ada_dikirim boolean,
  ada_pending boolean,
  ada_batal boolean,
  ada_terkirim boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean := false;
  v_grup text;
BEGIN
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;
  v_grup := nullif(obos.grup_rute(p_rute_pengirim), '');
  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM obos.buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  RETURN QUERY
  WITH nota AS (
    SELECT o.*
    FROM obos.v_omset_nota o
    JOIN obos.rute_peta rp ON rp.rute_sales = o.rute
    WHERE o.waktu_packed IS NOT NULL
      AND (v_grup IS NULL OR rp.rute_pengirim = v_grup)
      AND obos.nota_ikut_pengirim(
        v_id, v_tgl, v_hidup, o.id_setoran_buku,
        o.status, o.waktu_order, o.waktu_actual, p_tanggal
      )
      AND obos.pengirim_bukan_batal_gudang(o.status, o.id_transaksi)
  ),
  hitung AS (
    SELECT
      n.id_pelanggan,
      max(n.nama_pelanggan) AS nama_pelanggan,
      max(n.rute) AS rute_sales,
      count(*)::integer AS jumlah_nota,
      coalesce(sum(n.jual_order), 0)::bigint AS omset_order,
      coalesce(sum(n.jual_packed), 0)::bigint AS omset_packed,
      coalesce(sum(n.jual_actual_kartu), 0)::bigint AS omset_actual,
      coalesce(sum(n.jual_batal), 0)::bigint AS omset_batal,
      count(*) FILTER (
        WHERE n.status = 'dikirim' AND NOT n.pending
      )::integer AS wajib_kunci,
      bool_or(n.status = 'dikirim') AS ada_dikirim,
      bool_or(n.pending) AS ada_pending,
      bool_or(n.jual_batal > 0) AS ada_batal,
      bool_or(n.status = 'terkirim') AS ada_terkirim
    FROM nota n
    GROUP BY n.id_pelanggan
  ),
  retur AS (
    SELECT
      i.id_pelanggan,
      coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS omset_retur
    FROM obos.retur_toko i
    WHERE v_id IS NOT NULL
      AND i.id_setoran_buku = v_id
      AND (v_grup IS NULL OR i.rute_pengirim = v_grup)
    GROUP BY i.id_pelanggan
  )
  SELECT
    h.id_pelanggan,
    h.nama_pelanggan,
    h.rute_sales,
    pl.latitude,
    pl.longitude,
    h.jumlah_nota,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.omset_batal,
    coalesce(r.omset_retur, 0)::bigint,
    h.wajib_kunci,
    h.ada_dikirim,
    h.ada_pending,
    h.ada_batal,
    h.ada_terkirim
  FROM hitung h
  LEFT JOIN retur r ON r.id_pelanggan = h.id_pelanggan
  LEFT JOIN obos.pelanggan pl ON pl.id_pelanggan = h.id_pelanggan
  ORDER BY lower(h.nama_pelanggan), h.id_pelanggan;
END;
$$;

CREATE OR REPLACE FUNCTION obos.ringkas_pengirim(
  p_tanggal date,
  p_rute_pengirim text DEFAULT NULL
)
RETURNS TABLE (
  jumlah_toko integer,
  jumlah_nota integer,
  wajib_kunci integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_pending bigint,
  omset_retur bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean := false;
  v_grup text;
  v_retur bigint := 0;
BEGIN
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;
  v_grup := nullif(obos.grup_rute(p_rute_pengirim), '');
  SELECT x.id, x.hidup INTO v_id, v_hidup
  FROM obos.buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  IF v_id IS NOT NULL THEN
    SELECT coalesce(sum(i.qty * i.harga_jual), 0)::bigint
    INTO v_retur
    FROM obos.retur_toko i
    WHERE i.id_setoran_buku = v_id
      AND (v_grup IS NULL OR i.rute_pengirim = v_grup);
  END IF;

  RETURN QUERY
  SELECT
    count(DISTINCT o.id_pelanggan)::integer,
    count(*)::integer,
    count(*) FILTER (WHERE o.status = 'dikirim' AND NOT o.pending)::integer,
    coalesce(sum(o.jual_order), 0)::bigint,
    coalesce(sum(o.jual_packed), 0)::bigint,
    coalesce(sum(o.jual_actual_kartu), 0)::bigint,
    coalesce(sum(o.jual_batal), 0)::bigint,
    coalesce(sum(o.jual_pending), 0)::bigint,
    v_retur
  FROM obos.v_omset_nota o
  JOIN obos.rute_peta rp ON rp.rute_sales = o.rute
  WHERE o.waktu_packed IS NOT NULL
    AND (v_grup IS NULL OR rp.rute_pengirim = v_grup)
    AND obos.nota_ikut_pengirim(
      v_id, v_tgl, v_hidup, o.id_setoran_buku,
      o.status, o.waktu_order, o.waktu_actual, p_tanggal
    )
    AND obos.pengirim_bukan_batal_gudang(o.status, o.id_transaksi);
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
        'buku_terbuka', 'buku_untuk_hari', 'pending_kartu',
        'kartu_setoran', 'kartu_gudang', 'kartu_pengirim', 'ringkas_pengirim'
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
