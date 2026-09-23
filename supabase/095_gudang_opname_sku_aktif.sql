-- Opname gudang: SKU nonaktif (barang.aktif = false) tidak tampil, tidak dihitung
-- kurang fisik, tidak di-snapshot buku baru.
-- Jalankan SETELAH 094. SQL Editor → Run. Boleh di-Run ulang.
-- Tidak menutup buku, tidak mengubah stok_fisik yang sudah terisi.

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
  LEFT JOIN public.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = v_buku
    AND COALESCE(b.aktif, true)
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
      AND EXISTS (
        SELECT 1
        FROM public.stok_opname so
        LEFT JOIN public.barang b ON b.id_barang = so.id_barang
        WHERE so.id_setoran_buku = v_buku
          AND so.id_barang = btrim(e ->> 'id_barang')
          AND COALESCE(b.aktif, true)
      )
  ) THEN
    SELECT btrim(e ->> 'id_barang')
    INTO v_sku
    FROM jsonb_array_elements(p_baris) e
    WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
      AND EXISTS (
        SELECT 1
        FROM public.stok_opname so
        LEFT JOIN public.barang b ON b.id_barang = so.id_barang
        WHERE so.id_setoran_buku = v_buku
          AND so.id_barang = btrim(e ->> 'id_barang')
          AND COALESCE(b.aktif, true)
      )
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
      AND EXISTS (
        SELECT 1
        FROM public.stok_opname so
        LEFT JOIN public.barang b ON b.id_barang = so.id_barang
        WHERE so.id_setoran_buku = v_buku
          AND so.id_barang = btrim(e ->> 'id_barang')
          AND COALESCE(b.aktif, true)
      )
      AND round(replace(btrim(e ->> 'stok_fisik'), ',', '.')::numeric, 4) < 0
    LIMIT 1;
    IF v_sku IS NOT NULL THEN
      RAISE EXCEPTION 'stok_fisik tidak boleh negatif (SKU %).', v_sku;
    END IF;

    SELECT btrim(e ->> 'id_barang')
    INTO v_sku
    FROM jsonb_array_elements(p_baris) e
    WHERE btrim(COALESCE(e ->> 'id_barang', '')) <> ''
      AND EXISTS (
        SELECT 1
        FROM public.stok_opname so
        LEFT JOIN public.barang b ON b.id_barang = so.id_barang
        WHERE so.id_setoran_buku = v_buku
          AND so.id_barang = btrim(e ->> 'id_barang')
          AND COALESCE(b.aktif, true)
      )
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
    LEFT JOIN public.barang b ON b.id_barang = v.id_barang
    WHERE so.id_setoran_buku = v_buku
      AND so.id_barang = v.id_barang
      AND COALESCE(b.aktif, true);
    GET DIAGNOSTICS v_ditulis = ROW_COUNT;
  END IF;

  SELECT
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE so.stok_fisik IS NULL)::integer
  INTO v_total, v_kurang
  FROM public.stok_opname so
  LEFT JOIN public.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = v_buku
    AND COALESCE(b.aktif, true);
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

CREATE OR REPLACE FUNCTION public.setoran_buka_jika_perlu()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_lama date;
  v_today date;
BEGIN
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_id := public.setoran_buku_terbuka();
  IF v_id IS NOT NULL THEN
    v_tgl := public.setoran_tanggal_order_sales(v_id);
    SELECT b.tanggal INTO v_lama
    FROM public.setoran_buku b
    WHERE b.id = v_id;
    IF EXISTS (SELECT 1 FROM public.setoran_buku x WHERE x.ditutup) THEN
      v_tgl := GREATEST(COALESCE(v_tgl, v_today), v_today);
    END IF;
    IF v_tgl IS NOT NULL AND v_lama IS DISTINCT FROM v_tgl THEN
      UPDATE public.setoran_buku
      SET tanggal = v_tgl
      WHERE id = v_id;
      UPDATE public.stok_opname
      SET tanggal = v_tgl
      WHERE id_setoran_buku = v_id;
    END IF;
    PERFORM public.setoran_pending_foto_pindah(v_id);
    RETURN v_id;
  END IF;

  v_tgl := public.setoran_tanggal_order_sales(NULL);

  INSERT INTO public.setoran_buku (tanggal, ditutup)
  VALUES (v_tgl, false)
  RETURNING id INTO v_id;

  INSERT INTO public.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
  )
  SELECT
    v_id,
    v_tgl,
    b.id_barang,
    b.nama_barang,
    GREATEST(COALESCE(b.stok, 0), 0),
    0
  FROM public.barang b
  WHERE btrim(b.id_barang) <> ''
    AND COALESCE(b.aktif, true);

  PERFORM public.setoran_pending_foto_pindah(v_id);
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_buku_isi() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_buku_isi()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_simpan_opname(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_simpan_opname(jsonb)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buka_jika_perlu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buka_jika_perlu()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
