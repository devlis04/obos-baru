-- Barang masuk pemasok utama menaikkan modal+jual, tapi strata lama tertinggal.
-- Sales memakai jual_strat_* (bukan tampilan form admin).
-- Jalankan SETELAH 106. SQL Editor → Run. Boleh diulang.
-- Nota yang sudah order tidak diubah.

CREATE OR REPLACE FUNCTION public.barang_masuk_terapkan_harga(
  p_id_supplier integer,
  p_id_barang text,
  p_harga numeric
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_kat integer;
  v_utama integer;
  v_lama integer;
  v_baru integer;
  v_jual integer;
BEGIN
  v_kat := (round(GREATEST(COALESCE(p_harga, 0), 0) / 5) * 5)::integer;
  IF v_kat < 1 THEN
    RETURN 0;
  END IF;
  INSERT INTO public.supplier_harga (id_supplier, id_barang, harga_beli)
  VALUES (p_id_supplier, p_id_barang, v_kat)
  ON CONFLICT (id_supplier, id_barang) DO UPDATE SET
    harga_beli = EXCLUDED.harga_beli;

  SELECT b.id_supplier_utama, b.harga_beli, b.harga_jual
  INTO v_utama, v_lama, v_jual
  FROM public.barang b
  WHERE b.id_barang = p_id_barang;
  IF NOT FOUND THEN
    RETURN v_kat;
  END IF;

  IF v_utama IS NULL THEN
    UPDATE public.barang
    SET id_supplier_utama = p_id_supplier
    WHERE id_barang = p_id_barang;
    v_utama := p_id_supplier;
  END IF;

  IF v_utama IS DISTINCT FROM p_id_supplier THEN
    RETURN v_kat;
  END IF;

  v_baru := GREATEST(COALESCE(v_lama, 0), v_kat);
  IF v_baru IS DISTINCT FROM COALESCE(v_lama, 0) THEN
    PERFORM public.barang_ikut_modal(p_id_barang, v_baru);
  ELSIF COALESCE(v_jual, 0) < 1 THEN
    UPDATE public.barang
    SET harga_jual = public.jual_dari_modal(v_baru)
    WHERE id_barang = p_id_barang;
  END IF;
  RETURN v_kat;
END;
$$;

UPDATE public.barang b
SET
  jual_strat_1 = CASE
    WHEN COALESCE(b.min_strat_1, 0) > 0
      THEN GREATEST(b.harga_jual - COALESCE(b.pengurang_strata, 0) * 1, 0)
    ELSE 0
  END,
  jual_strat_2 = CASE
    WHEN COALESCE(b.min_strat_2, 0) > 0
      THEN GREATEST(b.harga_jual - COALESCE(b.pengurang_strata, 0) * 2, 0)
    ELSE 0
  END,
  jual_strat_3 = CASE
    WHEN COALESCE(b.min_strat_3, 0) > 0
      THEN GREATEST(b.harga_jual - COALESCE(b.pengurang_strata, 0) * 3, 0)
    ELSE 0
  END,
  jual_strat_4 = CASE
    WHEN COALESCE(b.min_strat_4, 0) > 0
      THEN GREATEST(b.harga_jual - COALESCE(b.pengurang_strata, 0) * 4, 0)
    ELSE 0
  END,
  jual_strat_5 = CASE
    WHEN COALESCE(b.min_strat_5, 0) > 0
      THEN GREATEST(b.harga_jual - COALESCE(b.pengurang_strata, 0) * 5, 0)
    ELSE 0
  END
WHERE COALESCE(b.pengurang_strata, 0) > 0
  AND (
    (COALESCE(b.min_strat_1, 0) > 0
      AND b.jual_strat_1 IS DISTINCT FROM
        GREATEST(b.harga_jual - b.pengurang_strata * 1, 0))
    OR (COALESCE(b.min_strat_2, 0) > 0
      AND b.jual_strat_2 IS DISTINCT FROM
        GREATEST(b.harga_jual - b.pengurang_strata * 2, 0))
    OR (COALESCE(b.min_strat_3, 0) > 0
      AND b.jual_strat_3 IS DISTINCT FROM
        GREATEST(b.harga_jual - b.pengurang_strata * 3, 0))
    OR (COALESCE(b.min_strat_4, 0) > 0
      AND b.jual_strat_4 IS DISTINCT FROM
        GREATEST(b.harga_jual - b.pengurang_strata * 4, 0))
    OR (COALESCE(b.min_strat_5, 0) > 0
      AND b.jual_strat_5 IS DISTINCT FROM
        GREATEST(b.harga_jual - b.pengurang_strata * 5, 0))
  );

REVOKE ALL ON FUNCTION public.barang_masuk_terapkan_harga(integer, text, numeric)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.barang_masuk_terapkan_harga(integer, text, numeric)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
