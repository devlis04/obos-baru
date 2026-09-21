-- Kunci tebus nota pengirim. Sisa packed − actual diperlakukan seperti barang masuk.
-- Jalankan SETELAH 029. Boleh diulang.

CREATE OR REPLACE FUNCTION public.pengirim_kunci_nota(
  p_id_transaksi text,
  p_baris jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_status text;
  v_sales text[];
  v_item jsonb;
  v_sku text;
  v_qty integer;
  v_ada_isi boolean;
  rec record;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  v_sales := public.pengirim_rute_sales();
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar tebus wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  DROP TABLE IF EXISTS pengirim_qty_baru;

  SELECT t.status INTO v_status
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_status IS DISTINCT FROM 'dikirim' THEN
    RAISE EXCEPTION 'Nota sudah terkunci atau belum dikirim.';
  END IF;

  CREATE TEMP TABLE pengirim_qty_baru (
    id_barang text PRIMARY KEY,
    qty integer NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_sku := btrim(COALESCE(v_item ->> 'id_barang', ''));
    IF v_sku = '' THEN
      CONTINUE;
    END IF;
    v_qty := COALESCE((v_item ->> 'qty_actual')::integer, 0);
    IF v_qty < 0 THEN
      RAISE EXCEPTION 'Qty tebus tidak boleh negatif (SKU %).', v_sku;
    END IF;
    INSERT INTO pengirim_qty_baru (id_barang, qty)
    VALUES (v_sku, v_qty)
    ON CONFLICT (id_barang) DO UPDATE SET qty = EXCLUDED.qty;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pengirim_qty_baru n
    LEFT JOIN public.transaksi_items i
      ON i.id_transaksi = v_id
     AND i.id_barang = n.id_barang
    WHERE i.id_barang IS NULL
  ) THEN
    RAISE EXCEPTION 'Ada SKU yang tidak ada di nota.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
      AND n.id_barang IS NULL
      AND COALESCE(i.qty_packed, 0) > 0
  ) THEN
    RAISE EXCEPTION 'Semua SKU packed harus diisi qty tebus.';
  END IF;

  FOR rec IN
    SELECT
      i.id_barang,
      COALESCE(n.qty, 0) AS qty,
      COALESCE(i.qty_packed, 0) AS qty_packed,
      COALESCE(i.harga_beli, 0) AS beli,
      COALESCE(i.harga_jual_packed, i.harga_jual_order, 0) AS jual
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
  LOOP
    IF rec.qty > rec.qty_packed THEN
      RAISE EXCEPTION 'Qty tebus melebihi packed (SKU %).', rec.id_barang;
    END IF;

    UPDATE public.transaksi_items
    SET
      qty_actual = rec.qty,
      harga_jual_actual = rec.jual
    WHERE id_transaksi = v_id
      AND id_barang = rec.id_barang;

    IF rec.qty_packed - rec.qty > 0 THEN
      PERFORM public.barang_masuk_geser_stok(
        rec.id_barang,
        rec.qty_packed - rec.qty
      );
    END IF;
  END LOOP;

  UPDATE public.transaksi_items
  SET
    qty_actual = 0,
    harga_jual_actual = COALESCE(harga_jual_packed, harga_jual_order, 0)
  WHERE id_transaksi = v_id
    AND qty_actual IS NULL;

  UPDATE public.transaksi_items i
  SET harga_jual_actual = public.harga_jual_strata(
    COALESCE(i.harga_jual, i.harga_jual_order, i.harga_jual_packed, 0),
    (
      SELECT COALESCE(sum(x.qty_actual), 0)::integer
      FROM public.transaksi_items x
      WHERE x.id_transaksi = i.id_transaksi
        AND COALESCE(NULLIF(btrim(x.id_grup), ''), x.id_barang)
          = COALESCE(NULLIF(btrim(i.id_grup), ''), i.id_barang)
    ),
    i.min_strat_1, i.jual_strat_1,
    i.min_strat_2, i.jual_strat_2,
    i.min_strat_3, i.jual_strat_3,
    i.min_strat_4, i.jual_strat_4,
    i.min_strat_5, i.jual_strat_5
  )
  WHERE i.id_transaksi = v_id
    AND COALESCE(i.qty_actual, 0) > 0;

  SELECT EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
      AND COALESCE(i.qty_actual, 0) > 0
  ) INTO v_ada_isi;

  UPDATE public.transaksi
  SET
    pending = false,
    waktu_actual = clock_timestamp(),
    status = CASE WHEN v_ada_isi THEN 'terkirim' ELSE 'batal' END
  WHERE id_transaksi = v_id
    AND status = 'dikirim';
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_kunci_nota(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kunci_nota(text, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
