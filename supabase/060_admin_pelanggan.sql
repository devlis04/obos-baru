-- Halaman Pelanggan admin: katalog, simpan, CSV. Toko baru dari salesman.
-- Jalankan SETELAH 059. SQL Editor → Run. Boleh di-Run ulang.

CREATE OR REPLACE FUNCTION public.admin_rute_sales()
RETURNS TABLE (
  rute text,
  nama text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  RETURN QUERY
  SELECT
    btrim(u.rute),
    btrim(u.nama)
  FROM public.users u
  WHERE u.peran = 'sales'
    AND nullif(btrim(u.rute), '') IS NOT NULL
  ORDER BY u.rute;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_pelanggan_semua();
DROP FUNCTION IF EXISTS public.admin_pelanggan_simpan(jsonb);
DROP FUNCTION IF EXISTS public.admin_pelanggan_csv(jsonb);

CREATE FUNCTION public.admin_pelanggan_semua()
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute text,
  visit text,
  urutan integer,
  latitude double precision,
  longitude double precision,
  aktif boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  RETURN QUERY
  SELECT
    p.id_pelanggan,
    p.nama_pelanggan,
    p.rute,
    p.visit,
    p.urutan,
    p.latitude,
    p.longitude,
    COALESCE(p.aktif, true)
  FROM public.pelanggan p
  WHERE btrim(p.id_pelanggan) <> ''
  ORDER BY COALESCE(p.aktif, true) DESC, lower(p.nama_pelanggan), p.id_pelanggan;
END;
$$;

CREATE FUNCTION public.admin_pelanggan_simpan(p_toko jsonb)
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute text,
  visit text,
  urutan integer,
  latitude double precision,
  longitude double precision,
  aktif boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_nama text;
  v_rute text;
  v_visit text;
  v_urutan integer;
  v_lat double precision;
  v_lng double precision;
  v_aktif boolean;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_toko IS NULL OR jsonb_typeof(p_toko) <> 'object' THEN
    RAISE EXCEPTION 'Data pelanggan kosong.';
  END IF;

  v_id := btrim(COALESCE(p_toko->>'id_pelanggan', ''));
  v_nama := upper(btrim(COALESCE(p_toko->>'nama_pelanggan', p_toko->>'nama', '')));
  v_rute := nullif(btrim(COALESCE(p_toko->>'rute', '')), '');
  v_visit := nullif(btrim(COALESCE(p_toko->>'visit', '')), '');
  v_urutan := COALESCE((p_toko->>'urutan')::integer, 0);
  v_lat := NULLIF(btrim(COALESCE(p_toko->>'latitude', '')), '')::double precision;
  v_lng := NULLIF(btrim(COALESCE(p_toko->>'longitude', '')), '')::double precision;
  v_aktif := COALESCE((p_toko->>'aktif')::boolean, true);

  IF v_id = '' THEN
    RAISE EXCEPTION 'Id pelanggan wajib diisi.';
  END IF;
  IF v_nama = '' THEN
    RAISE EXCEPTION 'Nama pelanggan wajib diisi.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.pelanggan p WHERE lower(p.id_pelanggan) = lower(v_id)
  ) THEN
    RAISE EXCEPTION 'Toko baru hanya dari aplikasi salesman.';
  END IF;
  IF v_rute IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.peran = 'sales' AND btrim(u.rute) = v_rute
  ) THEN
    RAISE EXCEPTION 'Rute % bukan rute salesman.', v_rute;
  END IF;
  IF v_visit IS NOT NULL AND v_visit NOT IN (
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
  ) THEN
    RAISE EXCEPTION 'Hari visit harus Senin–Minggu.';
  END IF;

  UPDATE public.pelanggan p
  SET
    nama_pelanggan = v_nama,
    rute = v_rute,
    visit = v_visit,
    urutan = v_urutan,
    latitude = v_lat,
    longitude = v_lng,
    aktif = v_aktif
  WHERE lower(p.id_pelanggan) = lower(v_id)
  RETURNING p.id_pelanggan INTO v_id;

  RETURN QUERY
  SELECT
    p.id_pelanggan,
    p.nama_pelanggan,
    p.rute,
    p.visit,
    p.urutan,
    p.latitude,
    p.longitude,
    COALESCE(p.aktif, true)
  FROM public.pelanggan p
  WHERE p.id_pelanggan = v_id;
END;
$$;

