-- Buku ditutup: chip supplier tetap tampil (cap buku itu).
-- Yatim (21/09 atau hari ini) diikat ke buku terbuka, atau buku terakhir jika sudah ditutup.
-- Lihat rincian ikut p_id_setoran_buku. Jalankan SETELAH 078. Boleh diulang.

DO $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hari date;
BEGIN
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  SELECT b.id, b.tanggal INTO v_id, v_tgl
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;
  IF v_id IS NULL THEN
    SELECT b.id, b.tanggal INTO v_id, v_tgl
    FROM public.setoran_buku b
    ORDER BY b.id DESC
    LIMIT 1;
  END IF;
  IF v_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.barang_masuk a
  SET
    qty = a.qty + b.qty,
    nilai = a.nilai + b.nilai
  FROM public.barang_masuk b
  WHERE a.id_setoran_buku = v_id
    AND b.id_setoran_buku IS NULL
    AND b.tanggal IN (v_tgl, v_hari)
    AND a.id_supplier = b.id_supplier
    AND a.id_barang = b.id_barang;

  DELETE FROM public.barang_masuk b
  WHERE b.id_setoran_buku IS NULL
    AND b.tanggal IN (v_tgl, v_hari)
    AND EXISTS (
      SELECT 1
      FROM public.barang_masuk a
      WHERE a.id_setoran_buku = v_id
        AND a.id_supplier = b.id_supplier
        AND a.id_barang = b.id_barang
    );

  UPDATE public.barang_masuk
  SET id_setoran_buku = v_id
  WHERE id_setoran_buku IS NULL
    AND tanggal IN (v_tgl, v_hari);

  UPDATE public.ongkir a
  SET jumlah = a.jumlah + b.jumlah
  FROM public.ongkir b
  WHERE a.id_setoran_buku = v_id
    AND b.id_setoran_buku IS NULL
    AND b.tanggal IN (v_tgl, v_hari)
    AND a.id_supplier = b.id_supplier;

  DELETE FROM public.ongkir b
  WHERE b.id_setoran_buku IS NULL
    AND b.tanggal IN (v_tgl, v_hari)
    AND EXISTS (
      SELECT 1
      FROM public.ongkir a
      WHERE a.id_setoran_buku = v_id
        AND a.id_supplier = b.id_supplier
    );

  UPDATE public.ongkir
  SET id_setoran_buku = v_id
  WHERE id_setoran_buku IS NULL
    AND tanggal IN (v_tgl, v_hari);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_barang_masuk_lihat(integer);
CREATE FUNCTION public.admin_barang_masuk_lihat(
  p_id_supplier integer,
  p_id_setoran_buku bigint DEFAULT NULL
)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  qty numeric,
  nilai integer,
  harga_beli integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_tutup boolean := false;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RETURN;
  END IF;
  IF p_id_setoran_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup INTO v_buku, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = p_id_setoran_buku;
  ELSE
    SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();
  END IF;
  RETURN QUERY
  SELECT
    m.id_barang,
    b.nama_barang,
    m.qty,
    m.nilai,
    CASE WHEN m.qty > 0 THEN round(m.nilai / m.qty)::integer ELSE COALESCE(h.harga_beli, 0) END
  FROM public.barang_masuk m
  JOIN public.barang b ON b.id_barang = m.id_barang
  LEFT JOIN public.supplier_harga h
    ON h.id_supplier = m.id_supplier AND h.id_barang = m.id_barang
  WHERE m.id_supplier = p_id_supplier
    AND public.barang_masuk_di_kartu(
      v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal
    )
  ORDER BY lower(b.nama_barang);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_ongkir_lihat_supplier(integer);
CREATE FUNCTION public.admin_ongkir_lihat_supplier(
  p_id_supplier integer,
  p_id_setoran_buku bigint DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_tutup boolean := false;
  v integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RETURN 0;
  END IF;
  IF p_id_setoran_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup INTO v_buku, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = p_id_setoran_buku;
  ELSE
    SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();
  END IF;
  SELECT coalesce(sum(o.jumlah), 0)::integer INTO v
  FROM public.ongkir o
  WHERE o.id_supplier = p_id_supplier
    AND public.barang_masuk_di_kartu(
      v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal
    );
  RETURN COALESCE(v, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_barang_masuk_lihat(integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_lihat(integer, bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_ongkir_lihat_supplier(integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_ongkir_lihat_supplier(integer, bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
