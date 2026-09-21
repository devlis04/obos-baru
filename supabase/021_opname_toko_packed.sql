-- Toko yang packed SKU di buku yang sama, untuk dialog selisih admin.
-- Jalankan SETELAH 020. Boleh diulang.

DROP FUNCTION IF EXISTS public.admin_opname_lihat(bigint);

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
  dicek_stok_oleh text,
  putusan text,
  kasbon_email text,
  kasbon_nama text,
  nilai_putusan integer,
  toko_packed jsonb
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
    so.dicek_stok_oleh,
    so.putusan,
    so.kasbon_email,
    so.kasbon_nama,
    so.nilai_putusan,
    COALESCE(p.toko, '[]'::jsonb)
  FROM public.stok_opname so
  LEFT JOIN public.barang b ON b.id_barang = so.id_barang
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id_pelanggan', x.id_pelanggan,
        'nama', x.nama_pelanggan,
        'qty', x.qty
      )
      ORDER BY lower(x.nama_pelanggan)
    ) AS toko
    FROM (
      SELECT
        t.id_pelanggan,
        max(t.nama_pelanggan) AS nama_pelanggan,
        sum(COALESCE(i.qty_packed, 0))::numeric AS qty
      FROM public.transaksi t
      JOIN public.transaksi_items i ON i.id_transaksi = t.id_transaksi
      WHERE t.id_setoran_buku = p_id_setoran_buku
        AND i.id_barang = so.id_barang
        AND COALESCE(i.qty_packed, 0) > 0
      GROUP BY t.id_pelanggan
    ) x
  ) p ON true
  WHERE so.id_setoran_buku = p_id_setoran_buku
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) <> 0
  ORDER BY
    CASE WHEN COALESCE(so.selisih, 0) < 0 THEN 0 ELSE 1 END,
    lower(so.nama_barang),
    so.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_opname_lihat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_opname_lihat(bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
