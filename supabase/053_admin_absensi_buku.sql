-- Kartu absensi admin: pengirim + gudang.
-- Belum masuk = abu, sudah masuk belum keluar = oranye, sudah keluar = hijau.
-- Jalankan SETELAH 052. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_absensi_buku()
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
  v_baris jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    SELECT b.id, b.tanggal INTO v_id, v_tgl
    FROM public.setoran_buku b
    ORDER BY b.id DESC
    LIMIT 1;
  ELSE
    SELECT b.tanggal INTO v_tgl
    FROM public.setoran_buku b
    WHERE b.id = v_id;
  END IF;

  IF v_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'nama_kunci', u.email,
        'nama', u.nama,
        'urutan', CASE WHEN u.peran = 'pengirim' THEN 0 ELSE 1 END,
        'peran', u.peran,
        'di_dalam', EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
        ),
        'pulang', EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NOT NULL
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
        )
      )
      ORDER BY
        CASE WHEN u.peran = 'pengirim' THEN 0 ELSE 1 END,
        u.rute,
        u.nama
    ),
    '[]'::jsonb
  )
  INTO v_baris
  FROM public.users u
  WHERE u.peran IN ('pengirim', 'gudang');

  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_absensi_buku() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_absensi_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
