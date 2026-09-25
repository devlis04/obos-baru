-- Pengirim tidak boleh pulang sebelum setor. Setelah pulang, setoran masih bisa
-- disimpan di buku terbuka. Tutup buku menolak rute yang absen tapi belum setor.
-- Jalankan SETELAH 107. SQL Editor → Run. Boleh diulang.

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

CREATE OR REPLACE FUNCTION public.absensi_pengirim_pulang_wajib_setor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_grup text;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.peran, '') IS DISTINCT FROM 'pengirim' THEN
    RETURN NEW;
  END IF;
  IF OLD.waktu_keluar IS NOT NULL OR NEW.waktu_keluar IS NULL THEN
    RETURN NEW;
  END IF;

  v_buku := COALESCE(NEW.id_setoran_buku, OLD.id_setoran_buku);
  v_grup := public.pengirim_grup_rute(NEW.rute);
  IF v_buku IS NULL OR v_grup = '' THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.setoran_pengirim s
    WHERE s.rute_pengirim = v_grup
      AND s.id_setoran_buku = v_buku
  ) THEN
    RAISE EXCEPTION 'Simpan setoran dulu, baru scan pulang.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS absensi_pengirim_pulang_wajib_setor_trg ON public.absensi;
CREATE TRIGGER absensi_pengirim_pulang_wajib_setor_trg
  BEFORE UPDATE OF waktu_keluar ON public.absensi
  FOR EACH ROW
  EXECUTE FUNCTION public.absensi_pengirim_pulang_wajib_setor();

CREATE OR REPLACE FUNCTION public.pengirim_setoran_simpan(
  p_jumlah_transfer integer,
  p_jumlah_tunai integer,
  p_jumlah_bop integer,
  p_kasbon_supir integer,
  p_kasbon_kenek integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_akun text;
  v_nama text;
  v_buku bigint;
  v_tr integer;
  v_tu integer;
  v_bop integer;
  v_ks integer;
  v_kk integer;
  v_sales text[];
  v_belum integer;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Setoran tidak bisa diubah.';
  END IF;
  v_akun := public.pengirim_rute_saya();
  v_rute := public.pengirim_grup_rute(v_akun);
  IF v_rute IS NULL OR btrim(COALESCE(v_akun, '')) = '' THEN
    RAISE EXCEPTION 'Rute pengirim tidak ada.';
  END IF;

  IF public.pengirim_id_absensi_saya() IS NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.absensi a
      WHERE lower(btrim(a.email)) = public.email_jwt()
        AND a.peran = 'pengirim'
        AND a.id_setoran_buku = v_buku
        AND a.waktu_masuk IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'Belum scan masuk.';
    END IF;
  END IF;

  v_sales := public.pengirim_rute_sales();

  SELECT count(*)::integer
  INTO v_belum
  FROM public.transaksi t
  WHERE t.rute = ANY (v_sales)
    AND t.waktu_packed IS NOT NULL
    AND t.status = 'dikirim'
    AND NOT t.pending
    AND COALESCE(t.id_setoran_buku, v_buku) = v_buku;

  IF COALESCE(v_belum, 0) > 0 THEN
    RAISE EXCEPTION
      'Kunci semua nota dulu sebelum setor. Masih ada % nota belum dikunci.',
      v_belum;
  END IF;

  v_tr := GREATEST(COALESCE(p_jumlah_transfer, 0), 0);
  v_tu := GREATEST(COALESCE(p_jumlah_tunai, 0), 0);
  v_bop := GREATEST(COALESCE(p_jumlah_bop, 0), 0);
  v_ks := GREATEST(COALESCE(p_kasbon_supir, 0), 0);
  v_kk := GREATEST(COALESCE(p_kasbon_kenek, 0), 0);
  IF v_bop > 170000 THEN
    RAISE EXCEPTION 'BOP maksimal Rp 170.000.';
  END IF;

  SELECT COALESCE(NULLIF(btrim(u.nama), ''), u.email)
  INTO v_nama
  FROM public.users u
  WHERE lower(btrim(u.email)) = public.email_jwt()
    AND u.peran = 'pengirim'
  LIMIT 1;

  INSERT INTO public.setoran_pengirim (
    rute_pengirim,
    id_setoran_buku,
    jumlah_transfer,
    jumlah_tunai,
    jumlah_bop,
    kasbon_supir,
    kasbon_kenek,
    waktu_setor,
    dicatat_oleh,
    dicatat_rute
  )
  VALUES (
    v_rute,
    v_buku,
    v_tr,
    v_tu,
    v_bop,
    v_ks,
    v_kk,
    clock_timestamp(),
    COALESCE(v_nama, ''),
    v_akun
  )
  ON CONFLICT (rute_pengirim, id_setoran_buku) DO UPDATE SET
    jumlah_transfer = EXCLUDED.jumlah_transfer,
    jumlah_tunai = EXCLUDED.jumlah_tunai,
    jumlah_bop = EXCLUDED.jumlah_bop,
    kasbon_supir = EXCLUDED.kasbon_supir,
    kasbon_kenek = EXCLUDED.kasbon_kenek,
    waktu_setor = clock_timestamp(),
    dicatat_oleh = EXCLUDED.dicatat_oleh,
    dicatat_rute = EXCLUDED.dicatat_rute;

  RETURN true;
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
  v_rute text;
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

  v_rute := public.pengirim_rute_belum_setor(v_id);
  IF v_rute IS NOT NULL THEN
    RAISE EXCEPTION
      'Pengirim % belum simpan setoran. Simpan setoran dulu, lalu tutup buku.',
      v_rute;
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

  PERFORM public.setoran_pending_foto_catat(v_id);

  UPDATE public.setoran_buku
  SET
    ditutup = true,
    waktu_tutup = clock_timestamp()
  WHERE id = v_id
    AND NOT ditutup;

  UPDATE public.transaksi t
  SET id_setoran_buku = NULL
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'diproses'
    AND t.waktu_packed IS NULL;

  RETURN v_id;
END;
$$;

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

REVOKE ALL ON FUNCTION public.pengirim_rute_belum_setor(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_rute_belum_setor(bigint)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.pengirim_setoran_simpan(
  integer, integer, integer, integer, integer
) TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_tutup_setoran_buku()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_buku_siklus()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
