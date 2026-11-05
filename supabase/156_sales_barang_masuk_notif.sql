-- Notif salesman: barang masuk buku terbuka saja (bukan packing).
-- Jalankan SETELAH 155. Boleh diulang.

CREATE OR REPLACE FUNCTION public.sales_barang_masuk_buku()
RETURNS TABLE (
  id_setoran_buku bigint,
  id_barang text,
  nama_barang text,
  qty numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RETURN;
  END IF;
  SELECT b.tanggal INTO v_tgl
  FROM public.setoran_buku b
  WHERE b.id = v_buku;

  RETURN QUERY
  SELECT
    v_buku,
    m.id_barang,
    max(b.nama_barang),
    sum(m.qty)::numeric
  FROM public.barang_masuk m
  JOIN public.barang b ON b.id_barang = m.id_barang
  WHERE public.barang_masuk_di_kartu(
      v_buku, v_tgl, false, m.id_setoran_buku, m.tanggal
    )
    AND m.qty > 0
  GROUP BY m.id_barang
  HAVING sum(m.qty) > 0
  ORDER BY lower(max(b.nama_barang)), m.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.sales_barang_masuk_buku() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_barang_masuk_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
