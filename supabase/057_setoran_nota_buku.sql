-- Kartu setoran hanya menghitung nota buku ini.
-- Nota packed tanpa id hanya ikut jika buku masih terbuka.
-- Pengirim: nota dikirim ikut id buku, bukan hanya tanggal HP = hari ini.
-- Jalankan SETELAH 056. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_transaksi_ikut_buku(
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
            AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
          )
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_setoran_kartu_hidup(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_baris jsonb;
BEGIN
  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'dari_snapshot', false,
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
    FROM (
      SELECT DISTINCT rute_pengirim
      FROM public.rute_peta
    ) p
    LEFT JOIN (
      SELECT
        rp.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS kiriman,
        coalesce(sum(
          CASE WHEN t.status = 'batal' THEN i.subtotal_jual_packed ELSE 0 END
        ), 0)::bigint AS batal,
        coalesce(sum(
          CASE WHEN t.pending THEN i.subtotal_jual_packed ELSE 0 END
        ), 0)::bigint AS pending,
        coalesce(sum(
          CASE WHEN t.status = 'batal' THEN 0 ELSE i.subtotal_jual_actual END
        ), 0)::bigint AS actual,
        count(DISTINCT t.id_transaksi) FILTER (
          WHERE t.status = 'dikirim' AND NOT t.pending
        )::integer AS wajib_kunci
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
      WHERE t.waktu_packed IS NOT NULL
        AND public.admin_transaksi_ikut_buku(
          v_id, v_tgl, v_tutup, t.id_setoran_buku, t.status, t.waktu_actual
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN public.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        public.pengirim_grup_rute(u.rute) AS rute_pengirim,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'D' THEN u.nama END) AS nama_supir,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'H' THEN u.nama END) AS nama_kenek
      FROM public.users u
      WHERE u.peran = 'pengirim'
      GROUP BY public.pengirim_grup_rute(u.rute)
    ) nm ON nm.rute_pengirim = p.rute_pengirim
    LEFT JOIN (
      SELECT
        i.rute_pengirim,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM public.retur_toko i
      WHERE i.id_setoran_buku = v_id
      GROUP BY i.rute_pengirim
    ) r ON r.rute_pengirim = p.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', coalesce(v_tutup, false),
    'dari_snapshot', false,
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_ringkas_hari(p_tanggal date)
RETURNS TABLE (
  jumlah_toko integer,
  jumlah_nota integer,
  wajib_kunci integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_pending bigint,
  omset_retur bigint,
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
  v_sales text[];
  v_hari date;
  v_today date;
  v_id_buku bigint;
  v_rute text;
  v_retur bigint := 0;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_sales := public.pengirim_rute_sales();
  v_hari := p_tanggal;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

  v_id_buku := public.pengirim_buku_hari(v_hari);
  IF v_id_buku IS NOT NULL AND v_rute IS NOT NULL THEN
    SELECT coalesce(sum(i.qty * i.harga_jual), 0)::bigint
    INTO v_retur
    FROM public.retur_toko i
    WHERE i.id_setoran_buku = v_id_buku
      AND i.rute_pengirim = v_rute;
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND (
        (v_id_buku IS NOT NULL AND t.id_setoran_buku = v_id_buku)
        OR (
          t.status = 'dikirim'
          AND t.id_setoran_buku IS NULL
          AND v_hari = v_today
        )
        OR (
          v_id_buku IS NULL
          AND t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
        )
      )
  ),
  item AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.status,
      n.pending,
      coalesce(sum(i.subtotal_jual_order), 0) AS jual_order,
      coalesce(sum(i.subtotal_beli_order), 0) AS beli_order,
      coalesce(sum(i.subtotal_jual_packed), 0) AS jual_packed,
      coalesce(sum(i.subtotal_beli_packed), 0) AS beli_packed,
      coalesce(sum(i.subtotal_jual_actual), 0) AS jual_actual,
      coalesce(sum(i.subtotal_beli_actual), 0) AS beli_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.id_transaksi, n.id_pelanggan, n.status, n.pending
  )
  SELECT
    count(DISTINCT i.id_pelanggan)::integer,
    count(*)::integer,
    count(*) FILTER (WHERE i.status = 'dikirim' AND NOT i.pending)::integer,
    coalesce(sum(i.jual_order), 0)::bigint,
    coalesce(sum(i.jual_packed), 0)::bigint,
    coalesce(sum(CASE WHEN i.status = 'batal' THEN 0 ELSE i.jual_actual END), 0)::bigint,
    coalesce(sum(CASE WHEN i.status = 'batal' THEN i.jual_packed ELSE 0 END), 0)::bigint,
    coalesce(sum(CASE WHEN i.pending THEN i.jual_packed ELSE 0 END), 0)::bigint,
    v_retur,
    coalesce(sum(i.jual_order - i.beli_order), 0)::bigint,
    coalesce(sum(i.jual_packed - i.beli_packed), 0)::bigint,
    coalesce(sum(
      CASE WHEN i.status = 'batal' THEN 0 ELSE i.jual_actual - i.beli_actual END
    ), 0)::bigint
  FROM item i;
