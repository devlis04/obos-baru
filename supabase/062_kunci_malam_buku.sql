-- Satu buku = satu siklus (malam packing + pagi kirim), bukan satu tanggal kalender.
-- Gudang scan masuk pagi hari berikutnya masih boleh selama ada nota dikirim.
-- Malam baru ditolak jika tanggal buku < hari ini dan siklus sudah bersih (tidak ada dikirim),
-- atau sudah lewat lebih dari satu hari dari tanggal buku.
-- Tutup tetap manual admin. Jalankan SETELAH 061. Boleh di-Run ulang.

CREATE OR REPLACE FUNCTION public.setoran_pesan_tutup_dulu(p_tanggal date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT format(
    'Minta admin tutup buku dulu. Buku %s masih terbuka; malam baru tidak bisa memakai buku itu.',
    to_char(p_tanggal, 'FMDD-MM-YYYY')
  );
$$;

CREATE OR REPLACE FUNCTION public.setoran_buku_ada_dikirim(p_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.transaksi t
    WHERE t.id_setoran_buku = p_id
      AND t.status = 'dikirim'
      AND NOT COALESCE(t.pending, false)
  );
$$;

CREATE OR REPLACE FUNCTION public.setoran_buku_kunci_malam_baru(p_id bigint)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
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
  FROM public.setoran_buku b
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
  IF public.setoran_buku_ada_dikirim(p_id) THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.transaksi_tolak_buku_malam_baru()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
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
  FROM public.setoran_buku b
  WHERE b.id = NEW.id_setoran_buku;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  IF COALESCE(v_tutup, false) THEN
    RAISE EXCEPTION 'Nota tidak bisa masuk buku yang sudah ditutup.';
  END IF;
  IF public.setoran_buku_kunci_malam_baru(NEW.id_setoran_buku) THEN
    RAISE EXCEPTION '%', public.setoran_pesan_tutup_dulu(v_tgl);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS transaksi_tolak_buku_malam_baru ON public.transaksi;
CREATE TRIGGER transaksi_tolak_buku_malam_baru
  BEFORE INSERT OR UPDATE OF id_setoran_buku ON public.transaksi
  FOR EACH ROW
  EXECUTE PROCEDURE public.transaksi_tolak_buku_malam_baru();

CREATE OR REPLACE FUNCTION public.admin_buku_siklus()
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
  v_dikirim integer := 0;
  v_dalam integer := 0;
  v_fisik integer := 0;
  v_minus integer := 0;
  v_kunci boolean := false;
  v_siap boolean := false;
  v_pesan text := '';
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_id := public.setoran_buku_terbuka();
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
  FROM public.setoran_buku b
  WHERE b.id = v_id;

  SELECT count(*)::integer INTO v_dikirim
  FROM public.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);

  SELECT count(*)::integer INTO v_dalam
  FROM public.absensi a
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
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id;

  v_kunci := public.setoran_buku_kunci_malam_baru(v_id);
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
    v_pesan := public.setoran_pesan_tutup_dulu(v_tgl);
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
  v_buku bigint;
  v_tgl_buku date;
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

  PERFORM pg_advisory_xact_lock(88221019);
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

    SELECT a.tanggal INTO v_tanggal FROM public.absensi a WHERE a.id = v_id;
    PERFORM public.serahkan_stok_jika_gudang_kosong();

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

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NOT NULL THEN
    SELECT b.tanggal INTO v_tgl_buku
    FROM public.setoran_buku b
    WHERE b.id = v_buku;
    IF public.setoran_buku_kunci_malam_baru(v_buku) THEN
      RAISE EXCEPTION '%', public.setoran_pesan_tutup_dulu(v_tgl_buku);
    END IF;
  END IF;

  v_buku := public.setoran_buka_jika_perlu();
  SELECT b.tanggal INTO v_tanggal
  FROM public.setoran_buku b
  WHERE b.id = v_buku;

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
  v_tgl_buku date;
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

  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Belum ada buku setoran. Gudang scan masuk dulu.';
  END IF;

  SELECT b.tanggal INTO v_tgl_buku
  FROM public.setoran_buku b
  WHERE b.id = v_buku;
  IF public.setoran_buku_kunci_malam_baru(v_buku) THEN
    RAISE EXCEPTION '%', public.setoran_pesan_tutup_dulu(v_tgl_buku);
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

CREATE OR REPLACE FUNCTION public.admin_tutup_setoran_buku()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_sku text;
  v_n integer;
  v_fisik integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menutup buku.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);
  IF v_n > 0 THEN
    RAISE EXCEPTION
      'Masih ada % nota dikirim. Pengirim selesaikan dulu, lalu tutup buku.',
      v_n;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'pengirim')
    AND a.id_setoran_buku = v_id;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada absensi yang belum pulang. Scan pulang dulu, lalu tutup buku.';
  END IF;

  SELECT count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer
  INTO v_fisik
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id;
  IF COALESCE(v_fisik, 0) <= 0 THEN
    RAISE EXCEPTION 'Opname fisik belum diisi. Gudang isi fisik dulu, lalu tutup buku.';
  END IF;

  SELECT so.id_barang
  INTO v_sku
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) < 0
    AND so.putusan IS DISTINCT FROM 'kasbon'
    AND so.putusan IS DISTINCT FROM 'beban'
  ORDER BY lower(so.nama_barang)
  LIMIT 1;
  IF v_sku IS NOT NULL THEN
    RAISE EXCEPTION
      'Masih ada selisih kurang belum diputuskan (SKU %). Kasbon atau potong margin dulu.',
      v_sku;
  END IF;

  UPDATE public.stok_opname so
  SET
    putusan = 'margin_plus',
    nilai_putusan = round(so.selisih * GREATEST(COALESCE(b.harga_beli, 0), 0))::integer,
    harga_beli_putusan = GREATEST(COALESCE(b.harga_beli, 0), 0)::integer,
    qty_selisih_putusan = so.selisih,
    kasbon_email = NULL,
    kasbon_nama = NULL,
    waktu_putusan = clock_timestamp()
  FROM public.barang b
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) > 0;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  UPDATE public.setoran_buku
  SET
    ditutup = true,
    waktu_tutup = clock_timestamp()
  WHERE id = v_id
    AND NOT ditutup;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_pesan_tutup_dulu(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.setoran_buku_ada_dikirim(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transaksi_tolak_buku_malam_baru() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_buku_siklus() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.setoran_pesan_tutup_dulu(date)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.setoran_buku_ada_dikirim(bigint)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_buku_siklus()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.gudang_scan_absensi(boolean, double precision, double precision, timestamptz)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.pengirim_scan_absensi(boolean, double precision, double precision, timestamptz)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_tutup_setoran_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
