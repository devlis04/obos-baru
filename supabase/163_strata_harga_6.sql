-- Slot strata ke-6 (min_strat_6 / jual_strat_6).
-- Jalankan SETELAH 155. SQL Editor → Run. Boleh diulang.
-- Nota lama tetap 5 tingkat (kolom baru 0). Jangan dijalankan otomatis.

ALTER TABLE public.barang
  ADD COLUMN IF NOT EXISTS min_strat_6 integer NOT NULL DEFAULT 0;
ALTER TABLE public.barang
  ADD COLUMN IF NOT EXISTS jual_strat_6 integer NOT NULL DEFAULT 0;
ALTER TABLE public.transaksi_items
  ADD COLUMN IF NOT EXISTS min_strat_6 integer NOT NULL DEFAULT 0;
ALTER TABLE public.transaksi_items
  ADD COLUMN IF NOT EXISTS jual_strat_6 integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.barang.min_strat_6 IS
  'Qty minimal strata 6. 0 = tidak dipakai.';
COMMENT ON COLUMN public.barang.jual_strat_6 IS
  'Harga jual strata 6 = harga_jual - pengurang_strata * 6.';

DROP FUNCTION IF EXISTS public.harga_jual_strata(
  integer, integer, integer, integer, integer, integer,
  integer, integer, integer, integer, integer, integer
) CASCADE;

CREATE FUNCTION public.harga_jual_strata(
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
  p_jual5 integer,
  p_min6 integer DEFAULT 0,
  p_jual6 integer DEFAULT 0
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
          (p_min6, p_jual6),
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

CREATE OR REPLACE VIEW public.v_transaksi_item AS
SELECT
  z.*,
  z.qty_order * z.harga_jual_order AS subtotal_jual_order,
  CASE
    WHEN z.qty_packed IS NULL THEN NULL
    ELSE z.qty_packed * z.harga_jual_packed
  END AS subtotal_jual_packed,
  CASE
    WHEN z.qty_actual IS NULL THEN NULL
    ELSE z.qty_actual * z.harga_jual_actual
  END AS subtotal_jual_actual
FROM (
  SELECT
    i.id,
    i.id_transaksi,
    i.id_barang,
    i.id_grup,
    i.nama_barang,
    i.harga_beli,
    i.harga_jual,
    i.qty_order,
    i.qty_packed,
    i.qty_actual,
    i.subtotal_beli_order,
    i.subtotal_beli_packed,
    i.subtotal_beli_actual,
    i.min_strat_1,
    i.jual_strat_1,
    i.min_strat_2,
    i.jual_strat_2,
    i.min_strat_3,
    i.jual_strat_3,
    i.min_strat_4,
    i.jual_strat_4,
    i.min_strat_5,
    i.jual_strat_5,
    i.min_strat_6,
    i.jual_strat_6,
    public.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(i.qty_order) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5,
      i.min_strat_6, i.jual_strat_6
    ) AS harga_jual_order,
    CASE WHEN i.qty_packed IS NULL THEN NULL ELSE public.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(COALESCE(i.qty_packed, 0)) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5,
      i.min_strat_6, i.jual_strat_6
    ) END AS harga_jual_packed,
    CASE WHEN i.qty_actual IS NULL THEN NULL ELSE public.harga_jual_strata(
      COALESCE(i.harga_jual, 0),
      COALESCE(SUM(COALESCE(i.qty_actual, 0)) OVER w, 0)::integer,
      i.min_strat_1, i.jual_strat_1,
      i.min_strat_2, i.jual_strat_2,
      i.min_strat_3, i.jual_strat_3,
      i.min_strat_4, i.jual_strat_4,
      i.min_strat_5, i.jual_strat_5,
      i.min_strat_6, i.jual_strat_6
    ) END AS harga_jual_actual
  FROM public.transaksi_items i
  WINDOW w AS (
    PARTITION BY i.id_transaksi,
      COALESCE(NULLIF(btrim(i.id_grup), ''), i.id_barang)
  )
) z;

