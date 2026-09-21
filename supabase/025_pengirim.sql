-- Pengirim tahap 1–2: absensi gudang + peta rute + kartu toko.
-- Jalankan SETELAH 014 (setoran_buku) dan 010 (absensi). Skema public. Boleh diulang.

CREATE TABLE IF NOT EXISTS public.rute_peta (
  rute_sales text PRIMARY KEY,
  rute_pengirim text NOT NULL,
  CONSTRAINT rute_peta_sales_chk CHECK (btrim(rute_sales) <> ''),
  CONSTRAINT rute_peta_pengirim_chk CHECK (btrim(rute_pengirim) <> '')
);

COMMENT ON TABLE public.rute_peta IS
  'Satu rute sales = satu grup pengirim. SBGP04D dan SBGP04H memakai baris SBGP04.';
COMMENT ON COLUMN public.rute_peta.rute_pengirim IS
  'Grup tanpa shift (SBGP04). Bukan SBGP04D / SBGP04H.';

CREATE INDEX IF NOT EXISTS rute_peta_pengirim_idx
  ON public.rute_peta (rute_pengirim);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rute_peta
  TO postgres, service_role;
REVOKE ALL ON TABLE public.rute_peta FROM anon, authenticated;
ALTER TABLE public.rute_peta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rute_peta FORCE ROW LEVEL SECURITY;

INSERT INTO public.rute_peta (rute_sales, rute_pengirim) VALUES
  ('SBGS01', 'SBGP01'),
  ('SBGS02', 'SBGP01'),
  ('SBGS03', 'SBGP02'),
  ('SBGS04', 'SBGP02'),
  ('SBGS05', 'SBGP03'),
  ('SBGS06', 'SBGP03'),
  ('SBGS07', 'SBGP04'),
  ('SBGS08', 'SBGP04')
ON CONFLICT (rute_sales) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pengirim_grup_rute(p_rute text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(upper(btrim(COALESCE(p_rute, ''))), '[DH]$', '');
$$;

CREATE OR REPLACE FUNCTION public.pengirim_rute_saya()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT nullif(btrim(u.rute), '')
  FROM public.users u
  WHERE lower(trim(u.email)) = public.email_jwt()
    AND u.peran = 'pengirim'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_rute_sales()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    array_agg(p.rute_sales ORDER BY p.rute_sales),
    ARRAY[]::text[]
  )
  FROM public.rute_peta p
  WHERE p.rute_pengirim = public.pengirim_grup_rute(public.pengirim_rute_saya());
$$;

