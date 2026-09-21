-- Nama/rute yang mencatat setoran, untuk tampilan halaman setoran.
-- Jalankan SETELAH 044. Boleh diulang.

DROP FUNCTION IF EXISTS public.pengirim_setoran_lihat();

CREATE OR REPLACE FUNCTION public.pengirim_setoran_lihat()
RETURNS TABLE (
  jumlah_transfer integer,
  jumlah_tunai integer,
  jumlah_bop integer,
  kasbon_supir integer,
  kasbon_kenek integer,
  sudah_ada boolean,
  bisa_ubah boolean,
  dicatat_oleh text,
  dicatat_rute text
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
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RETURN;
  END IF;
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  v_buku := public.setoran_buku_terbuka();
  IF v_rute IS NULL THEN
    RETURN;
  END IF;
  IF v_buku IS NULL THEN
    RETURN QUERY SELECT 0, 0, 0, 0, 0, false, false, ''::text, ''::text;
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
    COALESCE(s.dicatat_rute, '')
  FROM (SELECT 1) z
  LEFT JOIN public.setoran_pengirim s
    ON s.rute_pengirim = v_rute
   AND s.id_setoran_buku = v_buku;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_setoran_lihat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_setoran_lihat()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
