-- Isi stok fisik dari app gudang. Tidak menutup buku, tidak menulis barang.stok.
-- Jalankan SETELAH 017. Boleh diulang.

CREATE OR REPLACE FUNCTION public.gudang_buku_isi()
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  stok_awal numeric,
  qty_packed numeric,
  stok_hitung numeric,
  stok_fisik numeric,
  selisih numeric,
  jumlah_bagian integer,
  id_setoran_buku bigint,
  dicek_stok_oleh text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_bagian integer;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.gudang_id_absensi_saya() IS NULL THEN
    RETURN;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RETURN;
  END IF;

  SELECT GREATEST(1, count(*)::integer)
  INTO v_bagian
  FROM public.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'admin');

  RETURN QUERY
  SELECT
    so.id_barang,
    so.nama_barang,
    so.stok_awal,
    so.qty_packed,
    so.stok_hitung,
    so.stok_fisik,
    so.selisih,
    v_bagian,
    so.id_setoran_buku,
    so.dicek_stok_oleh
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_buku
  ORDER BY lower(so.nama_barang), so.id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_simpan_opname(p_baris jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_sku text;
  v_email text;
  v_nama text;
  v_ditulis integer := 0;
  v_total integer := 0;
  v_kurang integer := 0;
  v_terisi integer := 0;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.gudang_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka. Scan masuk gudang dulu.';
  END IF;

  v_email := lower(btrim(COALESCE(auth.jwt() ->> 'email', '')));
  SELECT nullif(btrim(u.nama), '')
  INTO v_nama
  FROM public.users u
  WHERE lower(btrim(u.email)) = v_email
  LIMIT 1;
  v_nama := COALESCE(nullif(btrim(COALESCE(v_nama, '')), ''), v_email);
  IF v_nama = '' THEN
    RAISE EXCEPTION 'Nama petugas tidak terbaca.';
  END IF;

  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar stok fisik wajib.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_baris) e
    WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
  ) THEN
    SELECT btrim(e ->> 'id_barang')
    INTO v_sku
    FROM jsonb_array_elements(p_baris) e
    WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
      AND (
        e -> 'stok_fisik' IS NULL
        OR jsonb_typeof(e -> 'stok_fisik') = 'null'
        OR btrim(COALESCE(e ->> 'stok_fisik', '')) = ''
      )
    LIMIT 1;
    IF v_sku IS NOT NULL THEN
      RAISE EXCEPTION 'stok_fisik wajib untuk SKU %.', v_sku;
    END IF;

    SELECT btrim(e ->> 'id_barang')
    INTO v_sku
    FROM jsonb_array_elements(p_baris) e
    WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
      AND round(replace(btrim(e ->> 'stok_fisik'), ',', '.')::numeric, 4) < 0
    LIMIT 1;
    IF v_sku IS NOT NULL THEN
      RAISE EXCEPTION 'stok_fisik tidak boleh negatif (SKU %).', v_sku;
    END IF;

    SELECT btrim(e ->> 'id_barang')
    INTO v_sku
    FROM jsonb_array_elements(p_baris) e
    WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
      AND NOT EXISTS (
        SELECT 1
        FROM public.stok_opname so
        WHERE so.id_setoran_buku = v_buku
          AND so.id_barang = btrim(e ->> 'id_barang')
      )
    LIMIT 1;
    IF v_sku IS NOT NULL THEN
      RAISE EXCEPTION 'SKU % tidak ada di buku terbuka.', v_sku;
    END IF;

    UPDATE public.stok_opname so
    SET
      stok_fisik = v.fisik,
      dicek_stok_oleh = v_nama
    FROM (
      SELECT DISTINCT ON (btrim(e ->> 'id_barang'))
        btrim(e ->> 'id_barang') AS id_barang,
        round(replace(btrim(e ->> 'stok_fisik'), ',', '.')::numeric, 4) AS fisik
      FROM jsonb_array_elements(p_baris) e
      WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
      ORDER BY btrim(e ->> 'id_barang')
    ) v
    WHERE so.id_setoran_buku = v_buku
      AND so.id_barang = v.id_barang;
    GET DIAGNOSTICS v_ditulis = ROW_COUNT;
  END IF;

  SELECT
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE stok_fisik IS NULL)::integer
  INTO v_total, v_kurang
  FROM public.stok_opname
  WHERE id_setoran_buku = v_buku;
  v_terisi := v_total - v_kurang;

  RETURN jsonb_build_object(
    'ditutup', false,
    'ditulis', v_ditulis,
    'terisi', v_terisi,
    'total', v_total,
    'kurang', v_kurang
  );
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_buku_isi() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_buku_isi()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_simpan_opname(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_simpan_opname(jsonb)
  TO authenticated, postgres, service_role;

COMMENT ON COLUMN public.stok_opname.dicek_stok_oleh IS
  'Nama petugas yang mengisi stok_fisik baris ini.';

UPDATE public.stok_opname so
SET dicek_stok_oleh = btrim(u.nama)
FROM public.users u
WHERE so.dicek_stok_oleh IS NOT NULL
  AND btrim(so.dicek_stok_oleh) <> ''
  AND lower(btrim(u.email)) = lower(btrim(so.dicek_stok_oleh))
  AND btrim(u.nama) <> '';

NOTIFY pgrst, 'reload schema';
