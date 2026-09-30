-- Sabtu buku 26, Senin 28 masih siklus yang sama (Minggu dilewati).
-- Hidup dan kunci malam memakai hari_buku_berikut, bukan kalender +1.
-- Jalankan SETELAH 109. Boleh diulang.

CREATE OR REPLACE FUNCTION public.setoran_buku_untuk_hari(p_tanggal date DEFAULT NULL)
RETURNS TABLE (
  id bigint,
  tanggal date,
  ditutup boolean,
  hidup boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hari date;
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_buka bigint;
  v_today date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;

  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;

  SELECT b.id INTO v_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  IF p_tanggal IS NULL THEN
    IF v_buka IS NULL THEN
      RETURN;
    END IF;
    SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_buka;
    id := v_id;
    tanggal := v_tgl;
    ditutup := COALESCE(v_tutup, false);
    hidup := true;
    RETURN NEXT;
    RETURN;
  END IF;

  v_hari := p_tanggal;

  IF v_buka IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_buka;
    IF v_tgl = v_hari THEN
      id := v_id;
      tanggal := v_tgl;
      ditutup := COALESCE(v_tutup, false);
      hidup := true;
      RETURN NEXT;
      RETURN;
    END IF;
    IF v_hari = v_today AND v_hari <= public.hari_buku_berikut(v_tgl) THEN
      id := v_id;
      tanggal := v_tgl;
      ditutup := COALESCE(v_tutup, false);
      hidup := true;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.tanggal = v_hari
  ORDER BY b.id DESC
  LIMIT 1;
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  id := v_id;
  tanggal := v_tgl;
  ditutup := COALESCE(v_tutup, false);
  hidup := (v_buka IS NOT NULL AND v_id = v_buka);
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_buku_kunci_malam_baru(p_id bigint)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_tgl date;
  v_tutup boolean;
  v_hari date;
BEGIN
  IF p_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id;
  IF NOT FOUND OR COALESCE(v_tutup, false) THEN
    RETURN false;
  END IF;
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  IF v_tgl >= v_hari THEN
    RETURN false;
  END IF;
  IF v_hari > public.hari_buku_berikut(v_tgl) THEN
    RETURN true;
  END IF;
  IF public.setoran_buku_ada_dikirim(p_id) THEN
    RETURN false;
  END IF;
  IF public.pengirim_rute_belum_setor(p_id) IS NOT NULL THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transaksi t
    WHERE t.status = 'diproses'
      AND t.waktu_packed IS NULL
      AND t.waktu_order IS NOT NULL
      AND (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = v_hari
      AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  ) THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transaksi t
    WHERE t.id_setoran_buku = p_id
      AND t.waktu_packed IS NOT NULL
  ) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_buku_untuk_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_untuk_hari(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint)
  TO postgres, service_role;

NOTIFY pgrst, 'reload schema';
