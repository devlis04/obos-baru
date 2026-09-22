-- Chip barang masuk ikut buku yang sedang dilihat (terbuka ATAU terakhir
-- yang sudah ditutup). 079 tidak cukup: ringkas masih memakai lingkup
-- buku terbuka saja, jadi setelah tutup kartu kosong.
-- Yatim semua tanggal diikat ke buku itu (gabung SKU dobel).
-- Jalankan SETELAH 079. Boleh diulang. Jangan jalankan 055/078 setelah ini.

CREATE OR REPLACE FUNCTION public.barang_masuk_di_kartu(
  p_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_buku bigint,
  p_tgl_baris date
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    (p_buku IS NOT NULL AND p_id_buku = p_buku)
    OR (
      COALESCE(p_tutup, false) = false
      AND p_id_buku IS NULL
    );
$$;

DO $$
DECLARE
  v_id bigint;
  v_tgl date;
BEGIN
  SELECT x.id, x.tanggal INTO v_id, v_tgl
  FROM public.admin_buku_lihat(NULL) x;
  IF v_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.barang_masuk a
  SET
    qty = a.qty + x.qty,
    nilai = a.nilai + x.nilai
  FROM (
    SELECT id_supplier, id_barang, sum(qty) AS qty, sum(nilai)::integer AS nilai
    FROM public.barang_masuk
    WHERE id_setoran_buku IS NULL
    GROUP BY id_supplier, id_barang
  ) x
  WHERE a.id_setoran_buku = v_id
    AND a.id_supplier = x.id_supplier
    AND a.id_barang = x.id_barang;

  DELETE FROM public.barang_masuk b
  WHERE b.id_setoran_buku IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.barang_masuk a
      WHERE a.id_setoran_buku = v_id
        AND a.id_supplier = b.id_supplier
        AND a.id_barang = b.id_barang
    );

  UPDATE public.barang_masuk a
  SET
    qty = d.qty,
    nilai = d.nilai,
    tanggal = v_tgl,
    id_setoran_buku = v_id
  FROM (
    SELECT
      min(id) AS keep,
      sum(qty) AS qty,
      sum(nilai)::integer AS nilai
    FROM public.barang_masuk
    WHERE id_setoran_buku IS NULL
    GROUP BY id_supplier, id_barang
  ) d
  WHERE a.id = d.keep;

  DELETE FROM public.barang_masuk
  WHERE id_setoran_buku IS NULL;

  UPDATE public.ongkir a
  SET jumlah = a.jumlah + x.jumlah
  FROM (
    SELECT id_supplier, sum(jumlah)::integer AS jumlah
    FROM public.ongkir
    WHERE id_setoran_buku IS NULL
    GROUP BY id_supplier
  ) x
  WHERE a.id_setoran_buku = v_id
    AND a.id_supplier = x.id_supplier;

  DELETE FROM public.ongkir b
  WHERE b.id_setoran_buku IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.ongkir a
      WHERE a.id_setoran_buku = v_id
        AND a.id_supplier = b.id_supplier
    );

  UPDATE public.ongkir a
  SET
    jumlah = d.jumlah,
    tanggal = v_tgl,
    id_setoran_buku = v_id
  FROM (
    SELECT min(id) AS keep, sum(jumlah)::integer AS jumlah
    FROM public.ongkir
    WHERE id_setoran_buku IS NULL
    GROUP BY id_supplier
  ) d
  WHERE a.id = d.keep;

  DELETE FROM public.ongkir
  WHERE id_setoran_buku IS NULL;
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

  SELECT x.id, x.tanggal, x.ditutup
  INTO v_buku, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  SELECT
    count(*)::integer,
    coalesce(sum(m.nilai), 0)::bigint
  INTO v_sku, v_nilai
  FROM public.barang_masuk m
  WHERE public.barang_masuk_di_kartu(
    v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal
  );

  SELECT coalesce(sum(o.jumlah), 0)::bigint
  INTO v_ongkir
  FROM public.ongkir o
  WHERE public.barang_masuk_di_kartu(
    v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal
  );

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

DROP FUNCTION IF EXISTS public.admin_barang_masuk_lihat(integer);
DROP FUNCTION IF EXISTS public.admin_barang_masuk_lihat(integer, bigint);
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
  SELECT x.id, x.tanggal, x.ditutup
  INTO v_buku, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;
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
DROP FUNCTION IF EXISTS public.admin_ongkir_lihat_supplier(integer, bigint);
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
  SELECT x.id, x.tanggal, x.ditutup
  INTO v_buku, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;
  SELECT coalesce(sum(o.jumlah), 0)::integer INTO v
  FROM public.ongkir o
  WHERE o.id_supplier = p_id_supplier
    AND public.barang_masuk_di_kartu(
      v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal
    );
  RETURN COALESCE(v, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.barang_masuk_di_kartu(bigint, date, boolean, bigint, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.barang_masuk_di_kartu(bigint, date, boolean, bigint, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_masuk_ringkas(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_ringkas(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_masuk_lihat(integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_lihat(integer, bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_ongkir_lihat_supplier(integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_ongkir_lihat_supplier(integer, bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
