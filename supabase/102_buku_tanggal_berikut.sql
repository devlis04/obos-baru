-- Tanggal buku berikutnya = hari kerja berikutnya (Sabtu → Senin).
-- Buku terbuka tidak digeser ke "hari ini". Jalankan SETELAH 096. Boleh diulang.

CREATE OR REPLACE FUNCTION public.hari_buku_berikut(p_tanggal date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE EXTRACT(ISODOW FROM p_tanggal)::integer
    WHEN 6 THEN p_tanggal + 2
    WHEN 7 THEN p_tanggal + 1
    ELSE p_tanggal + 1
  END;
$$;

CREATE OR REPLACE FUNCTION public.tanggal_buku_baru()
RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_last date;
  v_today date;
BEGIN
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  SELECT b.tanggal
  INTO v_last
  FROM public.setoran_buku b
  ORDER BY b.tanggal DESC NULLS LAST, b.id DESC
  LIMIT 1;
  IF v_last IS NULL THEN
    IF EXTRACT(ISODOW FROM v_today)::integer = 7 THEN
      RETURN v_today + 1;
    END IF;
    RETURN v_today;
  END IF;
  RETURN public.hari_buku_berikut(v_last);
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_buka_jika_perlu()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
BEGIN
  v_id := public.setoran_buku_terbuka();
  IF v_id IS NOT NULL THEN
    PERFORM public.setoran_pending_foto_pindah(v_id);
    RETURN v_id;
  END IF;

  v_tgl := public.tanggal_buku_baru();

  INSERT INTO public.setoran_buku (tanggal, ditutup)
  VALUES (v_tgl, false)
  RETURNING id INTO v_id;

  INSERT INTO public.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
  )
  SELECT
    v_id,
    v_tgl,
    b.id_barang,
    b.nama_barang,
    GREATEST(COALESCE(b.stok, 0), 0),
    0
  FROM public.barang b
  WHERE btrim(b.id_barang) <> ''
    AND COALESCE(b.aktif, true);

  PERFORM public.setoran_pending_foto_pindah(v_id);
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.hari_buku_berikut(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hari_buku_berikut(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.tanggal_buku_baru() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tanggal_buku_baru()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buka_jika_perlu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buka_jika_perlu()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
