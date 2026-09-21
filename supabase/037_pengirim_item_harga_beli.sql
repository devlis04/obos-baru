-- Harga beli di item nota pengirim, untuk rasio profit tebus/actual.

DROP FUNCTION IF EXISTS public.pengirim_nota_item(text);

CREATE FUNCTION public.pengirim_nota_item(p_id_transaksi text)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  id_grup text,
  harga_jual integer,
  harga_beli integer,
  qty_order integer,
  qty_packed integer,
  qty_actual integer,
  harga_jual_order integer,
  harga_jual_packed integer,
  harga_jual_actual integer,
  subtotal_order integer,
  subtotal_packed integer,
  subtotal_actual integer,
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
  v_id text;
  v_sales text[];
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();
  IF NOT EXISTS (
    SELECT 1 FROM public.transaksi t
    WHERE t.id_transaksi = v_id
      AND t.rute = ANY (v_sales)
  ) THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;

  RETURN QUERY
  SELECT
    i.id_barang,
    i.nama_barang,
    i.id_grup,
    i.harga_jual,
    i.harga_beli,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.harga_jual_order,
    i.harga_jual_packed,
    i.harga_jual_actual,
    i.subtotal_jual_order,
    i.subtotal_jual_packed,
    i.subtotal_jual_actual,
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
  FROM public.v_transaksi_item i
  WHERE i.id_transaksi = v_id
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_nota_item(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_item(text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
