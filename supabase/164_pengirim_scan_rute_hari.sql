-- Scan pengirim: hari ini tetap rute kiriman (transaksi.rute / check-in),
-- rute master toko baru aktif mulai besok. Keluar boleh meski jalur sudah pindah.
-- Jalankan SETELAH 163. SQL Editor → Run. Boleh diulang.

CREATE OR REPLACE FUNCTION public.pengirim_scan_kunjungan(
  p_id_pelanggan text,
  p_keluar boolean,
  p_latitude double precision,
  p_longitude double precision,
  p_waktu timestamptz
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_rute_p text;
  v_rute_s text;
  v_sales text[];
  v_lat double precision;
  v_lng double precision;
  v_jarak double precision;
  v_tanggal date;
  v_masuk timestamptz;
  v_keluar timestamptz;
  v_now timestamptz;
  v_id_buku bigint;
  v_tgl date;
  v_hidup boolean := false;
  v_nota_saya boolean := false;
  v_nota_lain boolean := false;
  v_master boolean := false;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk gudang.';
  END IF;

  IF p_waktu IS NULL THEN
    RAISE EXCEPTION 'Waktu HP kosong';
  END IF;
  IF abs(extract(epoch FROM (p_waktu - clock_timestamp()))) > 180 THEN
    RAISE EXCEPTION 'Jam HP tidak sesuai waktu Jakarta. Nyalakan waktu otomatis, lalu scan lagi.';
  END IF;
  v_now := p_waktu;

  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  v_rute_p := public.pengirim_grup_rute(public.pengirim_rute_saya());
  v_sales := public.pengirim_rute_sales();
  IF v_id = '' OR v_rute_p IS NULL OR v_rute_p = '' THEN
    RAISE EXCEPTION 'Toko atau rute kosong.';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'Koordinat HP kosong';
  END IF;

  SELECT pl.latitude, pl.longitude, pl.rute
  INTO v_lat, v_lng, v_rute_s
  FROM public.pelanggan pl
  WHERE pl.id_pelanggan = v_id
    AND COALESCE(pl.aktif, true);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Toko tidak ada.';
  END IF;
  IF v_lat IS NULL OR v_lng IS NULL OR (v_lat = 0 AND v_lng = 0) THEN
    RAISE EXCEPTION 'Toko belum punya koordinat GPS.';
  END IF;

  v_jarak := 6371000 * 2 * asin(sqrt(least(1.0,
    power(sin(radians(p_latitude - v_lat) / 2), 2) +
    cos(radians(v_lat)) * cos(radians(p_latitude)) *
    power(sin(radians(p_longitude - v_lng) / 2), 2)
  )));

  IF v_jarak > 20 THEN
    RAISE EXCEPTION 'Anda masih % m dari toko. Mendekatlah, lalu scan lagi.',
      round(v_jarak);
  END IF;

  v_tanggal := (v_now AT TIME ZONE 'Asia/Jakarta')::date;
  PERFORM pg_advisory_xact_lock(hashtext(v_rute_p || ':' || v_id || ':' || v_tanggal::text));

  SELECT waktu_masuk, waktu_keluar
  INTO v_masuk, v_keluar
  FROM public.kunjungan_pengirim
  WHERE rute_pengirim = v_rute_p
    AND id_pelanggan = v_id
    AND tanggal = v_tanggal
  FOR UPDATE;

  IF COALESCE(p_keluar, false) THEN
    IF v_masuk IS NULL THEN
      RAISE EXCEPTION 'Belum check-in hari ini. Scan masuk dulu.';
    END IF;
    IF v_keluar IS NOT NULL THEN
      RETURN v_keluar;
    END IF;
    UPDATE public.kunjungan_pengirim
    SET waktu_keluar = v_now,
        jarak = v_jarak
    WHERE rute_pengirim = v_rute_p
      AND id_pelanggan = v_id
      AND tanggal = v_tanggal;
    RETURN v_now;
  END IF;

  IF v_keluar IS NOT NULL THEN
    RAISE EXCEPTION 'Kunjungan toko ini hari ini sudah selesai.';
  END IF;
  IF v_masuk IS NOT NULL THEN
    RETURN v_masuk;
  END IF;

  v_master := COALESCE(v_rute_s, '') = ANY (COALESCE(v_sales, ARRAY[]::text[]));

  SELECT x.id, x.tanggal, x.hidup INTO v_id_buku, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(v_tanggal) x;
  v_tgl := v_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  SELECT
    bool_or(t.rute = ANY (v_sales)),
    bool_or(NOT (t.rute = ANY (v_sales)))
  INTO v_nota_saya, v_nota_lain
  FROM public.transaksi t
  WHERE t.id_pelanggan = v_id
    AND t.waktu_packed IS NOT NULL
    AND public.pengirim_nota_ikut_buku(
      v_id_buku, v_tgl, v_hidup, t.id_setoran_buku,
      t.status, t.waktu_order, t.waktu_actual, v_tanggal
    );

  v_nota_saya := COALESCE(v_nota_saya, false);
  v_nota_lain := COALESCE(v_nota_lain, false);

  IF NOT (v_nota_saya OR (v_master AND NOT v_nota_lain)) THEN
    RAISE EXCEPTION 'Toko tidak ada di rute Anda';
  END IF;

  IF v_nota_saya THEN
    SELECT t.rute INTO v_rute_s
    FROM public.transaksi t
    WHERE t.id_pelanggan = v_id
      AND t.rute = ANY (v_sales)
      AND t.waktu_packed IS NOT NULL
      AND public.pengirim_nota_ikut_buku(
        v_id_buku, v_tgl, v_hidup, t.id_setoran_buku,
        t.status, t.waktu_order, t.waktu_actual, v_tanggal
      )
    ORDER BY t.waktu_packed DESC NULLS LAST
    LIMIT 1;
  END IF;

  INSERT INTO public.kunjungan_pengirim (
    id_pelanggan, rute_pengirim, rute_sales, tanggal, waktu_masuk, waktu_keluar, jarak
  ) VALUES (
    v_id, v_rute_p, COALESCE(v_rute_s, ''), v_tanggal, v_now, NULL, v_jarak
  )
  ON CONFLICT (rute_pengirim, id_pelanggan, tanggal) DO UPDATE
  SET waktu_masuk = COALESCE(public.kunjungan_pengirim.waktu_masuk, EXCLUDED.waktu_masuk),
      jarak = EXCLUDED.jarak
  WHERE public.kunjungan_pengirim.waktu_keluar IS NULL;

  RETURN v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_scan_kunjungan(
  text, boolean, double precision, double precision, timestamptz
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_scan_kunjungan(
  text, boolean, double precision, double precision, timestamptz
) TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
