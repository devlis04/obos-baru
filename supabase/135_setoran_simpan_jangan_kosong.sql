-- Jangan timpa chip tunai admin / kasbon / cek dengan JSON kosong saat Simpan.
-- Jalankan SETELAH 063. Boleh diulang.

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

  v_cek := CASE
    WHEN p_cek IS NULL OR p_cek = '{}'::jsonb
      OR coalesce(p_cek -> 'hijau', '{}'::jsonb) = '{}'::jsonb
      THEN coalesce(v_lama -> 'cek', '{}'::jsonb)
    ELSE p_cek
  END;
  v_tunai := CASE
    WHEN p_tunai IS NULL OR p_tunai = '{}'::jsonb
      THEN coalesce(v_lama -> 'tunai_admin', '{}'::jsonb)
    ELSE p_tunai
  END;
  v_kasbon := CASE
    WHEN p_kasbon IS NULL OR p_kasbon = '{}'::jsonb
      THEN coalesce(v_lama -> 'kasbon', '{}'::jsonb)
    ELSE p_kasbon
  END;

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
