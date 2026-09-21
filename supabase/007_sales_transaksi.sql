-- RLS + simpan/ubah/batal nota salesman. Jalankan SETELAH 006_transaksi.sql
-- Harga jual order dihitung di server dari qty per id_grup + strata barang yang dikunci ke baris.

CREATE OR REPLACE FUNCTION public.harga_jual_strata(
  p_dasar integer,
  p_qty integer,
  p_min1 integer,
  p_jual1 integer,
  p_min2 integer,
  p_jual2 integer,
  p_min3 integer,
  p_jual3 integer,
  p_min4 integer,
  p_jual4 integer,
  p_min5 integer,
  p_jual5 integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    (
      SELECT s.jual
      FROM (
        VALUES
          (p_min5, p_jual5),
          (p_min4, p_jual4),
          (p_min3, p_jual3),
          (p_min2, p_jual2),
          (p_min1, p_jual1)
      ) AS s(min, jual)
      WHERE COALESCE(p_qty, 0) >= s.min
        AND s.min > 0
        AND s.jual > 0
      ORDER BY s.min DESC
      LIMIT 1
    ),
    GREATEST(COALESCE(p_dasar, 0), 0)
  );
$$;

GRANT SELECT ON TABLE public.barang TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.barang FROM authenticated;
GRANT SELECT ON TABLE public.transaksi TO authenticated;
GRANT SELECT ON TABLE public.transaksi_items TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.transaksi FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.transaksi_items FROM authenticated;

ALTER TABLE public.barang ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barang FORCE ROW LEVEL SECURITY;
ALTER TABLE public.transaksi ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaksi FORCE ROW LEVEL SECURITY;
ALTER TABLE public.transaksi_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaksi_items FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS barang_select_sales ON public.barang;
CREATE POLICY barang_select_sales
  ON public.barang
  FOR SELECT
  TO authenticated
  USING (public.rute_sales_saya() IS NOT NULL);

DROP POLICY IF EXISTS transaksi_select_sales ON public.transaksi;
CREATE POLICY transaksi_select_sales
  ON public.transaksi
  FOR SELECT
  TO authenticated
  USING (
    public.rute_sales_saya() IS NOT NULL
    AND rute = public.rute_sales_saya()
  );

DROP POLICY IF EXISTS transaksi_items_select_sales ON public.transaksi_items;
CREATE POLICY transaksi_items_select_sales
  ON public.transaksi_items
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.transaksi t
      WHERE t.id_transaksi = transaksi_items.id_transaksi
        AND t.rute = public.rute_sales_saya()
    )
  );

