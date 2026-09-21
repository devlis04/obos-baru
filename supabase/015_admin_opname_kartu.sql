-- Kartu opname admin. Jalankan SETELAH 014. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_opname_ringkas()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_total integer := 0;
  v_fisik integer := 0;
  v_selisih integer := 0;
  v_nilai bigint := 0;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    ORDER BY b.id DESC
    LIMIT 1;
  ELSE
    SELECT b.tanggal, b.ditutup
    INTO v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_id;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'sku_total', 0,
      'sku_fisik', 0,
      'sku_selisih', 0,
      'nilai_selisih', 0
    );
  END IF;

  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer,
    count(*) FILTER (
      WHERE so.stok_fisik IS NOT NULL AND COALESCE(so.selisih, 0) <> 0
    )::integer,
    coalesce(sum(
      CASE
        WHEN so.stok_fisik IS NULL THEN 0
        ELSE round(COALESCE(so.selisih, 0) * COALESCE(b.harga_beli, 0))
      END
    ), 0)::bigint
  INTO v_total, v_fisik, v_selisih, v_nilai
  FROM public.stok_opname so
  LEFT JOIN public.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = v_id;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', COALESCE(v_tutup, false),
    'sku_total', v_total,
    'sku_fisik', v_fisik,
    'sku_selisih', v_selisih,
    'nilai_selisih', v_nilai
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_opname_lihat(p_id_setoran_buku bigint)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  stok_awal numeric,
  qty_packed numeric,
  stok_hitung numeric,
  stok_fisik numeric,
  selisih numeric,
  nilai_selisih integer,
  harga_beli integer,
  dicek_stok_oleh text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_id_setoran_buku IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    so.id_barang,
    so.nama_barang,
    so.stok_awal,
    so.qty_packed,
    so.stok_hitung,
    so.stok_fisik,
    so.selisih,
    round(COALESCE(so.selisih, 0) * COALESCE(b.harga_beli, 0))::integer,
    COALESCE(b.harga_beli, 0),
    so.dicek_stok_oleh
  FROM public.stok_opname so
  LEFT JOIN public.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = p_id_setoran_buku
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) <> 0
  ORDER BY lower(so.nama_barang), so.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_opname_ringkas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_opname_ringkas()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_opname_lihat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_opname_lihat(bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
