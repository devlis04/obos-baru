-- Gudang: dasar strata packing = harga_jual terkunci di transaksi_items,
-- bukan harga_jual_order. Jalankan SETELAH 031. Boleh diulang.

CREATE OR REPLACE FUNCTION public.gudang_nota_item(p_id_transaksi text)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  qty_order integer,
  qty_packed integer,
  qty_actual integer,
  harga_jual_order integer,
  harga_beli_order integer,
  harga_jual_packed integer,
  harga_beli_packed integer,
  harga_jual_actual integer,
  harga_beli_actual integer,
  subtotal_order integer,
  subtotal_packed integer,
  subtotal_actual integer,
  id_grup_kunci text,
  harga_jual_kunci integer,
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
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF btrim(COALESCE(p_id_transaksi, '')) = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;

  RETURN QUERY
  SELECT
    i.id_barang,
    i.nama_barang,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.harga_jual_order,
    i.harga_beli,
    i.harga_jual_packed,
    i.harga_beli,
    i.harga_jual_actual,
    i.harga_beli,
    i.subtotal_jual_order,
    i.subtotal_jual_packed,
    i.subtotal_jual_actual,
    i.id_grup,
    COALESCE(i.harga_jual, 0),
    i.min_strat_1,
    i.jual_strat_1,
    i.min_strat_2,
    i.jual_strat_2,
    i.min_strat_3,
    i.jual_strat_3,
    i.min_strat_4,
    i.jual_strat_4,
    i.min_strat_5,
    i.jual_strat_5
  FROM public.transaksi_items i
  WHERE i.id_transaksi = p_id_transaksi
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_nota_item(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_item(text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