-- Isi baris nota: kunci harga beli, harga jual katalog, dan strata dari barang.
-- harga_jual_order = hasil strata dari qty total per id_grup.
CREATE OR REPLACE FUNCTION public.sales_isi_item_order(p_id text, p_items jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  n integer;
BEGIN
  INSERT INTO public.transaksi_items (
    id_transaksi,
    id_barang,
    id_grup,
    nama_barang,
    harga_beli,
    harga_jual,
    qty_order,
    harga_jual_order,
    min_strat_1,
    jual_strat_1,
    min_strat_2,
    jual_strat_2,
    min_strat_3,
    jual_strat_3,
    min_strat_4,
    jual_strat_4,
    min_strat_5,
    jual_strat_5
  )
  WITH pesan AS (
    SELECT
      btrim(e->>'id_barang') AS id_barang,
      SUM((e->>'qty')::integer) AS qty
    FROM jsonb_array_elements(p_items) AS e
    WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
      AND COALESCE((e->>'qty')::integer, 0) > 0
    GROUP BY 1
  ),
  baris AS (
    SELECT
      p.id_barang,
      p.qty,
      NULLIF(btrim(COALESCE(b.id_grup, '')), '') AS id_grup,
      b.nama_barang,
      COALESCE(b.harga_beli, 0) AS harga_beli,
      COALESCE(b.harga_jual, 0) AS harga_jual,
      COALESCE(b.min_strat_1, 0) AS min_strat_1,
      COALESCE(b.jual_strat_1, 0) AS jual_strat_1,
      COALESCE(b.min_strat_2, 0) AS min_strat_2,
      COALESCE(b.jual_strat_2, 0) AS jual_strat_2,
      COALESCE(b.min_strat_3, 0) AS min_strat_3,
      COALESCE(b.jual_strat_3, 0) AS jual_strat_3,
      COALESCE(b.min_strat_4, 0) AS min_strat_4,
      COALESCE(b.jual_strat_4, 0) AS jual_strat_4,
      COALESCE(b.min_strat_5, 0) AS min_strat_5,
      COALESCE(b.jual_strat_5, 0) AS jual_strat_5,
      COALESCE(NULLIF(btrim(COALESCE(b.id_grup, '')), ''), b.id_barang) AS kunci_grup
    FROM pesan p
    JOIN public.barang b ON b.id_barang = p.id_barang
  ),
  grup AS (
    SELECT kunci_grup, SUM(qty)::integer AS qty_grup
    FROM baris
    GROUP BY kunci_grup
  )
  SELECT
    p_id,
    baris.id_barang,
    baris.id_grup,
    baris.nama_barang,
    baris.harga_beli,
    baris.harga_jual,
    baris.qty,
    public.harga_jual_strata(
      baris.harga_jual,
      grup.qty_grup,
      baris.min_strat_1,
      baris.jual_strat_1,
      baris.min_strat_2,
      baris.jual_strat_2,
      baris.min_strat_3,
      baris.jual_strat_3,
      baris.min_strat_4,
      baris.jual_strat_4,
      baris.min_strat_5,
      baris.jual_strat_5
    ),
    baris.min_strat_1,
    baris.jual_strat_1,
    baris.min_strat_2,
    baris.jual_strat_2,
    baris.min_strat_3,
    baris.jual_strat_3,
    baris.min_strat_4,
    baris.jual_strat_4,
    baris.min_strat_5,
    baris.jual_strat_5
  FROM baris
  JOIN grup ON grup.kunci_grup = baris.kunci_grup;

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN COALESCE(n, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.sales_simpan_transaksi(
  p_id_transaksi text,
  p_id_pelanggan text,
  p_nama_pelanggan text,
  p_items jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_pelanggan text;
  v_jumlah integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF NOT public.sales_sedang_login() THEN
    RETURN false;
  END IF;

  v_rute := public.rute_sales_saya();
  IF v_rute IS NULL THEN
    RETURN false;
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  v_pelanggan := btrim(COALESCE(p_id_pelanggan, ''));
  IF v_id = '' OR v_pelanggan = '' THEN
    RETURN false;
  END IF;
  IF left(v_pelanggan, 3) = 'TMP' THEN
    RETURN false;
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pelanggan
    WHERE id_pelanggan = v_pelanggan
      AND rute = v_rute
  ) THEN
    RETURN false;
  END IF;

  SELECT COUNT(*) INTO v_jumlah
  FROM jsonb_array_elements(p_items) AS e
  WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
    AND COALESCE((e->>'qty')::integer, 0) > 0;

  IF COALESCE(v_jumlah, 0) <= 0 THEN
    RETURN false;
  END IF;

  IF EXISTS (SELECT 1 FROM public.transaksi WHERE id_transaksi = v_id) THEN
    RETURN true;
  END IF;

  INSERT INTO public.transaksi (
    id_transaksi,
    id_pelanggan,
    nama_pelanggan,
    rute,
    status,
    waktu_order,
    pending
  ) VALUES (
    v_id,
    v_pelanggan,
    upper(btrim(COALESCE(p_nama_pelanggan, ''))),
    v_rute,
    'diproses',
    timezone('utc', now()),
    false
  );

  v_jumlah := public.sales_isi_item_order(v_id, p_items);
  IF v_jumlah <= 0 THEN
    DELETE FROM public.transaksi WHERE id_transaksi = v_id;
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.sales_ubah_transaksi(
  p_id_transaksi text,
  p_items jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_jumlah integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF NOT public.sales_sedang_login() THEN
    RETURN false;
  END IF;

  v_rute := public.rute_sales_saya();
  IF v_rute IS NULL THEN
    RETURN false;
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RETURN false;
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.transaksi
    WHERE id_transaksi = v_id
      AND rute = v_rute
      AND status = 'diproses'
      AND waktu_packed IS NULL
  ) THEN
    RETURN false;
  END IF;

  SELECT COUNT(*) INTO v_jumlah
  FROM jsonb_array_elements(p_items) AS e
  JOIN public.barang b
    ON b.id_barang = btrim(e->>'id_barang')
  WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
    AND COALESCE((e->>'qty')::integer, 0) > 0;

  IF COALESCE(v_jumlah, 0) <= 0 THEN
    RETURN false;
  END IF;

  DELETE FROM public.transaksi_items WHERE id_transaksi = v_id;

  v_jumlah := public.sales_isi_item_order(v_id, p_items);
  IF v_jumlah <= 0 THEN
    RAISE EXCEPTION 'item nota kosong';
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.sales_batal_transaksi(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_id text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF NOT public.sales_sedang_login() THEN
    RETURN false;
  END IF;

  v_rute := public.rute_sales_saya();
  IF v_rute IS NULL THEN
    RETURN false;
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RETURN false;
  END IF;

  UPDATE public.transaksi
  SET status = 'batal',
      pending = false
  WHERE id_transaksi = v_id
    AND rute = v_rute
    AND status = 'diproses'
    AND waktu_packed IS NULL;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.harga_jual_strata(
  integer, integer, integer, integer, integer, integer,
  integer, integer, integer, integer, integer, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.harga_jual_strata(
  integer, integer, integer, integer, integer, integer,
  integer, integer, integer, integer, integer, integer
) TO authenticated;

REVOKE ALL ON FUNCTION public.sales_isi_item_order(text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sales_isi_item_order(text, jsonb) FROM authenticated;

REVOKE ALL ON FUNCTION public.sales_simpan_transaksi(text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_simpan_transaksi(text, text, text, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.sales_ubah_transaksi(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_ubah_transaksi(text, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.sales_batal_transaksi(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_batal_transaksi(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
