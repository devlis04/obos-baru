-- Alur scan absensi = scan salesman (jam HP ±3 menit, lokasi untuk overlay jarak).
-- Jalankan SETELAH 010_gudang_absensi.sql. Aman diulang.

CREATE OR REPLACE FUNCTION public.gudang_waktu_sekarang()
RETURNS timestamptz
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT clock_timestamp();
$$;

CREATE OR REPLACE FUNCTION public.gudang_lokasi_utama()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_nama text;
  v_lat double precision;
  v_lng double precision;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Tidak terautentikasi';
  END IF;

  SELECT l.nama, l.latitude, l.longitude
  INTO v_nama, v_lat, v_lng
  FROM public.lokasi_gudang l
  WHERE l.id = 'utama'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lokasi gudang belum diisi.';
  END IF;

  RETURN jsonb_build_object(
    'nama', v_nama,
    'latitude', v_lat,
    'longitude', v_lng
  );
END;
$$;

DROP FUNCTION IF EXISTS public.gudang_scan_absensi(boolean, double precision, double precision);
DROP FUNCTION IF EXISTS public.gudang_scan_absensi(boolean, double precision, double precision, timestamptz);

CREATE OR REPLACE FUNCTION public.gudang_scan_absensi(
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
BEGIN
  IF NOT public.gudang_sedang_login() THEN
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

  PERFORM public.pastikan_di_gudang(p_latitude, p_longitude);

  v_email := lower(btrim(COALESCE(auth.jwt() ->> 'email', '')));
  IF v_email = '' THEN
    RAISE EXCEPTION 'Email sesi kosong.';
  END IF;

  SELECT lower(btrim(u.peran)), u.rute INTO v_peran, v_rute
  FROM public.users u
  WHERE lower(btrim(u.email)) = v_email
  LIMIT 1;

  IF v_peran IS NULL OR v_peran NOT IN ('gudang', 'admin') THEN
    RAISE EXCEPTION 'Hanya gudang atau admin yang boleh scan absensi di aplikasi ini.';
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
    SET waktu_keluar = v_now
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
    email, peran, rute, tanggal, waktu_masuk, waktu_keluar
  ) VALUES (
    v_email, v_peran, v_rute, v_tanggal, v_now, NULL
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

REVOKE ALL ON FUNCTION public.gudang_waktu_sekarang() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_waktu_sekarang()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_lokasi_utama() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_lokasi_utama()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_scan_absensi(boolean, double precision, double precision, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_scan_absensi(boolean, double precision, double precision, timestamptz)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
