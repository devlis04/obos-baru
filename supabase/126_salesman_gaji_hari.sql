-- Penggerak gaji sales untuk SATU hari (bukan gaji harian).
-- BOP/net dialokasi di server; hasil hanya rute login.
-- Jalankan SETELAH 125. Boleh diulang.

DROP FUNCTION IF EXISTS public.salesman_gaji_hari(date);

CREATE FUNCTION public.salesman_gaji_hari(p_hari date)
RETURNS TABLE (
  hari date,
  bop_aktual bigint,
  net_actual bigint,
  visit integer,
  ec integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
#variable_conflict use_column
DECLARE
  v_hari date;
  v_rute text;
  rec record;
  alokasi record;
  v_sisa bigint;
  v_n int;
  v_i int;
  v_v bigint;
  v_denom bigint;
  v_pool bigint;
  v_pas text;
  v_visit int;
  v_ec int;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun sales yang boleh melihat gaji ini.';
  END IF;
  IF p_hari IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong.';
  END IF;
  v_hari := p_hari;

  SELECT btrim(u.rute) INTO v_rute
  FROM public.users u
  WHERE u.peran = 'sales'
    AND lower(btrim(u.email)) = public.email_jwt()
  LIMIT 1;

  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Akun sales belum punya rute.';
  END IF;

  DROP TABLE IF EXISTS _sg_hari;
  CREATE TEMP TABLE _sg_hari (
    rute text PRIMARY KEY,
    pengirim text,
    mar_act bigint DEFAULT 0,
    retur_act bigint DEFAULT 0,
    bop_a bigint DEFAULT 0,
    ongkir_a bigint DEFAULT 0,
    selisih_a bigint DEFAULT 0
  ) ON COMMIT DROP;

  INSERT INTO _sg_hari (rute, pengirim)
  SELECT
    btrim(u.rute),
    coalesce(p.rute_pengirim, '')
  FROM public.users u
  LEFT JOIN LATERAL (
    SELECT btrim(rp.rute_pengirim) AS rute_pengirim
    FROM public.rute_peta rp
    WHERE btrim(rp.rute_sales) = btrim(u.rute)
      AND btrim(rp.rute_pengirim) <> ''
    ORDER BY btrim(rp.rute_pengirim)
    LIMIT 1
  ) p ON true
  WHERE u.peran = 'sales'
    AND nullif(btrim(u.rute), '') IS NOT NULL
  ON CONFLICT (rute) DO NOTHING;

  WITH uang AS (
    SELECT
      t.id_setoran_buku AS id_buku,
      btrim(t.rute) AS rute,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS omset,
      coalesce(sum(i.subtotal_beli_actual), 0)::bigint AS modal
    FROM public.transaksi t
    JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
    JOIN public.setoran_buku b ON b.id = t.id_setoran_buku
    WHERE t.status = 'terkirim'
      AND t.id_setoran_buku IS NOT NULL
      AND btrim(t.rute) <> ''
      AND b.tanggal = v_hari
    GROUP BY t.id_setoran_buku, btrim(t.rute)
  ),
  retur AS (
    SELECT
      r.id_setoran_buku AS id_buku,
      btrim(r.rute_sales) AS rute,
      coalesce(sum(
        (r.qty::bigint * r.harga_jual::bigint)
        - (r.qty::bigint * coalesce(beli.harga_beli, 0)::bigint)
      ), 0)::bigint AS margin_retur
    FROM public.retur_toko r
    JOIN public.setoran_buku b ON b.id = r.id_setoran_buku
    LEFT JOIN LATERAL (
      SELECT i.harga_beli
      FROM public.transaksi t
      JOIN public.transaksi_items i ON i.id_transaksi = t.id_transaksi
      WHERE t.id_setoran_buku = r.id_setoran_buku
        AND i.id_barang = r.kode_barang
      ORDER BY
        CASE WHEN t.id_pelanggan = r.id_pelanggan THEN 0 ELSE 1 END,
        i.id DESC
      LIMIT 1
    ) beli ON true
    WHERE btrim(COALESCE(r.rute_sales, '')) <> ''
      AND b.tanggal = v_hari
    GROUP BY r.id_setoran_buku, btrim(r.rute_sales)
  ),
  gabung AS (
    SELECT
      coalesce(u.rute, rt.rute) AS rute,
      (coalesce(u.omset, 0) - coalesce(u.modal, 0))::bigint AS margin,
      coalesce(rt.margin_retur, 0)::bigint AS margin_retur
    FROM uang u
    FULL JOIN retur rt ON rt.id_buku = u.id_buku AND rt.rute = u.rute
  ),
  tot AS (
    SELECT gabung.rute AS kode, sum(margin) AS margin, sum(margin_retur) AS margin_retur
    FROM gabung
    GROUP BY gabung.rute
  )
  UPDATE _sg_hari d
  SET
    mar_act = coalesce(t.margin, 0),
    retur_act = coalesce(t.margin_retur, 0)
  FROM tot t
  WHERE t.kode = d.rute;

  FOR rec IN
    SELECT
      btrim(s.rute_pengirim) AS pengirim,
      coalesce(sum(s.jumlah_bop::bigint), 0) AS pool
    FROM public.setoran_pengirim s
    JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
    WHERE b.tanggal = v_hari
      AND btrim(s.rute_pengirim) <> ''
    GROUP BY btrim(s.rute_pengirim)
  LOOP
    v_pas := rec.pengirim;
    v_pool := rec.pool;
    SELECT coalesce(sum(mar_act - retur_act), 0), count(*)
    INTO v_denom, v_n
    FROM _sg_hari WHERE pengirim = v_pas;
    v_sisa := v_pool;
    v_i := 0;
    FOR alokasi IN
      SELECT * FROM _sg_hari d WHERE d.pengirim = v_pas ORDER BY d.rute
    LOOP
      v_i := v_i + 1;
      IF v_i = v_n THEN
        v_v := v_sisa;
      ELSIF v_denom <= 0 THEN
        v_v := v_pool / GREATEST(v_n, 1);
      ELSE
        v_v := round(((alokasi.mar_act - alokasi.retur_act)::numeric / v_denom) * v_pool);
      END IF;
      v_sisa := v_sisa - v_v;
      UPDATE _sg_hari d SET bop_a = v_v WHERE d.rute = alokasi.rute;
    END LOOP;
  END LOOP;

  SELECT coalesce(sum(o.jumlah::bigint), 0) INTO v_pool
  FROM public.ongkir o
  JOIN public.setoran_buku b ON b.id = o.id_setoran_buku
  WHERE b.ditutup AND b.tanggal = v_hari;

  SELECT coalesce(sum(mar_act - retur_act), 0), count(*)
  INTO v_denom, v_n FROM _sg_hari;
  v_sisa := v_pool;
  v_i := 0;
  FOR rec IN SELECT * FROM _sg_hari d ORDER BY d.rute
  LOOP
    v_i := v_i + 1;
    IF v_i = v_n THEN
      v_v := v_sisa;
    ELSIF v_denom <= 0 THEN
      v_v := v_pool / GREATEST(v_n, 1);
    ELSE
      v_v := round(((rec.mar_act - rec.retur_act)::numeric / v_denom) * v_pool);
    END IF;
    v_sisa := v_sisa - v_v;
    UPDATE _sg_hari d SET ongkir_a = v_v WHERE d.rute = rec.rute;
  END LOOP;

  SELECT coalesce(sum(
    coalesce(b.selisih_opname, coalesce(op.hitung, 0))
  ), 0) INTO v_pool
  FROM public.setoran_buku b
  LEFT JOIN LATERAL (
    SELECT (
      coalesce(sum(
        CASE
          WHEN so.putusan = 'margin_plus' THEN so.nilai_putusan
          WHEN so.putusan IS NULL
            AND so.stok_fisik IS NOT NULL
            AND coalesce(so.selisih, 0) > 0
          THEN round(so.selisih * coalesce(br.harga_beli, 0))::integer
          ELSE 0
        END
      ), 0)
      - coalesce(sum(
        CASE WHEN so.putusan = 'beban' THEN so.nilai_putusan ELSE 0 END
      ), 0)
    )::bigint AS hitung
    FROM public.stok_opname so
    LEFT JOIN public.barang br ON br.id_barang = so.id_barang
    WHERE so.id_setoran_buku = b.id
  ) op ON true
  WHERE b.ditutup AND b.tanggal = v_hari;

  v_sisa := v_pool;
  v_i := 0;
  FOR rec IN SELECT * FROM _sg_hari d ORDER BY d.rute
  LOOP
    v_i := v_i + 1;
    IF v_i = v_n THEN
      v_v := v_sisa;
    ELSIF v_denom <= 0 THEN
      v_v := v_pool / GREATEST(v_n, 1);
    ELSE
      v_v := round(((rec.mar_act - rec.retur_act)::numeric / v_denom) * v_pool);
    END IF;
    v_sisa := v_sisa - v_v;
    UPDATE _sg_hari d SET selisih_a = v_v WHERE d.rute = rec.rute;
  END LOOP;

  SELECT * INTO rec FROM _sg_hari d WHERE d.rute = v_rute;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Rute sales tidak ditemukan.';
  END IF;

  SELECT count(DISTINCT k.id_pelanggan)::int INTO v_visit
  FROM public.kunjungan_sales k
  WHERE btrim(k.rute) = v_rute
    AND k.tanggal = v_hari
    AND btrim(COALESCE(k.id_pelanggan, '')) <> '';

  SELECT count(DISTINCT t.id_pelanggan)::int INTO v_ec
  FROM public.transaksi t
  WHERE t.status = 'terkirim'
    AND btrim(t.rute) = v_rute
    AND btrim(COALESCE(t.id_pelanggan, '')) <> ''
    AND (timezone('Asia/Jakarta', t.waktu_order))::date = v_hari;

  hari := v_hari;
  bop_aktual := rec.bop_a;
  net_actual := rec.mar_act - rec.retur_act - rec.bop_a - rec.ongkir_a + rec.selisih_a;
  visit := COALESCE(v_visit, 0);
  ec := COALESCE(v_ec, 0);
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.salesman_gaji_hari(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.salesman_gaji_hari(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.salesman_gaji_hari(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.salesman_gaji_hari(date) IS
  'Penggerak gaji sales rute login untuk satu hari. Bukan slip gaji harian.';

NOTIFY pgrst, 'reload schema';
