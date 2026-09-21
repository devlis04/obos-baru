-- Katalog admin: ubah master, stok, CSV, pemasok utama.
-- Jalankan SETELAH 058. SQL Editor → Run. Boleh di-Run ulang.
-- SKU baru hanya dari Barang masuk. SKU nonaktif disembunyikan dari sales/gudang cari.

ALTER TABLE public.barang
  ADD COLUMN IF NOT EXISTS aktif boolean NOT NULL DEFAULT true;

ALTER TABLE public.barang
  ADD COLUMN IF NOT EXISTS pengurang_strata integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.barang.aktif IS
  'false = disembunyikan dari katalog lapangan. Tidak dihapus (FK nota).';
COMMENT ON COLUMN public.barang.pengurang_strata IS
  'Potongan per tingkat strata. jual_n = harga_jual - (pengurang_strata * n) jika min_n terisi.';

UPDATE public.barang
SET pengurang_strata = COALESCE(
  CASE
    WHEN min_strat_1 > 0 AND jual_strat_1 > 0 AND harga_jual > jual_strat_1
    THEN harga_jual - jual_strat_1
  END,
  CASE
    WHEN min_strat_2 > 0 AND jual_strat_2 > 0 AND harga_jual > jual_strat_2
    THEN (harga_jual - jual_strat_2) / 2
  END,
  CASE
    WHEN min_strat_3 > 0 AND jual_strat_3 > 0 AND harga_jual > jual_strat_3
    THEN (harga_jual - jual_strat_3) / 3
  END,
  CASE
    WHEN min_strat_4 > 0 AND jual_strat_4 > 0 AND harga_jual > jual_strat_4
    THEN (harga_jual - jual_strat_4) / 4
  END,
  CASE
    WHEN min_strat_5 > 0 AND jual_strat_5 > 0 AND harga_jual > jual_strat_5
    THEN (harga_jual - jual_strat_5) / 5
  END,
  0
)
WHERE pengurang_strata = 0;

DROP POLICY IF EXISTS barang_select_sales ON public.barang;
CREATE POLICY barang_select_sales
  ON public.barang
  FOR SELECT
  TO authenticated
  USING (public.rute_sales_saya() IS NOT NULL AND aktif);

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
DECLARE
  v_buku bigint;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
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
  v_buku bigint;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
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
    AND (
      v_q = ''
      OR lower(b.nama_barang) LIKE '%' || v_q || '%'
      OR lower(b.id_barang) LIKE '%' || v_q || '%'
    )
  ORDER BY lower(b.nama_barang), b.id_barang
  LIMIT 80;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_cari(p_q text)
