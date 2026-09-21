-- Packing rute gudang. Jalankan SETELAH 011. Boleh diulang.
-- Stok dipotong dari public.barang (buku opname menyusul).
-- SKU tambahan packing: qty_order = 0.

ALTER TABLE public.transaksi_items
  DROP CONSTRAINT IF EXISTS transaksi_items_order_chk;
ALTER TABLE public.transaksi_items
  ADD CONSTRAINT transaksi_items_order_chk CHECK (
    qty_order >= 0 AND harga_jual_order >= 0
  );

CREATE OR REPLACE FUNCTION public.gudang_kartu_rute(p_tanggal date)
RETURNS TABLE (
  rute text,
  nama_sales text,
  jumlah_nota integer,
  sudah_siap integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM public.transaksi t
    WHERE (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
      AND t.status IS DISTINCT FROM 'batal'
  ),
  hitung AS (
    SELECT
      n.rute,
      count(DISTINCT n.id_transaksi)::integer AS jumlah_nota,
      count(DISTINCT n.id_transaksi) FILTER (
        WHERE n.status IN ('dikirim', 'terkirim') OR n.waktu_packed IS NOT NULL
      )::integer AS sudah_siap,
      coalesce(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS omset_packed,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint AS laba_order,
      coalesce(sum(
        CASE
          WHEN i.qty_packed IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
        END
      ), 0)::bigint AS laba_packed,
      coalesce(sum(
        CASE
          WHEN i.qty_actual IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
        END
      ), 0)::bigint AS laba_actual
    FROM nota n
    LEFT JOIN public.transaksi_items i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.rute
  )
  SELECT
    h.rute,
    coalesce(
      (
        SELECT u.nama
        FROM public.users u
        WHERE u.peran = 'sales'
          AND u.rute = h.rute
        LIMIT 1
      ),
      h.rute
    ),
    h.jumlah_nota,
    h.sudah_siap,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.laba_order,
    h.laba_packed,
    h.laba_actual
  FROM hitung h
  ORDER BY h.rute;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_nota_rute(p_tanggal date, p_rute text)
RETURNS TABLE (
  id_transaksi text,
  id_pelanggan text,
  nama_pelanggan text,
  status text,
  pending boolean,
  waktu_order timestamptz,
  waktu_packed timestamptz,
  waktu_actual timestamptz,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
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
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;

  RETURN QUERY
  SELECT
    t.id_transaksi,
    t.id_pelanggan,
    t.nama_pelanggan,
    t.status,
    t.pending,
    t.waktu_order,
    t.waktu_packed,
    t.waktu_actual,
    coalesce(sum(i.subtotal_jual_order), 0)::bigint,
    coalesce(sum(i.subtotal_jual_packed), 0)::bigint,
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint,
    coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_packed IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
      END
    ), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_actual IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
      END
    ), 0)::bigint
  FROM public.transaksi t
  LEFT JOIN public.transaksi_items i ON i.id_transaksi = t.id_transaksi
  WHERE (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
    AND t.rute = p_rute
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order DESC;
END;
$$;

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

CREATE OR REPLACE FUNCTION public.gudang_barang_katalog()
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
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
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
  WHERE btrim(b.id_barang) <> ''
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 8000;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_barang_cari(p_kata text)
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
  v_q text := lower(btrim(COALESCE(p_kata, '')));
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
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
  WHERE btrim(b.id_barang) <> ''
    AND (
      v_q = ''
      OR lower(b.nama_barang) LIKE '%' || v_q || '%'
      OR lower(b.id_barang) LIKE '%' || v_q || '%'
    )
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 80;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_barang_banyak(p_id jsonb)
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
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_id IS NULL OR jsonb_typeof(p_id) <> 'array' THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
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
  WHERE b.id_barang IN (
    SELECT jsonb_array_elements_text(p_id)
  )
  ORDER BY lower(b.nama_barang), b.id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_pack_nota(
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
  v_status text;
  v_actual timestamptz;
  v_item jsonb;
  v_sku text;
  v_qty integer;
  v_sisa numeric;
  v_maks numeric;
  v_lama integer;
  v_delta integer;
  v_jual integer;
  v_beli integer;
  v_nama text;
  v_grup text;
  v_min1 integer; v_jual1 integer;
  v_min2 integer; v_jual2 integer;
  v_min3 integer; v_jual3 integer;
  v_min4 integer; v_jual4 integer;
  v_min5 integer; v_jual5 integer;
  v_ada boolean;
  v_ada_isi boolean;
  v_n integer;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.gudang_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  IF btrim(COALESCE(p_id_transaksi, '')) = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar packing wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.waktu_actual
  INTO v_status, v_actual
  FROM public.transaksi t
  WHERE t.id_transaksi = p_id_transaksi
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada.';
  END IF;
  IF v_status = 'batal' THEN
    RAISE EXCEPTION 'Nota batal tidak bisa di packing.';
  END IF;
  IF v_actual IS NOT NULL OR v_status = 'terkirim' THEN
    RAISE EXCEPTION 'Nota sudah terkunci. Packing tidak bisa diubah.';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_sku := btrim(COALESCE(v_item ->> 'id_barang', ''));
    IF v_sku = '' THEN
      CONTINUE;
    END IF;
    v_qty := COALESCE((v_item ->> 'qty_packed')::integer, 0);
    IF v_qty < 0 THEN
      RAISE EXCEPTION 'Qty packing tidak boleh negatif (SKU %).', v_sku;
    END IF;

    SELECT
      b.id_barang,
      b.nama_barang,
      COALESCE(b.harga_jual, 0),
      GREATEST(COALESCE(b.harga_beli, 0), 0),
      b.id_grup,
      b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
      b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
      b.min_strat_5, b.jual_strat_5,
      b.stok
    INTO
      v_sku, v_nama, v_jual, v_beli, v_grup,
      v_min1, v_jual1, v_min2, v_jual2,
      v_min3, v_jual3, v_min4, v_jual4,
      v_min5, v_jual5,
      v_sisa
    FROM public.barang b
    WHERE lower(b.id_barang) = lower(v_sku)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SKU % tidak ada di barang.', v_sku;
    END IF;

    SELECT true, i.qty_packed INTO v_ada, v_lama
    FROM public.transaksi_items i
    WHERE i.id_transaksi = p_id_transaksi
      AND i.id_barang = v_sku
    FOR UPDATE;
    IF NOT FOUND THEN
      v_ada := false;
      v_lama := 0;
      IF v_qty <= 0 THEN
        CONTINUE;
      END IF;
    END IF;

    v_sisa := COALESCE(v_sisa, 0);
    v_maks := v_sisa + COALESCE(v_lama, 0);
    IF v_maks < COALESCE(v_lama, 0) THEN
      v_maks := COALESCE(v_lama, 0);
    END IF;
    IF v_qty > v_maks THEN
      RAISE EXCEPTION 'Sisa stok tidak cukup (SKU %).', v_sku;
    END IF;

    IF NOT v_ada THEN
      INSERT INTO public.transaksi_items (
        id_transaksi, id_barang, id_grup, nama_barang, harga_beli, harga_jual,
        qty_order, harga_jual_order,
        qty_packed, harga_jual_packed,
        min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
        min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
        min_strat_5, jual_strat_5
      ) VALUES (
        p_id_transaksi, v_sku, v_grup, v_nama, v_beli, v_jual,
        0, v_jual,
        v_qty, v_jual,
        COALESCE(v_min1, 0), COALESCE(v_jual1, 0),
        COALESCE(v_min2, 0), COALESCE(v_jual2, 0),
        COALESCE(v_min3, 0), COALESCE(v_jual3, 0),
        COALESCE(v_min4, 0), COALESCE(v_jual4, 0),
        COALESCE(v_min5, 0), COALESCE(v_jual5, 0)
      );
    END IF;

    v_delta := v_qty - COALESCE(v_lama, 0);
    IF v_delta <> 0 THEN
      UPDATE public.barang
      SET stok = stok - v_delta
      WHERE lower(id_barang) = lower(v_sku)
        AND stok - v_delta >= 0;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n < 1 THEN
        RAISE EXCEPTION 'Sisa stok tidak cukup (SKU %).', v_sku;
      END IF;
    END IF;

    IF v_ada THEN
      UPDATE public.transaksi_items
      SET
        qty_packed = v_qty,
        harga_jual_packed = COALESCE(harga_jual_packed, harga_jual_order, v_jual, 0)
      WHERE id_transaksi = p_id_transaksi
        AND id_barang = v_sku;
    END IF;
  END LOOP;

  UPDATE public.transaksi_items i
  SET
    qty_packed = 0,
    harga_jual_packed = COALESCE(i.harga_jual_order, 0)
  WHERE i.id_transaksi = p_id_transaksi
    AND i.qty_packed IS NULL;

  UPDATE public.transaksi_items i
  SET harga_jual_packed = public.harga_jual_strata(
    COALESCE(i.harga_jual, 0),
    (
      SELECT COALESCE(sum(x.qty_packed), 0)::integer
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
  WHERE i.id_transaksi = p_id_transaksi
    AND i.qty_packed IS NOT NULL;

  SELECT EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    WHERE i.id_transaksi = p_id_transaksi
      AND COALESCE(i.qty_packed, 0) > 0
  ) INTO v_ada_isi;

  IF v_ada_isi THEN
    UPDATE public.transaksi
    SET
      waktu_packed = COALESCE(waktu_packed, clock_timestamp()),
      status = CASE WHEN status = 'diproses' THEN 'dikirim' ELSE status END
    WHERE id_transaksi = p_id_transaksi;
  ELSE
    UPDATE public.transaksi
    SET
      status = 'batal',
      pending = false,
      waktu_packed = COALESCE(waktu_packed, clock_timestamp())
    WHERE id_transaksi = p_id_transaksi;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_kartu_rute(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_kartu_rute(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_rute(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_rute(date, text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_item(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_item(text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_barang_katalog() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_barang_katalog()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_barang_cari(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_barang_cari(text)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_barang_banyak(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_barang_banyak(jsonb)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_pack_nota(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_pack_nota(text, jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
