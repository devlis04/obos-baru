-- Plafon BOP harian pengirim = gaji_setelan.bop_mobil / 6 (Senin–Sabtu).
-- Tidak mengubah jumlah_bop yang sudah tersimpan.
-- Setoran baru/ubah: tidak boleh di atas plafon, kecuali angka lama yang
-- sudah tersimpan (kalau plafon diturunkan).
-- Jalankan SETELAH 116 dan 108. Boleh diulang.

CREATE OR REPLACE FUNCTION public.pengirim_bop_maks_hari()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_minggu bigint;
BEGIN
  SELECT g.bop_mobil INTO v_minggu
  FROM public.gaji_setelan g
  WHERE g.id = 1;
  v_minggu := GREATEST(COALESCE(v_minggu, 1020000), 0);
  RETURN LEAST(v_minggu / 6, 2147483647)::integer;
END;
$$;

ALTER TABLE public.setoran_pengirim
  DROP CONSTRAINT IF EXISTS setoran_pengirim_uang_chk;

ALTER TABLE public.setoran_pengirim
  ADD CONSTRAINT setoran_pengirim_uang_chk CHECK (
    jumlah_transfer >= 0
    AND jumlah_tunai >= 0
    AND jumlah_bop >= 0
    AND kasbon_supir >= 0
    AND kasbon_kenek >= 0
  );

DROP FUNCTION IF EXISTS public.pengirim_setoran_lihat();
CREATE FUNCTION public.pengirim_setoran_lihat()
RETURNS TABLE (
  jumlah_transfer integer,
  jumlah_tunai integer,
  jumlah_bop integer,
  kasbon_supir integer,
  kasbon_kenek integer,
  sudah_ada boolean,
  bisa_ubah boolean,
  dicatat_oleh text,
  dicatat_rute text,
  bop_maks integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_buku bigint;
  v_maks integer;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RETURN;
  END IF;
  v_maks := public.pengirim_bop_maks_hari();
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  v_buku := public.setoran_buku_terbuka();
  IF v_rute IS NULL THEN
    RETURN;
  END IF;
  IF v_buku IS NULL THEN
    RETURN QUERY SELECT
      0, 0, 0, 0, 0, false, false, ''::text, ''::text, v_maks;
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    COALESCE(s.jumlah_transfer, 0),
    COALESCE(s.jumlah_tunai, 0),
    COALESCE(s.jumlah_bop, 0),
    COALESCE(s.kasbon_supir, 0),
    COALESCE(s.kasbon_kenek, 0),
    (s.id IS NOT NULL),
    true,
    COALESCE(s.dicatat_oleh, ''),
    COALESCE(s.dicatat_rute, ''),
    v_maks
  FROM (SELECT 1) z
  LEFT JOIN public.setoran_pengirim s
    ON s.rute_pengirim = v_rute
   AND s.id_setoran_buku = v_buku;
END;
$$;

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
  v_maks integer;
  v_lama integer;
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
  v_maks := public.pengirim_bop_maks_hari();

  SELECT s.jumlah_bop
  INTO v_lama
  FROM public.setoran_pengirim s
  WHERE s.rute_pengirim = v_rute
    AND s.id_setoran_buku = v_buku;

  IF v_bop > v_maks AND v_bop IS DISTINCT FROM v_lama THEN
    RAISE EXCEPTION 'BOP maksimal % per hari.', v_maks;
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

REVOKE ALL ON FUNCTION public.pengirim_bop_maks_hari() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_bop_maks_hari()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_setoran_lihat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_setoran_lihat()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_setoran_simpan(
  integer, integer, integer, integer, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_setoran_simpan(
  integer, integer, integer, integer, integer
) TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