CREATE FUNCTION public.admin_pelanggan_csv(p_baris jsonb)
RETURNS TABLE (
  baris integer,
  id_pelanggan text,
  aksi text,
  ok boolean,
  pesan text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_e jsonb;
  v_i integer := 0;
  v_id text;
  v_nama text;
  v_hapus boolean;
  v_ada boolean;
  v_pakai boolean;
  v_teks text;
  v_urutan integer;
  v_lat double precision;
  v_lng double precision;
  v_aktif boolean;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Data CSV kosong.';
  END IF;
  IF jsonb_array_length(p_baris) > 3000 THEN
    RAISE EXCEPTION 'Maksimal 3000 baris per unggah.';
  END IF;

  FOR v_e IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_i := v_i + 1;
    baris := v_i;
    id_pelanggan := btrim(COALESCE(v_e->>'id_pelanggan', ''));
    aksi := '';
    ok := false;
    pesan := '';
    BEGIN
      v_id := id_pelanggan;
      IF v_id = '' THEN
        RAISE EXCEPTION 'Id pelanggan wajib diisi.';
      END IF;
      v_hapus := COALESCE((v_e->>'hapus')::boolean, false);
      SELECT EXISTS (
        SELECT 1 FROM public.pelanggan p WHERE lower(p.id_pelanggan) = lower(v_id)
      ) INTO v_ada;
      IF NOT v_ada THEN
        RAISE EXCEPTION 'Toko baru hanya dari aplikasi salesman.';
      END IF;

      IF v_hapus THEN
        SELECT EXISTS (
          SELECT 1 FROM public.transaksi t WHERE lower(t.id_pelanggan) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.kunjungan_sales k WHERE lower(k.id_pelanggan) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.kunjungan_pengirim k WHERE lower(k.id_pelanggan) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.retur_toko r WHERE lower(r.id_pelanggan) = lower(v_id)
        ) INTO v_pakai;
        IF v_pakai THEN
          UPDATE public.pelanggan p
          SET aktif = false
          WHERE lower(p.id_pelanggan) = lower(v_id);
          aksi := 'nonaktif';
          ok := true;
          pesan := 'Sudah dipakai nota/kunjungan. Tidak dihapus, dinonaktifkan.';
        ELSE
          DELETE FROM public.pelanggan p WHERE lower(p.id_pelanggan) = lower(v_id);
          aksi := 'hapus';
          ok := true;
          pesan := 'Dihapus.';
        END IF;
      ELSE
        v_nama := upper(btrim(COALESCE(v_e->>'nama_pelanggan', v_e->>'nama', '')));
        IF v_nama <> '' THEN
          UPDATE public.pelanggan p
          SET nama_pelanggan = v_nama
          WHERE lower(p.id_pelanggan) = lower(v_id);
        END IF;
        IF v_e ? 'rute' THEN
          v_teks := btrim(COALESCE(v_e->>'rute', ''));
          IF v_teks IN ('-', '0') THEN
            UPDATE public.pelanggan p SET rute = NULL
            WHERE lower(p.id_pelanggan) = lower(v_id);
          ELSIF v_teks <> '' THEN
            IF NOT EXISTS (
              SELECT 1 FROM public.users u
              WHERE u.peran = 'sales' AND btrim(u.rute) = v_teks
            ) THEN
              RAISE EXCEPTION 'Rute % bukan rute salesman.', v_teks;
            END IF;
            UPDATE public.pelanggan p SET rute = v_teks
            WHERE lower(p.id_pelanggan) = lower(v_id);
          END IF;
        END IF;
        IF v_e ? 'visit' THEN
          v_teks := btrim(COALESCE(v_e->>'visit', ''));
          IF v_teks IN ('-', '0') THEN
            UPDATE public.pelanggan p SET visit = NULL
            WHERE lower(p.id_pelanggan) = lower(v_id);
          ELSIF v_teks <> '' THEN
            IF v_teks NOT IN (
              'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
            ) THEN
              RAISE EXCEPTION 'Hari visit harus Senin–Minggu.';
            END IF;
            UPDATE public.pelanggan p SET visit = v_teks
            WHERE lower(p.id_pelanggan) = lower(v_id);
          END IF;
        END IF;
        IF v_e ? 'urutan' AND nullif(btrim(COALESCE(v_e->>'urutan', '')), '') IS NOT NULL THEN
          v_urutan := (v_e->>'urutan')::integer;
          UPDATE public.pelanggan p SET urutan = v_urutan
          WHERE lower(p.id_pelanggan) = lower(v_id);
        END IF;
        IF v_e ? 'latitude' AND nullif(btrim(COALESCE(v_e->>'latitude', '')), '') IS NOT NULL THEN
          v_lat := replace(btrim(v_e->>'latitude'), ',', '.')::double precision;
          UPDATE public.pelanggan p SET latitude = v_lat
          WHERE lower(p.id_pelanggan) = lower(v_id);
        END IF;
        IF v_e ? 'longitude' AND nullif(btrim(COALESCE(v_e->>'longitude', '')), '') IS NOT NULL THEN
          v_lng := replace(btrim(v_e->>'longitude'), ',', '.')::double precision;
          UPDATE public.pelanggan p SET longitude = v_lng
          WHERE lower(p.id_pelanggan) = lower(v_id);
        END IF;
        IF v_e ? 'aktif' AND nullif(btrim(COALESCE(v_e->>'aktif', '')), '') IS NOT NULL THEN
          v_aktif := (v_e->>'aktif')::boolean;
          UPDATE public.pelanggan p SET aktif = v_aktif
          WHERE lower(p.id_pelanggan) = lower(v_id);
        END IF;
        aksi := 'ubah';
        ok := true;
        pesan := 'Diubah.';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      ok := false;
      pesan := SQLERRM;
    END;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_rute_sales() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pelanggan_semua() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pelanggan_simpan(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pelanggan_csv(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_rute_sales()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_pelanggan_semua()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_pelanggan_simpan(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_pelanggan_csv(jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