CREATE OR REPLACE FUNCTION public.pengirim_id_absensi_saya()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT a.id
  FROM public.absensi a
  WHERE lower(btrim(a.email)) = lower(btrim(COALESCE(auth.jwt() ->> 'email', '')))
    AND a.peran = 'pengirim'
    AND a.waktu_masuk IS NOT NULL
    AND a.waktu_keluar IS NULL
  ORDER BY a.waktu_masuk DESC, a.id DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_status_lantai()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_masuk timestamptz;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RETURN jsonb_build_object(
      'login', false,
      'absensi_terbuka', false,
      'id_absensi', NULL,
      'waktu_masuk', NULL
    );
  END IF;

  SELECT a.id, a.waktu_masuk
  INTO v_id, v_masuk
  FROM public.absensi a
  WHERE lower(btrim(a.email)) = lower(btrim(COALESCE(auth.jwt() ->> 'email', '')))
    AND a.peran = 'pengirim'
    AND a.waktu_masuk IS NOT NULL
    AND a.waktu_keluar IS NULL
  ORDER BY a.waktu_masuk DESC, a.id DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'login', true,
    'absensi_terbuka', v_id IS NOT NULL,
    'id_absensi', v_id,
    'waktu_masuk', v_masuk
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_scan_absensi(
  p_keluar boolean,
  p_latitude double precision,
  p_longitude double precision,
  p_waktu timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_email text;
  v_peran text;
  v_rute text;
  v_now timestamptz;
  v_tanggal date;
  v_id bigint;
  v_buku bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;

  IF p_waktu IS NULL THEN
    RAISE EXCEPTION 'Waktu HP kosong';
  END IF;
  IF abs(extract(epoch FROM (p_waktu - clock_timestamp()))) > 180 THEN
    RAISE EXCEPTION 'Jam HP tidak sesuai waktu Jakarta. Nyalakan waktu otomatis, lalu scan lagi.';
  END IF;
  v_now := p_waktu;
  v_tanggal := (timezone('Asia/Jakarta', v_now))::date;
  v_buku := public.setoran_buku_terbuka();

  PERFORM public.pastikan_di_gudang(p_latitude, p_longitude);

  v_email := lower(btrim(COALESCE(auth.jwt() ->> 'email', '')));
  IF v_email = '' THEN
    RAISE EXCEPTION 'Email sesi kosong.';
  END IF;

  SELECT lower(btrim(u.peran)), u.rute INTO v_peran, v_rute
  FROM public.users u
  WHERE lower(btrim(u.email)) = v_email
  LIMIT 1;

  IF v_peran IS DISTINCT FROM 'pengirim' THEN
    RAISE EXCEPTION 'Hanya pengirim yang boleh scan absensi di aplikasi ini.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_email));

  IF p_keluar THEN
    SELECT a.id INTO v_id
    FROM public.absensi a
    WHERE lower(btrim(a.email)) = v_email
      AND a.waktu_keluar IS NULL
    ORDER BY a.waktu_masuk DESC NULLS LAST, a.id DESC
    LIMIT 1
    FOR UPDATE;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Belum scan masuk.';
    END IF;

    UPDATE public.absensi
    SET
      waktu_keluar = v_now,
      id_setoran_buku = COALESCE(id_setoran_buku, v_buku)
    WHERE id = v_id
      AND waktu_keluar IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sudah scan pulang.';
    END IF;

    RETURN jsonb_build_object(
      'id_absensi', v_id,
      'tanggal', v_tanggal,
      'waktu', v_now,
      'keluar', true
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.absensi a
    WHERE lower(btrim(a.email)) = v_email
      AND a.waktu_keluar IS NULL
  ) THEN
    RAISE EXCEPTION 'Sudah scan masuk.';
  END IF;

  INSERT INTO public.absensi (
    email, peran, rute, tanggal, waktu_masuk, waktu_keluar, id_setoran_buku
  ) VALUES (
    v_email, v_peran, v_rute, v_tanggal, v_now, NULL, v_buku
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id_absensi', v_id,
    'tanggal', v_tanggal,
    'waktu', v_now,
    'keluar', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_kartu_toko(p_tanggal date)
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute_sales text,
  latitude double precision,
  longitude double precision,
  jumlah_nota integer,
  omset_packed bigint,
  omset_actual bigint,
  wajib_kunci integer
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
        (t.status = 'dikirim' AND v_hari = v_today)
        OR (
          t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND CASE
            WHEN v_id_buku IS NOT NULL THEN t.id_setoran_buku = v_id_buku
            ELSE (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
          END
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
        SELECT coalesce(sum(i.subtotal_jual_packed), 0)
        FROM public.transaksi_items i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_packed,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN 0
             ELSE (
               SELECT coalesce(sum(i.subtotal_jual_actual), 0)
               FROM public.transaksi_items i
               WHERE i.id_transaksi = n.id_transaksi
             )
        END
      ), 0)::bigint AS omset_actual,
      count(*) FILTER (
        WHERE n.status = 'dikirim' AND NOT n.pending
      )::integer AS wajib_kunci
    FROM nota n
    GROUP BY n.id_pelanggan
  )
  SELECT
    h.id_pelanggan,
    h.nama_pelanggan,
    h.rute_sales,
    pl.latitude,
    pl.longitude,
    h.jumlah_nota,
    h.omset_packed,
    h.omset_actual,
    h.wajib_kunci
  FROM hitung h
  LEFT JOIN public.pelanggan pl ON pl.id_pelanggan = h.id_pelanggan
  ORDER BY lower(h.nama_pelanggan), h.id_pelanggan;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_grup_rute(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_grup_rute(text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_rute_saya() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_rute_saya()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_rute_sales() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_rute_sales()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_id_absensi_saya() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_id_absensi_saya()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_status_lantai() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_status_lantai()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_scan_absensi(boolean, double precision, double precision, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_scan_absensi(boolean, double precision, double precision, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_kartu_toko(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kartu_toko(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