END;
$$;

DROP FUNCTION IF EXISTS public.pengirim_kartu_toko(date);
CREATE FUNCTION public.pengirim_kartu_toko(p_tanggal date)
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
  ada_terkirim boolean,
  waktu_masuk timestamptz,
  waktu_keluar timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sales text[];
  v_hari date;
  v_today date;
  v_id_buku bigint;
  v_id_buka bigint;
  v_tgl_buka date;
  v_grup text;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_sales := public.pengirim_rute_sales();
  v_hari := p_tanggal;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_grup := public.pengirim_grup_rute(public.pengirim_rute_saya());
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

  SELECT b.id, b.tanggal INTO v_id_buka, v_tgl_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  LIMIT 1;
  IF v_id_buka IS NOT NULL AND (v_hari = v_today OR v_hari = v_tgl_buka) THEN
    v_id_buku := v_id_buka;
  ELSE
    SELECT b.id INTO v_id_buku
    FROM public.setoran_buku b
    WHERE b.tanggal = v_hari
    ORDER BY b.id DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND (
        (v_id_buku IS NOT NULL AND t.id_setoran_buku = v_id_buku)
        OR (
          t.status = 'dikirim'
          AND t.id_setoran_buku IS NULL
          AND v_hari = v_today
        )
        OR (
          v_id_buku IS NULL
          AND t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
        )
      )
  ),
  hitung AS (
    SELECT
      n.id_pelanggan,
      max(n.nama_pelanggan) AS nama_pelanggan,
      max(n.rute) AS rute_sales,
      count(*)::integer AS jumlah_nota,
      coalesce(sum((
        SELECT coalesce(sum(i.subtotal_jual_order), 0)
        FROM public.v_transaksi_item i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_order,
      coalesce(sum((
        SELECT coalesce(sum(i.subtotal_jual_packed), 0)
        FROM public.v_transaksi_item i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_packed,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN 0
             ELSE (
               SELECT coalesce(sum(i.subtotal_jual_actual), 0)
               FROM public.v_transaksi_item i
               WHERE i.id_transaksi = n.id_transaksi
             )
        END
      ), 0)::bigint AS omset_actual,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN (
          SELECT coalesce(sum(i.subtotal_jual_packed), 0)
          FROM public.v_transaksi_item i
          WHERE i.id_transaksi = n.id_transaksi
        ) ELSE 0 END
      ), 0)::bigint AS omset_batal,
      count(*) FILTER (
        WHERE n.status = 'dikirim' AND NOT n.pending
      )::integer AS wajib_kunci,
      bool_or(n.status = 'dikirim') AS ada_dikirim,
      bool_or(n.pending) AS ada_pending,
      bool_or(n.status = 'batal') AS ada_batal,
      bool_or(n.status = 'terkirim') AS ada_terkirim
    FROM nota n
    GROUP BY n.id_pelanggan
  ),
  retur AS (
    SELECT
      i.id_pelanggan,
      coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS omset_retur
    FROM public.retur_toko i
    WHERE v_id_buku IS NOT NULL
      AND i.id_setoran_buku = v_id_buku
      AND i.rute_pengirim = v_grup
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
    h.ada_terkirim,
    k.waktu_masuk,
    k.waktu_keluar
  FROM hitung h
  LEFT JOIN retur r ON r.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.pelanggan pl ON pl.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.kunjungan_pengirim k
    ON k.id_pelanggan = h.id_pelanggan
   AND k.rute_pengirim = v_grup
   AND k.tanggal = v_hari
  ORDER BY lower(h.nama_pelanggan), h.id_pelanggan;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_kartu_hidup(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu_hidup(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_ringkas_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_ringkas_hari(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_kartu_toko(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kartu_toko(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
