-- Absensi pengirim menempel ke buku setoran terbuka.
-- Data lama tanpa id_setoran_buku diikat ke buku tanggal yang sama.
-- Jalankan SETELAH 053. Boleh diulang.

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
    'keluar', false,
    'id_setoran_buku', v_buku
  );
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_scan_absensi(boolean, double precision, double precision, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_scan_absensi(boolean, double precision, double precision, timestamptz)
  TO authenticated, postgres, service_role;

UPDATE public.absensi a
SET id_setoran_buku = b.id
FROM public.setoran_buku b
WHERE a.id_setoran_buku IS NULL
  AND a.waktu_masuk IS NOT NULL
  AND b.tanggal = a.tanggal;

CREATE OR REPLACE FUNCTION public.admin_absensi_buku()
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
  v_baris jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    SELECT b.id, b.tanggal INTO v_id, v_tgl
    FROM public.setoran_buku b
    ORDER BY b.id DESC
    LIMIT 1;
  ELSE
    SELECT b.tanggal INTO v_tgl
    FROM public.setoran_buku b
    WHERE b.id = v_id;
  END IF;

  IF v_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'nama_kunci', u.email,
        'nama', u.nama,
        'urutan', CASE WHEN u.peran = 'pengirim' THEN 0 ELSE 1 END,
        'peran', u.peran,
        'di_dalam', EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        ),
        'pulang', EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NOT NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        )
      )
      ORDER BY
        CASE WHEN u.peran = 'pengirim' THEN 0 ELSE 1 END,
        u.rute,
        u.nama
    ),
    '[]'::jsonb
  )
  INTO v_baris
  FROM public.users u
  WHERE u.peran IN ('pengirim', 'gudang');

  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_absensi_buku() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_absensi_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
