-- Buku yang sudah ditutup jangan menampilkan foto Simpan yang kedaluwarsa.
-- Simpan di tengah hari mengunci rute. Setoran yang masuk setelah itu
-- (contoh SBGP03 buku 21) tetap "Belum setor" meski baris setoran_pengirim ada.
-- Angka rute selalu dari kartu hidup. Centang cek / tunai admin / kasbon
-- tetap dari foto, lalu digabung ulang tiap kali dicentang (lihat 146).
-- Jalankan SETELAH 136. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_setoran_kartu(
  p_id_setoran_buku bigint DEFAULT NULL
)
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
  v_hidup jsonb;
  v_snap jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT x.id, x.tanggal, x.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'dari_snapshot', false,
      'rute', '[]'::jsonb
    );
  END IF;

  v_hidup := public.admin_setoran_kartu_hidup(v_id);
  SELECT s.isi INTO v_snap
  FROM public.setoran_kartu_simpan s
  WHERE s.id_setoran_buku = v_id;

  IF v_snap IS NULL THEN
    RETURN coalesce(v_hidup, '{}'::jsonb) || jsonb_build_object(
      'ada_buku', true,
      'id_setoran_buku', v_id,
      'tanggal', v_tgl,
      'ditutup', coalesce(v_tutup, false),
      'dari_snapshot', false
    );
  END IF;

  RETURN coalesce(v_hidup, '{}'::jsonb) || jsonb_build_object(
    'cek', coalesce(v_snap -> 'cek', '{}'::jsonb),
    'tunai_admin', coalesce(v_snap -> 'tunai_admin', '{}'::jsonb),
    'kasbon', coalesce(v_snap -> 'kasbon', '{}'::jsonb),
    'dari_snapshot', true,
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', coalesce(v_tutup, false)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_kartu_segar_saat_tutup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hidup jsonb;
  v_lama jsonb;
  v_email text;
BEGIN
  IF NOT (NEW.ditutup AND NOT coalesce(OLD.ditutup, false)) THEN
    RETURN NEW;
  END IF;

  v_hidup := public.admin_setoran_kartu_hidup(NEW.id);
  SELECT s.isi INTO v_lama
  FROM public.setoran_kartu_simpan s
  WHERE s.id_setoran_buku = NEW.id;

  v_email := nullif(btrim(coalesce(auth.jwt() ->> 'email', '')), '');
  INSERT INTO public.setoran_kartu_simpan (
    id_setoran_buku, isi, waktu_simpan, dicatat_oleh
  ) VALUES (
    NEW.id,
    coalesce(v_hidup, '{}'::jsonb) || jsonb_build_object(
      'cek', coalesce(v_lama -> 'cek', '{}'::jsonb),
      'tunai_admin', coalesce(v_lama -> 'tunai_admin', '{}'::jsonb),
      'kasbon', coalesce(v_lama -> 'kasbon', '{}'::jsonb),
      'dari_snapshot', true,
      'ada_buku', true,
      'id_setoran_buku', NEW.id,
      'tanggal', NEW.tanggal,
      'ditutup', true
    ),
    clock_timestamp(),
    v_email
  )
  ON CONFLICT (id_setoran_buku) DO UPDATE
  SET
    isi = EXCLUDED.isi,
    waktu_simpan = EXCLUDED.waktu_simpan,
    dicatat_oleh = coalesce(
      EXCLUDED.dicatat_oleh,
      public.setoran_kartu_simpan.dicatat_oleh
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS setoran_kartu_segar_saat_tutup_trg ON public.setoran_buku;
CREATE TRIGGER setoran_kartu_segar_saat_tutup_trg
  AFTER UPDATE OF ditutup ON public.setoran_buku
  FOR EACH ROW
  EXECUTE FUNCTION public.setoran_kartu_segar_saat_tutup();

REVOKE ALL ON FUNCTION public.admin_setoran_kartu(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_kartu_segar_saat_tutup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_kartu_segar_saat_tutup()
  TO postgres, service_role;

NOTIFY pgrst, 'reload schema';