GRANT SELECT ON public.v_transaksi_item TO authenticated, postgres, service_role;

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
    id_transaksi, id_barang, id_grup, nama_barang, harga_beli, harga_jual,
    qty_order,
    min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
    min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
    min_strat_5, jual_strat_5, min_strat_6, jual_strat_6
  )
  WITH pesan AS (
    SELECT
      btrim(e->>'id_barang') AS id_barang,
      SUM((e->>'qty')::integer) AS qty
    FROM jsonb_array_elements(p_items) AS e
    WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
      AND COALESCE((e->>'qty')::integer, 0) > 0
    GROUP BY 1
  )
  SELECT
    p_id,
    p.id_barang,
    NULLIF(btrim(COALESCE(b.id_grup, '')), ''),
    b.nama_barang,
    COALESCE(b.harga_beli, 0),
    COALESCE(b.harga_jual, 0),
    p.qty,
    COALESCE(b.min_strat_1, 0), COALESCE(b.jual_strat_1, 0),
    COALESCE(b.min_strat_2, 0), COALESCE(b.jual_strat_2, 0),
    COALESCE(b.min_strat_3, 0), COALESCE(b.jual_strat_3, 0),
    COALESCE(b.min_strat_4, 0), COALESCE(b.jual_strat_4, 0),
    COALESCE(b.min_strat_5, 0), COALESCE(b.jual_strat_5, 0),
    COALESCE(b.min_strat_6, 0), COALESCE(b.jual_strat_6, 0)
  FROM pesan p
  JOIN public.barang b ON b.id_barang = p.id_barang;

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN COALESCE(n, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.barang_ikut_modal(
  p_id_barang text,
  p_beli_baru integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_lama integer;
  v_baru integer;
  v_jual integer;
  v_peng integer;
  v_peng0 integer;
  v_min int[];
  v_ok boolean;
  v_putar integer;
  v_i integer;
BEGIN
  v_id := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  v_baru := GREATEST(COALESCE(p_beli_baru, 0), 0);

  SELECT
    b.harga_beli,
    b.harga_jual,
    b.pengurang_strata,
    ARRAY[
      b.min_strat_1, b.min_strat_2, b.min_strat_3,
      b.min_strat_4, b.min_strat_5, b.min_strat_6
    ]
  INTO v_lama, v_jual, v_peng, v_min
  FROM public.barang b
  WHERE lower(b.id_barang) = lower(v_id);
  IF NOT FOUND THEN
    RETURN;
  END IF;
  v_lama := COALESCE(v_lama, 0);
  v_jual := COALESCE(v_jual, 0);
  v_peng := COALESCE(v_peng, 0);
  IF v_lama = v_baru THEN
    RETURN;
  END IF;

  v_jual := public.skala_harga_beli(v_jual, v_lama, v_baru);
  v_peng := public.skala_harga_beli(v_peng, v_lama, v_baru);
  IF v_peng = 0
     AND COALESCE(v_min[1], 0) + COALESCE(v_min[2], 0) + COALESCE(v_min[3], 0)
       + COALESCE(v_min[4], 0) + COALESCE(v_min[5], 0) + COALESCE(v_min[6], 0) > 0
     AND v_lama > 0 AND v_baru > 0 THEN
    v_peng := 500;
  END IF;
  v_peng0 := v_peng;

  IF v_jual > 0 AND v_baru > 0 AND v_jual <= v_baru THEN
    v_jual := (v_baru / 500 + 1) * 500;
  END IF;

  FOR v_putar IN 1..8 LOOP
    v_ok := true;
    IF v_jual > 0 AND v_baru > 0 AND v_jual <= v_baru THEN
      v_ok := false;
    END IF;
    FOR v_i IN 1..6 LOOP
      IF COALESCE(v_min[v_i], 0) > 0 THEN
        IF (v_jual - v_peng * v_i) <= v_baru THEN
          v_ok := false;
        END IF;
      END IF;
    END LOOP;
    EXIT WHEN v_ok;
    IF v_peng >= 500 THEN
      v_peng := v_peng - 500;
    ELSE
      v_peng := v_peng0;
      IF v_baru > 0 THEN
        v_jual := v_jual + 500;
      ELSE
        EXIT;
      END IF;
    END IF;
  END LOOP;

  UPDATE public.barang b
  SET
    harga_beli = v_baru,
    harga_jual = GREATEST(v_jual, 0),
    pengurang_strata = GREATEST(v_peng, 0),
    jual_strat_1 = CASE WHEN COALESCE(v_min[1], 0) > 0
      THEN GREATEST(v_jual - v_peng * 1, 0) ELSE 0 END,
    jual_strat_2 = CASE WHEN COALESCE(v_min[2], 0) > 0
      THEN GREATEST(v_jual - v_peng * 2, 0) ELSE 0 END,
    jual_strat_3 = CASE WHEN COALESCE(v_min[3], 0) > 0
      THEN GREATEST(v_jual - v_peng * 3, 0) ELSE 0 END,
    jual_strat_4 = CASE WHEN COALESCE(v_min[4], 0) > 0
      THEN GREATEST(v_jual - v_peng * 4, 0) ELSE 0 END,
    jual_strat_5 = CASE WHEN COALESCE(v_min[5], 0) > 0
      THEN GREATEST(v_jual - v_peng * 5, 0) ELSE 0 END,
    jual_strat_6 = CASE WHEN COALESCE(v_min[6], 0) > 0
      THEN GREATEST(v_jual - v_peng * 6, 0) ELSE 0 END
  WHERE lower(b.id_barang) = lower(v_id);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_barang_simpan(jsonb);
CREATE FUNCTION public.admin_barang_simpan(p_barang jsonb)
RETURNS TABLE (
  id_barang text,
  id_grup text,
  nama_barang text,
  kategori text,
  stok numeric,
  sisa_buku numeric,
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
  jual_strat_5 integer,
  min_strat_6 integer,
  jual_strat_6 integer,
  pengurang_strata integer,
  aktif boolean,
  id_supplier_utama integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_nama text;
  v_ada boolean;
  v_beli integer;
  v_jual integer;
  v_pengurang integer;
  v_min1 integer; v_min2 integer; v_min3 integer;
  v_min4 integer; v_min5 integer; v_min6 integer;
  v_jual1 integer; v_jual2 integer; v_jual3 integer;
  v_jual4 integer; v_jual5 integer; v_jual6 integer;
  v_utama integer;
  v_modal integer;
  v_buku bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_barang IS NULL OR jsonb_typeof(p_barang) <> 'object' THEN
    RAISE EXCEPTION 'Data barang kosong.';
  END IF;

  v_id := btrim(COALESCE(p_barang->>'id_barang', ''));
  v_nama := btrim(COALESCE(p_barang->>'nama_barang', ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'Id barang wajib diisi.';
  END IF;
  IF v_nama = '' THEN
    RAISE EXCEPTION 'Nama barang wajib diisi.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.barang b WHERE lower(b.id_barang) = lower(v_id)
  ) INTO v_ada;
  IF NOT v_ada THEN
    RAISE EXCEPTION 'SKU baru hanya dari Barang masuk.';
  END IF;

  IF p_barang->'harga_beli' IS NULL OR p_barang->>'harga_beli' = '' THEN
    RAISE EXCEPTION 'Harga beli wajib diisi.';
  END IF;
  IF p_barang->'harga_jual' IS NULL OR p_barang->>'harga_jual' = '' THEN
    RAISE EXCEPTION 'Harga jual wajib diisi.';
  END IF;
  v_beli := COALESCE((p_barang->>'harga_beli')::integer, 0);
  v_jual := COALESCE((p_barang->>'harga_jual')::integer, 0);
  v_pengurang := GREATEST(0, COALESCE((p_barang->>'pengurang_strata')::integer, 0));

  SELECT b.id_supplier_utama, h.harga_beli
  INTO v_utama, v_modal
  FROM public.barang b
  LEFT JOIN public.supplier_harga h
    ON h.id_supplier = b.id_supplier_utama
   AND lower(h.id_barang) = lower(b.id_barang)
  WHERE lower(b.id_barang) = lower(v_id);

  IF v_utama IS NOT NULL AND COALESCE(v_modal, 0) > 0 THEN
    SELECT b.harga_beli INTO v_beli
    FROM public.barang b
    WHERE lower(b.id_barang) = lower(v_id);
    v_beli := COALESCE(v_beli, v_modal);
  END IF;

  IF v_beli < 0 OR v_jual < 0 THEN
    RAISE EXCEPTION 'Harga tidak boleh minus.';
  END IF;
  IF v_jual <= v_beli THEN
    RAISE EXCEPTION 'Harga jual harus lebih besar dari harga beli.';
  END IF;

  v_min1 := GREATEST(0, COALESCE((p_barang->>'min_strat_1')::integer, 0));
  v_min2 := GREATEST(0, COALESCE((p_barang->>'min_strat_2')::integer, 0));
  v_min3 := GREATEST(0, COALESCE((p_barang->>'min_strat_3')::integer, 0));
  v_min4 := GREATEST(0, COALESCE((p_barang->>'min_strat_4')::integer, 0));
  v_min5 := GREATEST(0, COALESCE((p_barang->>'min_strat_5')::integer, 0));
  v_min6 := GREATEST(0, COALESCE((p_barang->>'min_strat_6')::integer, 0));

  IF (v_min1 > 0 OR v_min2 > 0 OR v_min3 > 0 OR v_min4 > 0 OR v_min5 > 0 OR v_min6 > 0)
     AND v_pengurang <= 0 THEN
    RAISE EXCEPTION 'Nilai pengurang wajib diisi jika strata dipakai.';
  END IF;

  v_jual1 := CASE WHEN v_min1 > 0 THEN v_jual - (v_pengurang * 1) ELSE 0 END;
  v_jual2 := CASE WHEN v_min2 > 0 THEN v_jual - (v_pengurang * 2) ELSE 0 END;
  v_jual3 := CASE WHEN v_min3 > 0 THEN v_jual - (v_pengurang * 3) ELSE 0 END;
  v_jual4 := CASE WHEN v_min4 > 0 THEN v_jual - (v_pengurang * 4) ELSE 0 END;
  v_jual5 := CASE WHEN v_min5 > 0 THEN v_jual - (v_pengurang * 5) ELSE 0 END;
  v_jual6 := CASE WHEN v_min6 > 0 THEN v_jual - (v_pengurang * 6) ELSE 0 END;

  IF (v_min1 > 0 AND v_jual1 <= v_beli)
     OR (v_min2 > 0 AND v_jual2 <= v_beli)
     OR (v_min3 > 0 AND v_jual3 <= v_beli)
     OR (v_min4 > 0 AND v_jual4 <= v_beli)
     OR (v_min5 > 0 AND v_jual5 <= v_beli)
     OR (v_min6 > 0 AND v_jual6 <= v_beli) THEN
    RAISE EXCEPTION 'Harga jual strata harus lebih besar dari harga beli.';
  END IF;

  UPDATE public.barang b
  SET
    id_grup = nullif(btrim(COALESCE(p_barang->>'id_grup', '')), ''),
    nama_barang = v_nama,
    kategori = nullif(btrim(COALESCE(p_barang->>'kategori', '')), ''),
    harga_beli = v_beli,
    harga_jual = v_jual,
    pengurang_strata = v_pengurang,
    min_strat_1 = v_min1, jual_strat_1 = GREATEST(0, v_jual1),
    min_strat_2 = v_min2, jual_strat_2 = GREATEST(0, v_jual2),
    min_strat_3 = v_min3, jual_strat_3 = GREATEST(0, v_jual3),
    min_strat_4 = v_min4, jual_strat_4 = GREATEST(0, v_jual4),
    min_strat_5 = v_min5, jual_strat_5 = GREATEST(0, v_jual5),
    min_strat_6 = v_min6, jual_strat_6 = GREATEST(0, v_jual6),
    aktif = COALESCE((p_barang->>'aktif')::boolean, true)
  WHERE lower(b.id_barang) = lower(v_id);

  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang, b.id_grup, b.nama_barang, b.kategori, b.stok,
    COALESCE(so.stok_hitung, b.stok),
    b.harga_beli, b.harga_jual,
    b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
    b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
    b.min_strat_5, b.jual_strat_5, b.min_strat_6, b.jual_strat_6,
    b.pengurang_strata, b.aktif, b.id_supplier_utama
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE lower(b.id_barang) = lower(v_id);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_barang_semua();
CREATE FUNCTION public.admin_barang_semua()
RETURNS TABLE (
  id_barang text,
  id_grup text,
  nama_barang text,
  kategori text,
  stok numeric,
  sisa_buku numeric,
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
  jual_strat_5 integer,
  min_strat_6 integer,
  jual_strat_6 integer,
  pengurang_strata integer,
  aktif boolean,
  id_supplier_utama integer
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
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang, b.id_grup, b.nama_barang, b.kategori, b.stok,
    COALESCE(so.stok_hitung, b.stok),
    b.harga_beli, b.harga_jual,
    b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
    b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
    b.min_strat_5, b.jual_strat_5, b.min_strat_6, b.jual_strat_6,
    b.pengurang_strata, b.aktif, b.id_supplier_utama
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> ''
  ORDER BY lower(b.id_barang);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_csv(p_baris jsonb)
RETURNS TABLE (
  baris integer,
  id_barang text,
  aksi text,
  ok boolean,
  pesan text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_e jsonb;
  v_i integer := 0;
  v_id text;
  v_nama text;
  v_satuan text;
  v_rincian text;
  v_full text;
  v_hapus boolean;
  v_ada boolean;
  v_pakai boolean;
  v_utama integer;
  v_aktif boolean;
  v_teks text;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Data CSV kosong.';
  END IF;
  IF jsonb_array_length(p_baris) > 3000 THEN
    RAISE EXCEPTION 'Maksimal 3000 baris per unggah.';
  END IF;

  FOR v_e IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_i := v_i + 1;
    baris := v_i;
    id_barang := btrim(COALESCE(v_e->>'id_barang', ''));
    aksi := '';
    ok := false;
    pesan := '';
    BEGIN
      v_id := id_barang;
      IF v_id = '' THEN
        RAISE EXCEPTION 'Id barang wajib diisi.';
      END IF;
      v_hapus := COALESCE((v_e->>'hapus')::boolean, false);
      SELECT EXISTS (
        SELECT 1 FROM public.barang b WHERE lower(b.id_barang) = lower(v_id)
      ) INTO v_ada;

      IF NOT v_ada THEN
        RAISE EXCEPTION 'SKU baru hanya dari Barang masuk.';
      END IF;

      IF v_hapus THEN
        SELECT EXISTS (
          SELECT 1 FROM public.transaksi_items i WHERE lower(i.id_barang) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.stok_opname so WHERE lower(so.id_barang) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.barang_masuk m WHERE lower(m.id_barang) = lower(v_id)
        ) INTO v_pakai;
        IF v_pakai THEN
          UPDATE public.barang b
          SET aktif = false
          WHERE lower(b.id_barang) = lower(v_id);
          aksi := 'nonaktif';
          ok := true;
          pesan := 'Sudah dipakai nota/buku. Tidak dihapus, dinonaktifkan.';
        ELSE
          DELETE FROM public.supplier_harga h
          WHERE lower(h.id_barang) = lower(v_id);
          DELETE FROM public.barang b WHERE lower(b.id_barang) = lower(v_id);
          aksi := 'hapus';
          ok := true;
          pesan := 'Dihapus.';
        END IF;
      ELSE
        v_nama := btrim(COALESCE(v_e->>'nama', v_e->>'nama_barang', ''));
        v_satuan := btrim(COALESCE(v_e->>'satuan', ''));
        v_rincian := btrim(COALESCE(v_e->>'rincian', ''));
        IF v_nama = '' THEN
          RAISE EXCEPTION 'Nama barang wajib diisi.';
        END IF;
        IF v_satuan = '' THEN
          RAISE EXCEPTION 'Satuan wajib diisi.';
        END IF;
        v_full := v_nama || ' /' || v_satuan;
        IF v_rincian <> '' THEN
          v_full := v_full || '/' || v_rincian;
        END IF;
        SELECT b.aktif INTO v_aktif
        FROM public.barang b
        WHERE lower(b.id_barang) = lower(v_id);
        IF v_e ? 'aktif' AND v_e->>'aktif' IS NOT NULL AND btrim(v_e->>'aktif') <> '' THEN
          v_aktif := (v_e->>'aktif')::boolean;
        END IF;
        PERFORM * FROM public.admin_barang_simpan(
          jsonb_build_object(
            'id_barang', v_id,
            'id_grup', COALESCE(v_e->>'id_grup', ''),
            'nama_barang', v_full,
            'kategori', COALESCE(v_e->>'kategori', ''),
            'harga_beli', COALESCE((v_e->>'harga_beli')::integer, 0),
            'harga_jual', COALESCE((v_e->>'harga_jual')::integer, 0),
            'pengurang_strata', COALESCE((v_e->>'pengurang_strata')::integer, 0),
            'min_strat_1', COALESCE((v_e->>'min_strat_1')::integer, 0),
            'min_strat_2', COALESCE((v_e->>'min_strat_2')::integer, 0),
            'min_strat_3', COALESCE((v_e->>'min_strat_3')::integer, 0),
            'min_strat_4', COALESCE((v_e->>'min_strat_4')::integer, 0),
            'min_strat_5', COALESCE((v_e->>'min_strat_5')::integer, 0),
            'min_strat_6', COALESCE((v_e->>'min_strat_6')::integer, 0),
            'aktif', COALESCE(v_aktif, true)
          )
        );
        v_teks := btrim(COALESCE(v_e->>'id_supplier_utama', ''));
        IF v_teks <> '' THEN
          v_utama := v_teks::integer;
          IF NOT public.admin_barang_utama_set(v_id, v_utama) THEN
            RAISE EXCEPTION 'Pemasok utama tidak valid.';
          END IF;
        END IF;
        aksi := 'ubah';
        ok := true;
        pesan := 'Diubah.';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      ok := false;
      IF aksi = '' THEN
        aksi := CASE WHEN COALESCE((v_e->>'hapus')::boolean, false) THEN 'hapus' ELSE 'simpan' END;
      END IF;
      pesan := SQLERRM;
    END;
    RETURN NEXT;
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.sales_barang_katalog();
CREATE FUNCTION public.sales_barang_katalog()
RETURNS TABLE (
  id_barang text, id_grup text, nama_barang text, kategori text, stok numeric,
  harga_beli integer, harga_jual integer,
  min_strat_1 integer, jual_strat_1 integer, min_strat_2 integer, jual_strat_2 integer,
  min_strat_3 integer, jual_strat_3 integer, min_strat_4 integer, jual_strat_4 integer,
  min_strat_5 integer, jual_strat_5 integer, min_strat_6 integer, jual_strat_6 integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
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
    b.id_barang, b.id_grup, b.nama_barang, b.kategori,
    COALESCE(so.stok_hitung, b.stok), b.harga_beli, b.harga_jual,
    b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
    b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
    b.min_strat_5, b.jual_strat_5, b.min_strat_6, b.jual_strat_6
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> '' AND b.aktif
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 8000;
END;
$$;

DROP FUNCTION IF EXISTS public.gudang_barang_katalog();
CREATE FUNCTION public.gudang_barang_katalog()
RETURNS TABLE (
  id_barang text, id_grup text, nama_barang text, kategori text, stok numeric,
  harga_beli integer, harga_jual integer,
  min_strat_1 integer, jual_strat_1 integer, min_strat_2 integer, jual_strat_2 integer,
  min_strat_3 integer, jual_strat_3 integer, min_strat_4 integer, jual_strat_4 integer,
  min_strat_5 integer, jual_strat_5 integer, min_strat_6 integer, jual_strat_6 integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang, b.id_grup, b.nama_barang, b.kategori,
    COALESCE(so.stok_hitung, b.stok), b.harga_beli, b.harga_jual,
    b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
    b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
    b.min_strat_5, b.jual_strat_5, b.min_strat_6, b.jual_strat_6
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> '' AND b.aktif
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 8000;
END;
$$;

DROP FUNCTION IF EXISTS public.gudang_barang_cari(text);
CREATE FUNCTION public.gudang_barang_cari(p_kata text)
RETURNS TABLE (
  id_barang text, id_grup text, nama_barang text, kategori text, stok numeric,
  harga_beli integer, harga_jual integer,
  min_strat_1 integer, jual_strat_1 integer, min_strat_2 integer, jual_strat_2 integer,
  min_strat_3 integer, jual_strat_3 integer, min_strat_4 integer, jual_strat_4 integer,
  min_strat_5 integer, jual_strat_5 integer, min_strat_6 integer, jual_strat_6 integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_q text := lower(btrim(COALESCE(p_kata, '')));
  v_buku bigint;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang, b.id_grup, b.nama_barang, b.kategori,
    COALESCE(so.stok_hitung, b.stok), b.harga_beli, b.harga_jual,
    b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
    b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
    b.min_strat_5, b.jual_strat_5, b.min_strat_6, b.jual_strat_6
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> '' AND b.aktif
    AND (
      v_q = ''
      OR lower(b.nama_barang) LIKE '%' || v_q || '%'
      OR lower(b.id_barang) LIKE '%' || v_q || '%'
    )
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 80;
END;
$$;

DROP FUNCTION IF EXISTS public.gudang_barang_banyak(jsonb);
CREATE FUNCTION public.gudang_barang_banyak(p_id jsonb)
RETURNS TABLE (
  id_barang text, id_grup text, nama_barang text, kategori text, stok numeric,
  harga_beli integer, harga_jual integer,
  min_strat_1 integer, jual_strat_1 integer, min_strat_2 integer, jual_strat_2 integer,
  min_strat_3 integer, jual_strat_3 integer, min_strat_4 integer, jual_strat_4 integer,
  min_strat_5 integer, jual_strat_5 integer, min_strat_6 integer, jual_strat_6 integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_id IS NULL OR jsonb_typeof(p_id) <> 'array' THEN
    RETURN;
  END IF;
  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang, b.id_grup, b.nama_barang, b.kategori,
    COALESCE(so.stok_hitung, b.stok), b.harga_beli, b.harga_jual,
    b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
    b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
    b.min_strat_5, b.jual_strat_5, b.min_strat_6, b.jual_strat_6
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku AND so.id_barang = b.id_barang
  WHERE b.id_barang IN (SELECT jsonb_array_elements_text(p_id))
  ORDER BY lower(b.nama_barang), b.id_barang;
END;
$$;

DROP FUNCTION IF EXISTS public.gudang_nota_item(text);
CREATE FUNCTION public.gudang_nota_item(p_id_transaksi text)
RETURNS TABLE (
  id_barang text, nama_barang text, qty_order integer, qty_packed integer,
  qty_actual integer, harga_jual_order integer, harga_beli_order integer,
  harga_jual_packed integer, harga_beli_packed integer,
  harga_jual_actual integer, harga_beli_actual integer,
  subtotal_order integer, subtotal_packed integer, subtotal_actual integer,
  id_grup_kunci text, harga_jual_kunci integer,
  min_strat_1 integer, jual_strat_1 integer, min_strat_2 integer, jual_strat_2 integer,
  min_strat_3 integer, jual_strat_3 integer, min_strat_4 integer, jual_strat_4 integer,
  min_strat_5 integer, jual_strat_5 integer, min_strat_6 integer, jual_strat_6 integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
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
    i.id_barang, i.nama_barang, i.qty_order, i.qty_packed, i.qty_actual,
    i.harga_jual_order, i.harga_beli, i.harga_jual_packed, i.harga_beli,
    i.harga_jual_actual, i.harga_beli,
    i.subtotal_jual_order, i.subtotal_jual_packed, i.subtotal_jual_actual,
    i.id_grup, COALESCE(i.harga_jual, 0),
    i.min_strat_1, i.jual_strat_1, i.min_strat_2, i.jual_strat_2,
    i.min_strat_3, i.jual_strat_3, i.min_strat_4, i.jual_strat_4,
    i.min_strat_5, i.jual_strat_5, i.min_strat_6, i.jual_strat_6
  FROM public.v_transaksi_item i
  WHERE i.id_transaksi = p_id_transaksi
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
$$;

DROP FUNCTION IF EXISTS public.pengirim_nota_item(text);
CREATE FUNCTION public.pengirim_nota_item(p_id_transaksi text)
RETURNS TABLE (
  id_barang text, nama_barang text, id_grup text, harga_jual integer,
  harga_beli integer, qty_order integer, qty_packed integer, qty_actual integer,
  harga_jual_order integer, harga_jual_packed integer, harga_jual_actual integer,
  subtotal_order integer, subtotal_packed integer, subtotal_actual integer,
  min_strat_1 integer, jual_strat_1 integer, min_strat_2 integer, jual_strat_2 integer,
  min_strat_3 integer, jual_strat_3 integer, min_strat_4 integer, jual_strat_4 integer,
  min_strat_5 integer, jual_strat_5 integer, min_strat_6 integer, jual_strat_6 integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
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
    WHERE t.id_transaksi = v_id AND t.rute = ANY (v_sales)
  ) THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  RETURN QUERY
  SELECT
    i.id_barang, i.nama_barang, i.id_grup, i.harga_jual, i.harga_beli,
    i.qty_order, i.qty_packed, i.qty_actual,
    i.harga_jual_order, i.harga_jual_packed, i.harga_jual_actual,
    i.subtotal_jual_order, i.subtotal_jual_packed, i.subtotal_jual_actual,
    i.min_strat_1, i.jual_strat_1, i.min_strat_2, i.jual_strat_2,
    i.min_strat_3, i.jual_strat_3, i.min_strat_4, i.jual_strat_4,
    i.min_strat_5, i.jual_strat_5, i.min_strat_6, i.jual_strat_6
  FROM public.v_transaksi_item i
  WHERE i.id_transaksi = v_id
  ORDER BY lower(i.nama_barang), i.id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.salesman_nota_rentang(p_dari date, p_sampai date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_isi jsonb;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun sales yang boleh melihat nota ini.';
  END IF;
  IF p_dari IS NULL OR p_sampai IS NULL OR p_sampai < p_dari THEN
    RAISE EXCEPTION 'Rentang tanggal nota tidak sah.';
  END IF;
  SELECT btrim(u.rute) INTO v_rute
  FROM public.users u
  WHERE u.peran = 'sales' AND lower(btrim(u.email)) = public.email_jwt()
  LIMIT 1;
  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Akun sales belum punya rute.';
  END IF;
  SELECT coalesce(jsonb_agg(q.baris ORDER BY q.waktu_order DESC), '[]'::jsonb)
  INTO v_isi
  FROM (
    SELECT
      t.waktu_order,
      jsonb_build_object(
        'id_transaksi', t.id_transaksi,
        'id_pelanggan', t.id_pelanggan,
        'nama_pelanggan', t.nama_pelanggan,
        'rute', t.rute,
        'status', t.status,
        'pending', t.pending,
        'waktu_order', t.waktu_order,
        'waktu_packed', t.waktu_packed,
        'waktu_actual', t.waktu_actual,
        'transaksi_items', coalesce((
          SELECT jsonb_agg(
            jsonb_build_object(
              'id_barang', i.id_barang,
              'id_grup', i.id_grup,
              'nama_barang', i.nama_barang,
              'qty_order', i.qty_order,
              'harga_jual', i.harga_jual,
              'harga_beli', i.harga_beli,
              'qty_packed', i.qty_packed,
              'qty_actual', i.qty_actual,
              'subtotal_beli_order', i.subtotal_beli_order,
              'min_strat_1', i.min_strat_1, 'jual_strat_1', i.jual_strat_1,
              'min_strat_2', i.min_strat_2, 'jual_strat_2', i.jual_strat_2,
              'min_strat_3', i.min_strat_3, 'jual_strat_3', i.jual_strat_3,
              'min_strat_4', i.min_strat_4, 'jual_strat_4', i.jual_strat_4,
              'min_strat_5', i.min_strat_5, 'jual_strat_5', i.jual_strat_5,
              'min_strat_6', i.min_strat_6, 'jual_strat_6', i.jual_strat_6
            )
            ORDER BY i.nama_barang
          )
          FROM public.transaksi_items i
          WHERE i.id_transaksi = t.id_transaksi
        ), '[]'::jsonb)
      ) AS baris
    FROM public.v_transaksi_hari_label t
    WHERE btrim(t.rute) = v_rute
      AND t.hari_label >= p_dari
      AND t.hari_label <= p_sampai
  ) q;
  RETURN coalesce(v_isi, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.harga_jual_strata(
  integer, integer, integer, integer, integer, integer,
  integer, integer, integer, integer, integer, integer, integer, integer
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.harga_jual_strata(
  integer, integer, integer, integer, integer, integer,
  integer, integer, integer, integer, integer, integer, integer, integer
) TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.sales_isi_item_order(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_isi_item_order(text, jsonb)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_simpan(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_semua() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_csv(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sales_barang_katalog() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gudang_barang_katalog() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gudang_barang_cari(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gudang_barang_banyak(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gudang_nota_item(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pengirim_nota_item(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.salesman_nota_rentang(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.barang_ikut_modal(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_barang_simpan(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_semua()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_csv(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.sales_barang_katalog()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.gudang_barang_katalog()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.gudang_barang_cari(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.gudang_barang_banyak(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.gudang_nota_item(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_item(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.salesman_nota_rentang(date, date)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.barang_ikut_modal(text, integer)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
