-- Kartu barang masuk: ikut baris tanggal buku yang belum terikat id buku
-- (mis. input dari app lama). Ikatkan ke buku terbuka. Jalankan di SQL Editor.

CREATE OR REPLACE FUNCTION public.barang_masuk_di_kartu(
  p_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_buku bigint,
  p_tgl_baris date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (p_buku IS NOT NULL AND p_id_buku = p_buku)
    OR (
      COALESCE(p_tutup, false) = false
      AND p_id_buku IS NULL
      AND p_tgl_baris = p_tgl
    );
$$;

-- Ikatkan barang_masuk/ongkir yatim ke buku yang masih terbuka.
DO $$
DECLARE
  v_id bigint;
  v_tgl date;
BEGIN
  SELECT b.id, b.tanggal INTO v_id, v_tgl
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  LIMIT 1;
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
    AND b.tanggal = v_tgl
    AND a.id_supplier = b.id_supplier
    AND a.id_barang = b.id_barang;

  DELETE FROM public.barang_masuk b
  WHERE b.id_setoran_buku IS NULL
    AND b.tanggal = v_tgl
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
    AND tanggal = v_tgl;

  UPDATE public.ongkir a
  SET jumlah = a.jumlah + b.jumlah
  FROM public.ongkir b
  WHERE a.id_setoran_buku = v_id
    AND b.id_setoran_buku IS NULL
    AND b.tanggal = v_tgl
    AND a.id_supplier = b.id_supplier;

  DELETE FROM public.ongkir b
  WHERE b.id_setoran_buku IS NULL
    AND b.tanggal = v_tgl
    AND EXISTS (
      SELECT 1
      FROM public.ongkir a
      WHERE a.id_setoran_buku = v_id
        AND a.id_supplier = b.id_supplier
    );

  UPDATE public.ongkir
  SET id_setoran_buku = v_id
  WHERE id_setoran_buku IS NULL
    AND tanggal = v_tgl;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_masuk_ringkas(
  p_id_setoran_buku bigint DEFAULT NULL
)
RETURNS jsonb
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
  v_sku integer := 0;
  v_nilai bigint := 0;
  v_ongkir bigint := 0;
  v_supplier jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  IF p_id_setoran_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup INTO v_buku, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = p_id_setoran_buku;
  ELSE
    SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();
    v_tutup := false;
  END IF;

  SELECT
    count(*)::integer,
    coalesce(sum(m.nilai), 0)::bigint
  INTO v_sku, v_nilai
  FROM public.barang_masuk m
  WHERE public.barang_masuk_di_kartu(v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal);

  SELECT coalesce(sum(o.jumlah), 0)::bigint
  INTO v_ongkir
  FROM public.ongkir o
  WHERE public.barang_masuk_di_kartu(v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal);

  SELECT coalesce(jsonb_agg(x.obj ORDER BY lower(x.nama)), '[]'::jsonb)
  INTO v_supplier
  FROM (
    SELECT
      jsonb_build_object(
        'id', s.id,
        'nama', s.nama,
        'sku', coalesce(m.sku, 0),
        'nilai', coalesce(m.nilai, 0),
        'ongkir', coalesce(o.jumlah, 0)
      ) AS obj,
      s.nama
    FROM (
      SELECT DISTINCT m.id_supplier
      FROM public.barang_masuk m
      WHERE public.barang_masuk_di_kartu(
        v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal
      )
      UNION
      SELECT DISTINCT o.id_supplier
      FROM public.ongkir o
      WHERE public.barang_masuk_di_kartu(
        v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal
      )
    ) ids
    JOIN public.supplier s ON s.id = ids.id_supplier
    LEFT JOIN LATERAL (
      SELECT
        count(*)::integer AS sku,
        coalesce(sum(mm.nilai), 0)::bigint AS nilai
      FROM public.barang_masuk mm
      WHERE mm.id_supplier = s.id
        AND public.barang_masuk_di_kartu(
          v_buku, v_tgl, v_tutup, mm.id_setoran_buku, mm.tanggal
        )
    ) m ON true
    LEFT JOIN LATERAL (
      SELECT coalesce(sum(oo.jumlah), 0)::bigint AS jumlah
      FROM public.ongkir oo
      WHERE oo.id_supplier = s.id
        AND public.barang_masuk_di_kartu(
          v_buku, v_tgl, v_tutup, oo.id_setoran_buku, oo.tanggal
        )
    ) o ON true
  ) x;

  RETURN jsonb_build_object(
    'ada_buku', v_buku IS NOT NULL,
    'id_setoran_buku', v_buku,
    'tanggal', v_tgl,
    'sku', v_sku,
    'nilai', v_nilai,
    'ongkir', v_ongkir,
    'supplier', v_supplier
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_masuk_lihat(p_id_supplier integer)
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
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RETURN;
  END IF;
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();
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
      v_buku, v_tgl, false, m.id_setoran_buku, m.tanggal
    )
  ORDER BY lower(b.nama_barang);
END;
$$;

REVOKE ALL ON FUNCTION public.barang_masuk_di_kartu(bigint, date, boolean, bigint, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.barang_masuk_di_kartu(bigint, date, boolean, bigint, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_masuk_ringkas(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_ringkas(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_masuk_lihat(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_lihat(integer)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_barang_masuk_ringkas(bigint) IS
  'Ringkas barang masuk buku: termasuk baris tanggal yang belum terikat id buku.';

NOTIFY pgrst, 'reload schema';
