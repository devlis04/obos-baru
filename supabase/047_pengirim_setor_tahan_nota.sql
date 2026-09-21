-- Setoran uang ditahan selama masih ada nota dikirim yang belum
-- dikunci (terkirim / batal) dan belum pending.
-- Jalankan SETELAH 046. Boleh diulang.

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
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
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

NOTIFY pgrst, 'reload schema';
