-- Kunci malam jangan menahan gudang scan selama siklus buku 24 masih berjalan
-- di kalender 25: masih dikirim, masih ada order hari ini belum packing,
-- atau pengirim belum setor. Jalankan SETELAH 108. Boleh diulang.

CREATE OR REPLACE FUNCTION public.pengirim_rute_belum_setor(p_id_buku bigint)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT x.grup
  FROM (
    SELECT DISTINCT public.pengirim_grup_rute(a.rute) AS grup
    FROM public.absensi a
    WHERE a.peran = 'pengirim'
      AND a.id_setoran_buku = p_id_buku
      AND public.pengirim_grup_rute(a.rute) <> ''
  ) x
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.setoran_pengirim s
    WHERE s.rute_pengirim = x.grup
      AND s.id_setoran_buku = p_id_buku
  )
  ORDER BY x.grup
  LIMIT 1;
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
  IF public.pengirim_rute_belum_setor(p_id) IS NOT NULL THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transaksi t
    WHERE t.status = 'diproses'
      AND t.waktu_packed IS NULL
      AND t.waktu_order IS NOT NULL
      AND (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = v_hari
      AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  ) THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transaksi t
    WHERE t.id_setoran_buku = p_id
      AND t.waktu_packed IS NOT NULL
  ) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_rute_belum_setor(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_rute_belum_setor(bigint)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint)
  TO postgres, service_role;

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
  v_rute text;
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

  v_rute := public.pengirim_rute_belum_setor(v_id);
  v_kunci := public.setoran_buku_kunci_malam_baru(v_id);
  v_siap := v_dikirim = 0
    AND v_dalam = 0
    AND v_fisik > 0
    AND v_minus = 0
    AND v_rute IS NULL;

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
  ELSIF v_rute IS NOT NULL THEN
    v_pesan := format(
      'Pengirim %s belum simpan setoran. Simpan setoran dulu, lalu tutup buku.',
      v_rute
    );
  ELSIF v_dalam > 0 THEN
    v_pesan := 'Masih ada absensi yang belum pulang. Scan pulang dulu, lalu tutup buku.';
  ELSIF COALESCE(v_fisik, 0) <= 0 THEN
    v_pesan := 'Opname fisik belum diisi. Gudang isi fisik dulu, lalu tutup buku.';
  ELSIF v_minus > 0 THEN
    v_pesan := 'Masih ada selisih kurang belum diputuskan. Kasbon atau potong margin dulu.';
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

GRANT EXECUTE ON FUNCTION public.admin_buku_siklus()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
