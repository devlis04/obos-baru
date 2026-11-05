-- Chip sisa stok salesman = stok_hitung buku terbuka (sama gudang), bukan barang.stok tertahan.
-- Jalankan SETELAH 016. Boleh diulang.

CREATE OR REPLACE FUNCTION public.sales_barang_katalog()
RETURNS TABLE (
  id_barang text,
  id_grup text,
  nama_barang text,
  kategori text,
  stok numeric,
  harga_beli integer,
  harga_jual integer,
  min_strat_1 integer,
  jual_strat_1 integer,
  min_strat_2 integer,
  jual_strat_2 integer,
  min_strat_3 integer,
  jual_strat_3 integer,
  min_strat_4 integer,
  jual_strat_4 integer,
  min_strat_5 integer,
  jual_strat_5 integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    COALESCE(so.stok_hitung, b.stok),
    b.harga_beli,
    b.harga_jual,
    b.min_strat_1,
    b.jual_strat_1,
    b.min_strat_2,
    b.jual_strat_2,
    b.min_strat_3,
    b.jual_strat_3,
    b.min_strat_4,
    b.jual_strat_4,
    b.min_strat_5,
    b.jual_strat_5
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> ''
    AND b.aktif
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 8000;
END;
$$;

REVOKE ALL ON FUNCTION public.sales_barang_katalog() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_barang_katalog()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
