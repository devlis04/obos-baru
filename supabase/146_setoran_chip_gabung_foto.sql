-- Foto cek / tunai admin / kasbon digabung per kunci, bukan ditimpa utuh.
-- Simpan dengan hijau kosong tidak boleh membuang centang yang sudah ada.
-- Jalankan SETELAH 145. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_setoran_simpan(
  p_id_setoran_buku bigint,
  p_cek jsonb DEFAULT NULL,
  p_tunai jsonb DEFAULT NULL,
  p_kasbon jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_isi jsonb;
  v_email text;
  v_lama jsonb;
  v_cek jsonb;
  v_tunai jsonb;
  v_kasbon jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_id_setoran_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran kosong.';
  END IF;

  SELECT b.id INTO v_id
  FROM public.setoran_buku b
  WHERE b.id = p_id_setoran_buku;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Buku setoran tidak ada.';
  END IF;

  SELECT s.isi INTO v_lama
  FROM public.setoran_kartu_simpan s
  WHERE s.id_setoran_buku = v_id;

  IF p_cek IS NULL OR p_cek = '{}'::jsonb THEN
    v_cek := coalesce(v_lama -> 'cek', '{}'::jsonb);
  ELSE
    v_cek := jsonb_build_object(
      'centang',
        coalesce(v_lama -> 'cek' -> 'centang', '{}'::jsonb)
        || coalesce(p_cek -> 'centang', '{}'::jsonb),
      'hijau',
        coalesce(v_lama -> 'cek' -> 'hijau', '{}'::jsonb)
        || coalesce(p_cek -> 'hijau', '{}'::jsonb)
    );
  END IF;

  IF p_tunai IS NULL OR p_tunai = '{}'::jsonb THEN
    v_tunai := coalesce(v_lama -> 'tunai_admin', '{}'::jsonb);
  ELSE
    v_tunai := coalesce(v_lama -> 'tunai_admin', '{}'::jsonb)
      || p_tunai;
  END IF;

  IF p_kasbon IS NULL OR p_kasbon = '{}'::jsonb THEN
    v_kasbon := coalesce(v_lama -> 'kasbon', '{}'::jsonb);
  ELSE
    v_kasbon := coalesce(v_lama -> 'kasbon', '{}'::jsonb)
      || p_kasbon;
  END IF;

  v_email := nullif(btrim(COALESCE(auth.jwt() ->> 'email', '')), '');
  v_isi := public.admin_setoran_kartu_hidup(v_id)
    || jsonb_build_object(
      'cek', v_cek,
      'tunai_admin', v_tunai,
      'kasbon', v_kasbon,
      'dari_snapshot', true
    );

  INSERT INTO public.setoran_kartu_simpan (
    id_setoran_buku, isi, waktu_simpan, dicatat_oleh
  ) VALUES (
    v_id, v_isi, clock_timestamp(), v_email
  )
  ON CONFLICT (id_setoran_buku) DO UPDATE
  SET
    isi = EXCLUDED.isi,
    waktu_simpan = EXCLUDED.waktu_simpan,
    dicatat_oleh = EXCLUDED.dicatat_oleh;

  RETURN v_isi;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_setoran_simpan(bigint, jsonb, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_simpan(bigint, jsonb, jsonb, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