RETURNS TABLE (id_barang text, nama_barang text, harga_beli integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_q text;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  v_q := lower(btrim(COALESCE(p_q, '')));
  IF length(v_q) < 1 THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT b.id_barang, b.nama_barang, b.harga_beli
  FROM public.barang b
  WHERE b.aktif
    AND (
      lower(b.id_barang) LIKE '%' || v_q || '%'
      OR lower(b.nama_barang) LIKE '%' || v_q || '%'
    )
  ORDER BY lower(b.nama_barang)
  LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulat_500(p integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p, 0) <= 0 THEN 0
    ELSE (round(p::numeric / 500) * 500)::integer
  END;
$$;

CREATE OR REPLACE FUNCTION public.skala_harga_beli(
  p_harga integer,
  p_beli_lama integer,
  p_beli_baru integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_harga, 0) <= 0 THEN COALESCE(p_harga, 0)
    WHEN COALESCE(p_beli_lama, 0) <= 0 THEN COALESCE(p_harga, 0)
    WHEN COALESCE(p_beli_baru, 0) <= 0 THEN COALESCE(p_harga, 0)
    WHEN p_beli_baru = p_beli_lama THEN COALESCE(p_harga, 0)
    ELSE (round((p_harga::numeric * p_beli_baru) / p_beli_lama / 500) * 500)::integer
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
      b.min_strat_1, b.min_strat_2, b.min_strat_3, b.min_strat_4, b.min_strat_5
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
  IF v_peng = 0 AND COALESCE(v_min[1], 0) + COALESCE(v_min[2], 0)
       + COALESCE(v_min[3], 0) + COALESCE(v_min[4], 0) + COALESCE(v_min[5], 0) > 0
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
    FOR v_i IN 1..5 LOOP
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
      THEN GREATEST(v_jual - v_peng * 5, 0) ELSE 0 END
  WHERE lower(b.id_barang) = lower(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.barang_modal_dari_utama(p_id_barang text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_harga integer;
BEGIN
  v_id := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  SELECT h.harga_beli INTO v_harga
  FROM public.barang b
  JOIN public.supplier_harga h
    ON h.id_supplier = b.id_supplier_utama
   AND lower(h.kode_barang) = lower(b.id_barang)
  WHERE lower(b.id_barang) = lower(v_id);
  IF COALESCE(v_harga, 0) > 0 THEN
    PERFORM public.barang_ikut_modal(v_id, v_harga);
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_barang_katalog(text);
DROP FUNCTION IF EXISTS public.admin_barang_semua();
DROP FUNCTION IF EXISTS public.admin_barang_simpan(jsonb);
DROP FUNCTION IF EXISTS public.admin_barang_stok(text, integer);
DROP FUNCTION IF EXISTS public.admin_barang_stok(text, numeric);
DROP FUNCTION IF EXISTS public.admin_barang_csv(jsonb);
DROP FUNCTION IF EXISTS public.admin_barang_stok_csv(jsonb);
DROP FUNCTION IF EXISTS public.admin_barang_pemasok_lihat(text);
DROP FUNCTION IF EXISTS public.admin_barang_utama_lihat(text);
DROP FUNCTION IF EXISTS public.admin_barang_utama_set(text, integer);

CREATE FUNCTION public.admin_barang_katalog(p_kata text DEFAULT '')
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
  v_q text := lower(btrim(COALESCE(p_kata, '')));
  v_buku bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
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
    b.jual_strat_5,
    b.pengurang_strata,
    b.aktif,
    b.id_supplier_utama
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> ''
    AND (
      v_q = ''
      OR lower(b.nama_barang) LIKE '%' || v_q || '%'
      OR lower(b.id_barang) LIKE '%' || v_q || '%'
      OR lower(COALESCE(b.kategori, '')) LIKE '%' || v_q || '%'
    )
  ORDER BY b.aktif DESC, lower(b.nama_barang), b.id_barang
  LIMIT 8000;
END;
$$;

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
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
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
    b.jual_strat_5,
    b.pengurang_strata,
    b.aktif,
    b.id_supplier_utama
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE btrim(b.id_barang) <> ''
  ORDER BY lower(b.id_barang);
END;
$$;

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
  v_min1 integer;
  v_min2 integer;
  v_min3 integer;
  v_min4 integer;
  v_min5 integer;
  v_jual1 integer;
  v_jual2 integer;
  v_jual3 integer;
  v_jual4 integer;
  v_jual5 integer;
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
   AND lower(h.kode_barang) = lower(b.id_barang)
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

  IF (v_min1 > 0 OR v_min2 > 0 OR v_min3 > 0 OR v_min4 > 0 OR v_min5 > 0)
     AND v_pengurang <= 0 THEN
    RAISE EXCEPTION 'Nilai pengurang wajib diisi jika strata dipakai.';
  END IF;

  v_jual1 := CASE WHEN v_min1 > 0 THEN v_jual - (v_pengurang * 1) ELSE 0 END;
  v_jual2 := CASE WHEN v_min2 > 0 THEN v_jual - (v_pengurang * 2) ELSE 0 END;
  v_jual3 := CASE WHEN v_min3 > 0 THEN v_jual - (v_pengurang * 3) ELSE 0 END;
  v_jual4 := CASE WHEN v_min4 > 0 THEN v_jual - (v_pengurang * 4) ELSE 0 END;
  v_jual5 := CASE WHEN v_min5 > 0 THEN v_jual - (v_pengurang * 5) ELSE 0 END;

  IF (v_min1 > 0 AND v_jual1 <= v_beli)
     OR (v_min2 > 0 AND v_jual2 <= v_beli)
     OR (v_min3 > 0 AND v_jual3 <= v_beli)
     OR (v_min4 > 0 AND v_jual4 <= v_beli)
     OR (v_min5 > 0 AND v_jual5 <= v_beli) THEN
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
    min_strat_1 = v_min1,
    jual_strat_1 = GREATEST(0, v_jual1),
    min_strat_2 = v_min2,
    jual_strat_2 = GREATEST(0, v_jual2),
    min_strat_3 = v_min3,
    jual_strat_3 = GREATEST(0, v_jual3),
    min_strat_4 = v_min4,
    jual_strat_4 = GREATEST(0, v_jual4),
    min_strat_5 = v_min5,
    jual_strat_5 = GREATEST(0, v_jual5),
    aktif = COALESCE((p_barang->>'aktif')::boolean, true)
  WHERE lower(b.id_barang) = lower(v_id);

  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
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
    b.jual_strat_5,
    b.pengurang_strata,
    b.aktif,
    b.id_supplier_utama
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE lower(b.id_barang) = lower(v_id);
END;
$$;

CREATE FUNCTION public.admin_barang_stok(p_id_barang text, p_stok numeric)
RETURNS TABLE (
  id_barang text,
  stok numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_lama numeric;
  v_baru numeric;
  v_buku bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  v_id := btrim(COALESCE(p_id_barang, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'Id barang wajib diisi.';
  END IF;
  IF p_stok IS NULL OR p_stok < 0 THEN
    RAISE EXCEPTION 'Stok tidak boleh minus.';
  END IF;
  v_baru := round(p_stok, 4);

  SELECT b.id_barang, b.stok INTO v_id, v_lama
  FROM public.barang b
  WHERE lower(b.id_barang) = lower(v_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Barang tidak ada.';
  END IF;

  IF v_lama IS DISTINCT FROM v_baru THEN
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang b
    SET stok = v_baru
    WHERE b.id_barang = v_id;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NOT NULL THEN
    UPDATE public.stok_opname so
    SET stok_awal = GREATEST(0, v_baru)
    WHERE so.id_setoran_buku = v_buku
      AND lower(so.id_barang) = lower(v_id)
      AND so.stok_fisik IS NULL;
  END IF;

  RETURN QUERY
  SELECT b.id_barang, b.stok
  FROM public.barang b
  WHERE b.id_barang = v_id;
END;
$$;

CREATE FUNCTION public.admin_barang_csv(p_baris jsonb)
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
          WHERE lower(h.kode_barang) = lower(v_id);
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

CREATE FUNCTION public.admin_barang_stok_csv(p_baris jsonb)
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
  v_stok numeric;
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
    aksi := 'stok';
    ok := false;
    pesan := '';
    BEGIN
      IF id_barang = '' THEN
        RAISE EXCEPTION 'Id barang wajib diisi.';
      END IF;
      IF v_e->'stok' IS NULL OR v_e->>'stok' = '' THEN
        RAISE EXCEPTION 'Stok wajib diisi.';
      END IF;
      v_teks := replace(btrim(v_e->>'stok'), ',', '.');
      v_stok := v_teks::numeric;
      PERFORM * FROM public.admin_barang_stok(id_barang, v_stok);
      ok := true;
      pesan := 'Stok disimpan.';
    EXCEPTION WHEN OTHERS THEN
      ok := false;
      pesan := SQLERRM;
    END;
    RETURN NEXT;
  END LOOP;
END;
$$;

CREATE FUNCTION public.admin_barang_pemasok_lihat(p_id_barang text)
RETURNS TABLE (
  id_supplier integer,
  nama_supplier text,
  harga_beli integer,
  utama boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_utama integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RETURN;
  END IF;
  v_id := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  SELECT b.id_supplier_utama INTO v_utama
  FROM public.barang b
  WHERE lower(b.id_barang) = lower(v_id);

  RETURN QUERY
  SELECT
    h.id_supplier,
    COALESCE(NULLIF(btrim(s.nama), ''), 'Supplier'),
    h.harga_beli,
    (v_utama IS NOT NULL AND h.id_supplier = v_utama)
  FROM public.supplier_harga h
  JOIN public.supplier s ON s.id = h.id_supplier
  WHERE lower(h.kode_barang) = lower(v_id)
    AND s.aktif
  ORDER BY (v_utama IS NOT NULL AND h.id_supplier = v_utama) DESC,
    lower(s.nama),
    h.id_supplier;
END;
$$;

CREATE FUNCTION public.admin_barang_utama_lihat(p_id_barang text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RETURN NULL;
  END IF;
  SELECT b.id_supplier_utama INTO v
  FROM public.barang b
  WHERE lower(b.id_barang) = lower(btrim(COALESCE(p_id_barang, '')));
  RETURN v;
END;
$$;

CREATE FUNCTION public.admin_barang_utama_set(
  p_id_barang text,
  p_id_supplier integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RETURN false;
  END IF;
  v_id := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF v_id IS NULL THEN
    RETURN false;
  END IF;
  IF p_id_supplier IS NOT NULL AND p_id_supplier > 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.supplier s
      WHERE s.id = p_id_supplier AND s.aktif
    ) THEN
      RETURN false;
    END IF;
  END IF;
  UPDATE public.barang b
  SET id_supplier_utama = CASE
    WHEN p_id_supplier IS NULL OR p_id_supplier <= 0 THEN NULL
    ELSE p_id_supplier
  END
  WHERE lower(b.id_barang) = lower(v_id);
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF p_id_supplier IS NOT NULL AND p_id_supplier > 0 THEN
    PERFORM public.barang_modal_dari_utama(v_id);
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.bulat_500(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.skala_harga_beli(integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.barang_ikut_modal(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.barang_modal_dari_utama(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulat_500(integer) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.skala_harga_beli(integer, integer, integer)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.barang_ikut_modal(text, integer)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.barang_modal_dari_utama(text)
  TO postgres, service_role;

REVOKE ALL ON FUNCTION public.admin_barang_katalog(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_semua() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_simpan(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_stok(text, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_csv(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_stok_csv(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_pemasok_lihat(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_utama_lihat(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_barang_utama_set(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_barang_katalog(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_semua()
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_simpan(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_stok(text, numeric)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_csv(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_stok_csv(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_pemasok_lihat(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_utama_lihat(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_utama_set(text, integer)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_cari(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_cari(text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
