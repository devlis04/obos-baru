-- RPC absensi gudang/pengirim/admin + kunjungan sales/pengirim.
-- Jalankan SETELAH 006. Uji SQL Editor (postgres). Tidak cek sesi HP.
-- Titik gudang 20 m; toko 20 m. public/app tidak diubah. Boleh diulang.

CREATE OR REPLACE FUNCTION obos.jarak_meter(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 6371000 * 2 * asin(sqrt(least(1.0,
    power(sin(radians(p_lat1 - p_lat2) / 2), 2) +
    cos(radians(p_lat2)) * cos(radians(p_lat1)) *
    power(sin(radians(p_lng1 - p_lng2) / 2), 2)
  )));
$$;

CREATE OR REPLACE FUNCTION obos.waktu_hp(p_waktu timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
BEGIN
  IF p_waktu IS NULL THEN
    RETURN clock_timestamp();
  END IF;
  IF abs(extract(epoch FROM (p_waktu - clock_timestamp()))) > 180 THEN
    RAISE EXCEPTION 'Jam HP tidak sesuai waktu Jakarta. Nyalakan waktu otomatis, lalu scan lagi.';
  END IF;
  RETURN p_waktu;
END;
$$;

CREATE OR REPLACE FUNCTION obos.lokasi_gudang_lihat()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_nama text;
  v_lat double precision;
  v_lng double precision;
BEGIN
  SELECT l.nama, l.latitude, l.longitude
  INTO v_nama, v_lat, v_lng
  FROM obos.lokasi_gudang l
  WHERE l.id = 'utama'
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lokasi gudang belum diisi.';
  END IF;
  RETURN jsonb_build_object('nama', v_nama, 'latitude', v_lat, 'longitude', v_lng);
END;
$$;

CREATE OR REPLACE FUNCTION obos.lokasi_gudang_simpan(
  p_latitude double precision,
  p_longitude double precision,
  p_nama text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_nama text;
BEGIN
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'Koordinat gudang wajib.';
  END IF;
  v_nama := nullif(btrim(COALESCE(p_nama, '')), '');
  INSERT INTO obos.lokasi_gudang (id, nama, latitude, longitude)
  VALUES ('utama', COALESCE(v_nama, 'Gudang Utama'), p_latitude, p_longitude)
  ON CONFLICT (id) DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    nama = COALESCE(v_nama, obos.lokasi_gudang.nama);
  RETURN obos.lokasi_gudang_lihat();
END;
$$;

CREATE OR REPLACE FUNCTION obos.pastikan_di_gudang(
  p_latitude double precision,
  p_longitude double precision
)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_lat double precision;
  v_lng double precision;
  v_jarak double precision;
BEGIN
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'Koordinat HP kosong';
  END IF;
  SELECT latitude, longitude INTO v_lat, v_lng
  FROM obos.lokasi_gudang
  WHERE id = 'utama'
  LIMIT 1;
  IF NOT FOUND
     OR v_lat IS NULL OR v_lng IS NULL
     OR (v_lat = 0 AND v_lng = 0) THEN
    RAISE EXCEPTION 'Titik lokasi gudang belum diisi. Isi koordinat gudang dulu, lalu scan lagi.';
  END IF;
  v_jarak := obos.jarak_meter(p_latitude, p_longitude, v_lat, v_lng);
  IF v_jarak > 20 THEN
    RAISE EXCEPTION 'Anda masih % m dari gudang. Mendekatlah, lalu scan lagi.',
      round(v_jarak);
  END IF;
  RETURN v_jarak;
END;
$$;

CREATE OR REPLACE FUNCTION obos.pesan_tutup_dulu(p_tanggal date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT format(
    'Minta admin tutup buku dulu. Buku %s masih terbuka; malam baru tidak bisa memakai buku itu.',
    to_char(p_tanggal, 'FMDD-MM-YYYY')
  );
$$;

CREATE OR REPLACE FUNCTION obos.buku_ada_dikirim(p_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM obos.transaksi t
    WHERE t.id_setoran_buku = p_id
      AND t.status = 'dikirim'
      AND NOT COALESCE(t.pending, false)
  );
$$;

CREATE OR REPLACE FUNCTION obos.kunci_malam_baru(p_id bigint)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_tgl date;
  v_tutup boolean;
  v_hari date;
BEGIN
  IF p_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = p_id;
  IF NOT FOUND OR COALESCE(v_tutup, false) THEN
    RETURN false;
  END IF;
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  IF v_tgl >= v_hari THEN
    RETURN false;
  END IF;
  IF v_hari > v_tgl + 1 THEN
    RETURN true;
  END IF;
  IF obos.buku_ada_dikirim(p_id) THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION obos.tolak_buku_malam_baru()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_tgl date;
  v_tutup boolean;
BEGIN
  IF NEW.id_setoran_buku IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.id_setoran_buku IS NOT DISTINCT FROM NEW.id_setoran_buku THEN
    RETURN NEW;
  END IF;
  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = NEW.id_setoran_buku;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  IF COALESCE(v_tutup, false) THEN
    RAISE EXCEPTION 'Nota tidak bisa masuk buku yang sudah ditutup.';
  END IF;
  IF obos.kunci_malam_baru(NEW.id_setoran_buku) THEN
    RAISE EXCEPTION '%', obos.pesan_tutup_dulu(v_tgl);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trx_tolak_buku_malam_baru ON obos.transaksi;
CREATE TRIGGER trx_tolak_buku_malam_baru
  BEFORE INSERT OR UPDATE OF id_setoran_buku ON obos.transaksi
  FOR EACH ROW
  EXECUTE PROCEDURE obos.tolak_buku_malam_baru();

CREATE OR REPLACE FUNCTION obos.id_absensi_terbuka(p_email text)
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT a.id
  FROM obos.absensi a
  WHERE lower(btrim(a.email)) = lower(btrim(COALESCE(p_email, '')))
    AND a.waktu_masuk IS NOT NULL
    AND a.waktu_keluar IS NULL
  ORDER BY a.waktu_masuk DESC, a.id DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION obos.status_lantai(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_masuk timestamptz;
  v_peran text;
BEGIN
  SELECT lower(btrim(u.peran)) INTO v_peran
  FROM obos.users u
  WHERE lower(btrim(u.email)) = lower(btrim(COALESCE(p_email, '')));
  SELECT a.id, a.waktu_masuk INTO v_id, v_masuk
  FROM obos.absensi a
  WHERE a.id = obos.id_absensi_terbuka(p_email);
  RETURN jsonb_build_object(
    'email', lower(btrim(COALESCE(p_email, ''))),
    'peran', v_peran,
    'absensi_terbuka', v_id IS NOT NULL,
    'id_absensi', v_id,
    'waktu_masuk', v_masuk
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.scan_absensi(
  p_email text,
  p_keluar boolean,
  p_latitude double precision,
  p_longitude double precision,
  p_waktu timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_email text;
  v_peran text;
  v_rute text;
  v_now timestamptz;
  v_tanggal date;
  v_id bigint;
  v_buku bigint;
  v_tgl_buku date;
BEGIN
  v_email := lower(btrim(COALESCE(p_email, '')));
  IF v_email = '' THEN
    RAISE EXCEPTION 'Email wajib.';
  END IF;
  v_now := obos.waktu_hp(p_waktu);
  PERFORM obos.pastikan_di_gudang(p_latitude, p_longitude);

  SELECT lower(btrim(u.peran)), u.rute INTO v_peran, v_rute
  FROM obos.users u
  WHERE lower(btrim(u.email)) = v_email;
  IF v_peran IS NULL THEN
    RAISE EXCEPTION 'User tidak ada.';
  END IF;
  IF v_peran NOT IN ('gudang', 'admin', 'pengirim') THEN
    RAISE EXCEPTION 'Hanya gudang, admin, atau pengirim yang boleh scan absensi.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);
  PERFORM pg_advisory_xact_lock(hashtext(v_email));

  IF p_keluar THEN
    SELECT a.id INTO v_id
    FROM obos.absensi a
    WHERE lower(btrim(a.email)) = v_email
      AND a.waktu_keluar IS NULL
    ORDER BY a.waktu_masuk DESC NULLS LAST, a.id DESC
    LIMIT 1
    FOR UPDATE;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Belum scan masuk.';
    END IF;
    v_buku := obos.buku_terbuka();
    UPDATE obos.absensi
    SET
      waktu_keluar = v_now,
      id_setoran_buku = COALESCE(id_setoran_buku, v_buku)
    WHERE id = v_id AND waktu_keluar IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sudah scan pulang.';
    END IF;
    SELECT a.tanggal INTO v_tanggal FROM obos.absensi a WHERE a.id = v_id;
    RETURN jsonb_build_object(
      'id_absensi', v_id,
      'tanggal', v_tanggal,
      'waktu', v_now,
      'keluar', true
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM obos.absensi a
    WHERE lower(btrim(a.email)) = v_email AND a.waktu_keluar IS NULL
  ) THEN
    RAISE EXCEPTION 'Sudah scan masuk.';
  END IF;

  v_buku := obos.buku_terbuka();
  IF v_buku IS NOT NULL THEN
    SELECT b.tanggal INTO v_tgl_buku FROM obos.setoran_buku b WHERE b.id = v_buku;
    IF obos.kunci_malam_baru(v_buku) THEN
      RAISE EXCEPTION '%', obos.pesan_tutup_dulu(v_tgl_buku);
    END IF;
  END IF;

  IF v_peran = 'pengirim' THEN
    IF v_buku IS NULL THEN
      RAISE EXCEPTION 'Belum ada buku setoran. Gudang scan masuk dulu.';
    END IF;
    v_tanggal := (timezone('Asia/Jakarta', v_now))::date;
  ELSE
    v_buku := obos.buka_buku();
    SELECT b.tanggal INTO v_tanggal FROM obos.setoran_buku b WHERE b.id = v_buku;
  END IF;

  INSERT INTO obos.absensi (
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

CREATE OR REPLACE FUNCTION obos.absensi_buku(p_id_buku bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_baris jsonb;
BEGIN
  IF p_id_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal INTO v_id, v_tgl
    FROM obos.setoran_buku b
    WHERE b.id = p_id_buku;
  ELSE
    SELECT b.id, b.tanggal INTO v_id, v_tgl
    FROM obos.setoran_buku b
    WHERE NOT b.ditutup
    ORDER BY b.id
    LIMIT 1;
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
        'rute', u.rute,
        'di_dalam', EXISTS (
          SELECT 1 FROM obos.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        ),
        'pulang', EXISTS (
          SELECT 1 FROM obos.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NOT NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        )
        AND NOT EXISTS (
          SELECT 1 FROM obos.absensi a
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
  FROM obos.users u
  WHERE u.peran IN ('pengirim', 'gudang');

  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION obos.buku_siklus()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_dikirim integer := 0;
  v_dalam integer := 0;
  v_fisik integer := 0;
  v_minus integer := 0;
  v_kunci boolean := false;
  v_siap boolean := false;
  v_pesan text := '';
BEGIN
  v_id := obos.buku_terbuka();
  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', true,
      'malam_baru_tertahan', false,
      'n_dikirim', 0,
      'n_absen_dalam', 0,
      'sku_fisik', 0,
      'sku_minus_belum', 0,
      'siap_tutup', false,
      'pesan', ''
    );
  END IF;

  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = v_id;

  SELECT count(*)::integer INTO v_dikirim
  FROM obos.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);

  SELECT count(*)::integer INTO v_dalam
  FROM obos.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'pengirim')
    AND (
      a.id_setoran_buku = v_id
      OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
    );

  SELECT
    count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer,
    count(*) FILTER (
      WHERE so.stok_fisik IS NOT NULL
        AND COALESCE(so.selisih, 0) < 0
        AND so.putusan IS DISTINCT FROM 'kasbon'
        AND so.putusan IS DISTINCT FROM 'beban'
    )::integer
  INTO v_fisik, v_minus
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id;

  v_kunci := obos.kunci_malam_baru(v_id);
  v_siap := v_dikirim = 0 AND v_dalam = 0 AND v_fisik > 0 AND v_minus = 0;

  IF v_siap THEN
    v_pesan := format(
      'Buku %s sesuai. Tutup buku supaya malam berikutnya memakai buku baru.',
      to_char(v_tgl, 'FMDD-MM-YYYY')
    );
  ELSIF v_dikirim > 0 THEN
    v_pesan := format(
      'Buku %s masih terbuka. %s nota masih dikirim. Pengirim selesaikan dulu, lalu tutup buku.',
      to_char(v_tgl, 'FMDD-MM-YYYY'),
      v_dikirim
    );
  ELSIF v_kunci THEN
    v_pesan := obos.pesan_tutup_dulu(v_tgl);
  END IF;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', COALESCE(v_tutup, false),
    'malam_baru_tertahan', v_kunci,
    'n_dikirim', v_dikirim,
    'n_absen_dalam', v_dalam,
    'sku_fisik', v_fisik,
    'sku_minus_belum', v_minus,
    'siap_tutup', v_siap,
    'pesan', v_pesan
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.kunjungan_sales_scan(
  p_rute text,
  p_id_pelanggan text,
  p_keluar boolean,
  p_latitude double precision,
  p_longitude double precision,
  p_waktu timestamptz DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_lat double precision;
  v_lng double precision;
  v_jarak double precision;
  v_tanggal date;
  v_id text;
  v_masuk timestamptz;
  v_keluar timestamptz;
  v_now timestamptz;
BEGIN
  v_now := obos.waktu_hp(p_waktu);
  v_rute := btrim(COALESCE(p_rute, ''));
  IF v_rute = '' THEN
    RAISE EXCEPTION 'Rute salesman kosong';
  END IF;
  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'Toko kosong';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'Koordinat HP kosong';
  END IF;

  SELECT latitude, longitude INTO v_lat, v_lng
  FROM obos.pelanggan
  WHERE id_pelanggan = v_id
    AND rute = v_rute
    AND COALESCE(aktif, true);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Toko tidak ada di rute Anda';
  END IF;
  IF v_lat IS NULL OR v_lng IS NULL OR (v_lat = 0 AND v_lng = 0) THEN
    RAISE EXCEPTION 'Toko belum punya koordinat GPS.';
  END IF;

  v_jarak := obos.jarak_meter(p_latitude, p_longitude, v_lat, v_lng);
  IF v_jarak > 20 THEN
    RAISE EXCEPTION 'Anda masih % m dari toko. Mendekatlah, lalu scan lagi.',
      round(v_jarak);
  END IF;

  v_tanggal := (v_now AT TIME ZONE 'Asia/Jakarta')::date;
  PERFORM pg_advisory_xact_lock(hashtext(v_rute || ':' || v_id || ':' || v_tanggal::text));

  SELECT waktu_masuk, waktu_keluar INTO v_masuk, v_keluar
  FROM obos.kunjungan_sales
  WHERE id_pelanggan = v_id AND tanggal = v_tanggal
  FOR UPDATE;

  IF COALESCE(p_keluar, false) THEN
    IF v_masuk IS NULL THEN
      RAISE EXCEPTION 'Belum check-in hari ini. Scan masuk dulu.';
    END IF;
    IF v_keluar IS NOT NULL THEN
      RETURN v_keluar;
    END IF;
    UPDATE obos.kunjungan_sales
    SET waktu_keluar = v_now, jarak = v_jarak
    WHERE id_pelanggan = v_id AND tanggal = v_tanggal;
    RETURN v_now;
  END IF;

  IF v_keluar IS NOT NULL THEN
    RAISE EXCEPTION 'Kunjungan toko ini hari ini sudah selesai.';
  END IF;
  IF v_masuk IS NOT NULL THEN
    RETURN v_masuk;
  END IF;

  INSERT INTO obos.kunjungan_sales (
    id_pelanggan, rute, tanggal, waktu_masuk, waktu_keluar, jarak
  ) VALUES (
    v_id, v_rute, v_tanggal, v_now, NULL, v_jarak
  )
  ON CONFLICT (id_pelanggan, tanggal) DO UPDATE
  SET waktu_masuk = COALESCE(obos.kunjungan_sales.waktu_masuk, EXCLUDED.waktu_masuk),
      jarak = EXCLUDED.jarak
  WHERE obos.kunjungan_sales.waktu_keluar IS NULL;

  RETURN v_now;
END;
$$;

CREATE OR REPLACE FUNCTION obos.kunjungan_pengirim_scan(
  p_email text,
  p_id_pelanggan text,
  p_keluar boolean,
  p_latitude double precision,
  p_longitude double precision,
  p_waktu timestamptz DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_email text;
  v_id text;
  v_rute_p text;
  v_rute_s text;
  v_lat double precision;
  v_lng double precision;
  v_jarak double precision;
  v_tanggal date;
  v_masuk timestamptz;
  v_keluar timestamptz;
  v_now timestamptz;
BEGIN
  v_email := lower(btrim(COALESCE(p_email, '')));
  IF v_email = '' THEN
    RAISE EXCEPTION 'Email wajib.';
  END IF;
  IF obos.id_absensi_terbuka(v_email) IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk gudang.';
  END IF;
  v_now := obos.waktu_hp(p_waktu);

  SELECT obos.grup_rute(u.rute) INTO v_rute_p
  FROM obos.users u
  WHERE lower(btrim(u.email)) = v_email AND u.peran = 'pengirim';
  IF v_rute_p IS NULL OR v_rute_p = '' THEN
    RAISE EXCEPTION 'Bukan akun pengirim, atau rute kosong.';
  END IF;

  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'Toko kosong.';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'Koordinat HP kosong';
  END IF;

  SELECT pl.latitude, pl.longitude, pl.rute
  INTO v_lat, v_lng, v_rute_s
  FROM obos.pelanggan pl
  JOIN obos.rute_peta rp ON rp.rute_sales = pl.rute
  WHERE pl.id_pelanggan = v_id
    AND rp.rute_pengirim = v_rute_p
    AND COALESCE(pl.aktif, true);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Toko tidak ada di rute Anda';
  END IF;
  IF v_lat IS NULL OR v_lng IS NULL OR (v_lat = 0 AND v_lng = 0) THEN
    RAISE EXCEPTION 'Toko belum punya koordinat GPS.';
  END IF;

  v_jarak := obos.jarak_meter(p_latitude, p_longitude, v_lat, v_lng);
  IF v_jarak > 20 THEN
    RAISE EXCEPTION 'Anda masih % m dari toko. Mendekatlah, lalu scan lagi.',
      round(v_jarak);
  END IF;

  v_tanggal := (v_now AT TIME ZONE 'Asia/Jakarta')::date;
  PERFORM pg_advisory_xact_lock(hashtext(v_rute_p || ':' || v_id || ':' || v_tanggal::text));

  SELECT waktu_masuk, waktu_keluar INTO v_masuk, v_keluar
  FROM obos.kunjungan_pengirim
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
    UPDATE obos.kunjungan_pengirim
    SET waktu_keluar = v_now, jarak = v_jarak
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

  INSERT INTO obos.kunjungan_pengirim (
    id_pelanggan, rute_pengirim, rute_sales, tanggal, waktu_masuk, waktu_keluar, jarak
  ) VALUES (
    v_id, v_rute_p, v_rute_s, v_tanggal, v_now, NULL, v_jarak
  )
  ON CONFLICT (rute_pengirim, id_pelanggan, tanggal) DO UPDATE
  SET waktu_masuk = COALESCE(obos.kunjungan_pengirim.waktu_masuk, EXCLUDED.waktu_masuk),
      jarak = EXCLUDED.jarak
  WHERE obos.kunjungan_pengirim.waktu_keluar IS NULL;

  RETURN v_now;
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
        'jarak_meter', 'waktu_hp',
        'lokasi_gudang_lihat', 'lokasi_gudang_simpan', 'pastikan_di_gudang',
        'pesan_tutup_dulu', 'buku_ada_dikirim', 'kunci_malam_baru',
        'tolak_buku_malam_baru',
        'id_absensi_terbuka', 'status_lantai', 'scan_absensi',
        'absensi_buku', 'buku_siklus',
        'kunjungan_sales_scan', 'kunjungan_pengirim_scan'
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
