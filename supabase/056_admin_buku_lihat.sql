-- Perbaiki "column reference id is ambiguous" di admin_buku_lihat.
-- Jalankan SETELAH 055. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_buku_lihat(
  p_id bigint DEFAULT NULL,
  OUT id bigint,
  OUT tanggal date,
  OUT ditutup boolean
)
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
BEGIN
  IF p_id IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = p_id;
  ELSE
    v_id := public.setoran_buku_terbuka();
    IF v_id IS NULL THEN
      SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
      FROM public.setoran_buku b
      ORDER BY b.id DESC
      LIMIT 1;
    ELSE
      SELECT b.tanggal, b.ditutup
      INTO v_tgl, v_tutup
      FROM public.setoran_buku b
      WHERE b.id = v_id;
    END IF;
  END IF;

  id := v_id;
  tanggal := v_tgl;
  ditutup := v_tutup;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_buku_lihat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_buku_lihat(bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
