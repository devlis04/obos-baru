-- Chip Simpan ikut dibaca lagi meski buku masih terbuka.
-- Sebelumnya cek / tunai admin / kasbon hanya kembali setelah Tutup buku.
-- Jalankan SETELAH 062. Boleh di-Run ulang.

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

  IF coalesce(v_tutup, false) THEN
    SELECT s.isi INTO v_snap
    FROM public.setoran_kartu_simpan s
    WHERE s.id_setoran_buku = v_id;
    IF v_snap IS NOT NULL THEN
      RETURN v_snap || jsonb_build_object(
        'dari_snapshot', true,
        'ada_buku', true,
        'id_setoran_buku', v_id,
        'tanggal', v_tgl,
        'ditutup', true
      );
    END IF;
  END IF;

  v_hidup := public.admin_setoran_kartu_hidup(v_id);
  SELECT s.isi INTO v_snap
  FROM public.setoran_kartu_simpan s
  WHERE s.id_setoran_buku = v_id;
  IF v_snap IS NULL THEN
    RETURN coalesce(v_hidup, '{}'::jsonb);
  END IF;
  RETURN coalesce(v_hidup, '{}'::jsonb) || jsonb_build_object(
    'cek', coalesce(v_snap -> 'cek', '{}'::jsonb),
    'tunai_admin', coalesce(v_snap -> 'tunai_admin', '{}'::jsonb),
    'kasbon', coalesce(v_snap -> 'kasbon', '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_setoran_kartu(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu(bigint)
  TO authenticated, postgres, service_role;
