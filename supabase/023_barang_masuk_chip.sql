-- Ringkas per supplier: sku, nilai, ongkir. Jalankan SETELAH 022. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_barang_masuk_ringkas()
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
  v_sku integer := 0;
  v_nilai bigint := 0;
  v_ongkir bigint := 0;
  v_supplier jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();
  SELECT
    count(*)::integer,
    coalesce(sum(m.nilai), 0)::bigint
  INTO v_sku, v_nilai
  FROM public.barang_masuk m
  WHERE (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
     OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl);

  SELECT coalesce(sum(o.jumlah), 0)::bigint
  INTO v_ongkir
  FROM public.ongkir o
  WHERE (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
     OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl);

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
      SELECT m.id_supplier
      FROM public.barang_masuk m
      WHERE (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
         OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl)
      UNION
      SELECT o.id_supplier
      FROM public.ongkir o
      WHERE (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
         OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl)
    ) ids
    JOIN public.supplier s ON s.id = ids.id_supplier
    LEFT JOIN LATERAL (
      SELECT
        count(*)::integer AS sku,
        coalesce(sum(mm.nilai), 0)::bigint AS nilai
      FROM public.barang_masuk mm
      WHERE mm.id_supplier = s.id
        AND (
          (v_buku IS NOT NULL AND mm.id_setoran_buku = v_buku)
          OR (v_buku IS NULL AND mm.id_setoran_buku IS NULL AND mm.tanggal = v_tgl)
        )
    ) m ON true
    LEFT JOIN LATERAL (
      SELECT oo.jumlah
      FROM public.ongkir oo
      WHERE oo.id_supplier = s.id
        AND (
          (v_buku IS NOT NULL AND oo.id_setoran_buku = v_buku)
          OR (v_buku IS NULL AND oo.id_setoran_buku IS NULL AND oo.tanggal = v_tgl)
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

NOTIFY pgrst, 'reload schema';
