-- Katalog CSV barang masuk. Jalankan SETELAH 022. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_barang_masuk_csv()
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  kategori text,
  harga_beli integer
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
  RETURN QUERY
  SELECT b.id_barang, b.nama_barang, coalesce(b.kategori, ''), b.harga_beli
  FROM public.barang b
  ORDER BY b.id_barang;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_barang_masuk_csv() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_csv()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
