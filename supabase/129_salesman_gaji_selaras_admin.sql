-- Gaji salesman: visit/EC/omset tampil sama sumber admin (dashboard + gaji).
-- Visit hanya toko jadwal. Omset/rasio actual = tanggal order, bukan tanggal buku.
-- Net/benefit tetap rumus gaji admin. Jalankan SETELAH 127. Boleh diulang.

DROP FUNCTION IF EXISTS public.salesman_gaji_minggu(date);

CREATE FUNCTION public.salesman_gaji_minggu(p_senin date DEFAULT NULL)
RETURNS TABLE (
  senin date,
  sabtu date,
  rute text,
  nama text,
  rasio_actual numeric,
  rasio_target numeric,
  pct_rasio numeric,
  omset_actual bigint,
  omset_target bigint,
  pct_omset numeric,
  ben_omset bigint,
  ec integer,
  ec_target integer,
  pct_ec numeric,
  ben_ec bigint,
  visit integer,
  visit_target integer,
  pct_visit numeric,
  ben_visit bigint,
  bop_pengirim bigint,
  total bigint
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
  v_senin date;
  v_sabtu date;
  v_email text;
  v_nama text;
  v_rute text;
  v_bop_mobil bigint := 1020000;
  v_ongkir_semua bigint := 2000000;
  v_sales_net bigint := 800000;
  v_sales_visit bigint := 200000;
  v_sales_ec bigint := 200000;
  rec record;
  alokasi record;
  v_tot_mar bigint;
  v_sisa bigint;
  v_n int;
  v_i int;
  v_v bigint;
  v_denom bigint;
  v_pool bigint;
  v_pas text;
  v_net_t bigint;
  v_pct numeric;
  v_ben_net bigint;
  v_ben_v bigint;
  v_ben_e bigint;
  v_tot bigint;
  v_net_a bigint;
  v_visit int;
  v_toko int;
  v_ec int;
  v_rasio_a numeric;
  v_rasio_t numeric;
  v_omset_a bigint;
  v_omset_t bigint;
  v_modal_dash bigint;
  v_bop_p bigint;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun sales yang boleh melihat gaji ini.';
  END IF;

  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_senin := COALESCE(p_senin, v_hari - ((EXTRACT(ISODOW FROM v_hari)::int) - 1));
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::int) - 1);
  v_sabtu := v_senin + 5;

  SELECT
    lower(btrim(u.email)),
    coalesce(nullif(btrim(u.nama), ''), btrim(u.email)),
    btrim(u.rute)
  INTO v_email, v_nama, v_rute
  FROM public.users u
  WHERE u.peran = 'sales'
    AND lower(btrim(u.email)) = public.email_jwt()
  LIMIT 1;

  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Akun sales belum punya rute.';
  END IF;

  SELECT
    g.bop_mobil, g.ongkir_semua, g.sales_net, g.sales_visit, g.sales_ec
  INTO v_bop_mobil, v_ongkir_semua, v_sales_net, v_sales_visit, v_sales_ec
  FROM public.gaji_setelan g
  WHERE g.id = 1;

  DROP TABLE IF EXISTS _sg_draf;
  CREATE TEMP TABLE _sg_draf (
    rute text PRIMARY KEY,
    nama text,
    pengirim text,
    omset bigint,
    rasio numeric,
    mar bigint,
    ongkir_t bigint DEFAULT 0,
    bop_t bigint DEFAULT 0,
    omset_act bigint DEFAULT 0,
    modal_act bigint DEFAULT 0,
    mar_act bigint DEFAULT 0,
    retur_act bigint DEFAULT 0,
    bop_a bigint DEFAULT 0,
    ongkir_a bigint DEFAULT 0,
    selisih_a bigint DEFAULT 0
  ) ON COMMIT DROP;

  INSERT INTO _sg_draf (rute, nama, pengirim, omset, rasio, mar)
  SELECT
    btrim(u.rute),
    coalesce(nullif(btrim(u.nama), ''), btrim(u.email)),
    coalesce(p.rute_pengirim, ''),
    GREATEST(COALESCE(t.target_omset, 0), 0),
    GREATEST(COALESCE(t.target_persen_laba, 0), 0),
    0
  FROM public.users u
  LEFT JOIN public.target_sales t ON lower(btrim(t.email)) = lower(btrim(u.email))
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

  UPDATE _sg_draf d
  SET mar = CASE
    WHEN d.omset <= 0 OR d.rasio <= 0 THEN 0
    ELSE round(d.omset * d.rasio / (100 + d.rasio))
  END
  WHERE TRUE;

  SELECT coalesce(sum(mar), 0) INTO v_tot_mar FROM _sg_draf;
  SELECT count(*) INTO v_n FROM _sg_draf;
  v_sisa := v_ongkir_semua;
  v_i := 0;
  FOR rec IN SELECT * FROM _sg_draf d ORDER BY d.rute
  LOOP
    v_i := v_i + 1;
    IF v_i = v_n THEN
      v_v := v_sisa;
    ELSIF v_tot_mar <= 0 THEN
      v_v := v_ongkir_semua / GREATEST(v_n, 1);
    ELSE
      v_v := round((rec.mar::numeric / v_tot_mar) * v_ongkir_semua);
    END IF;
    v_sisa := v_sisa - v_v;
    UPDATE _sg_draf d SET ongkir_t = v_v WHERE d.rute = rec.rute;
  END LOOP;

  FOR v_pas IN
    SELECT DISTINCT pengirim FROM _sg_draf WHERE pengirim <> ''
  LOOP
    SELECT coalesce(sum(mar), 0), count(*)
    INTO v_denom, v_n
    FROM _sg_draf WHERE pengirim = v_pas;
    v_sisa := v_bop_mobil;
    v_i := 0;
    FOR rec IN
      SELECT * FROM _sg_draf d WHERE d.pengirim = v_pas ORDER BY d.rute
    LOOP
      v_i := v_i + 1;
      IF v_i = v_n THEN
        v_v := v_sisa;
      ELSIF v_denom <= 0 THEN
        v_v := v_bop_mobil / GREATEST(v_n, 1);
      ELSE
        v_v := round((rec.mar::numeric / v_denom) * v_bop_mobil);
      END IF;
      v_sisa := v_sisa - v_v;
      UPDATE _sg_draf d SET bop_t = v_v WHERE d.rute = rec.rute;
    END LOOP;
  END LOOP;

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
      AND b.tanggal >= v_senin AND b.tanggal <= v_sabtu
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
      AND b.tanggal >= v_senin AND b.tanggal <= v_sabtu
    GROUP BY r.id_setoran_buku, btrim(r.rute_sales)
  ),
  gabung AS (
    SELECT
      coalesce(u.rute, rt.rute) AS rute,
      coalesce(u.omset, 0)::bigint AS omset,
      coalesce(u.modal, 0)::bigint AS modal,
      (coalesce(u.omset, 0) - coalesce(u.modal, 0))::bigint AS margin,
      coalesce(rt.margin_retur, 0)::bigint AS margin_retur
    FROM uang u
    FULL JOIN retur rt ON rt.id_buku = u.id_buku AND rt.rute = u.rute
  ),
  tot AS (
    SELECT
      rute,
      sum(omset) AS omset,
      sum(modal) AS modal,
      sum(margin) AS margin,
      sum(margin_retur) AS margin_retur
    FROM gabung
    GROUP BY rute
  )
  UPDATE _sg_draf d
  SET
    omset_act = coalesce(t.omset, 0),
    modal_act = coalesce(t.modal, 0),
    mar_act = coalesce(t.margin, 0),
    retur_act = coalesce(t.margin_retur, 0)
  FROM tot t
  WHERE t.rute = d.rute;

  FOR rec IN
    SELECT
      btrim(s.rute_pengirim) AS pengirim,
      coalesce(sum(s.jumlah_bop::bigint), 0) AS pool
    FROM public.setoran_pengirim s
    JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
    WHERE b.tanggal >= v_senin AND b.tanggal <= v_sabtu
      AND btrim(s.rute_pengirim) <> ''
    GROUP BY btrim(s.rute_pengirim)
  LOOP
    v_pas := rec.pengirim;
    v_pool := rec.pool;
    SELECT coalesce(sum(mar_act - retur_act), 0), count(*)
    INTO v_denom, v_n
    FROM _sg_draf WHERE pengirim = v_pas;
    v_sisa := v_pool;
    v_i := 0;
    FOR alokasi IN
      SELECT * FROM _sg_draf d WHERE d.pengirim = v_pas ORDER BY d.rute
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
      UPDATE _sg_draf d SET bop_a = v_v WHERE d.rute = alokasi.rute;
    END LOOP;
  END LOOP;

  SELECT coalesce(sum(o.jumlah::bigint), 0) INTO v_pool
  FROM public.ongkir o
  JOIN public.setoran_buku b ON b.id = o.id_setoran_buku
  WHERE b.ditutup
    AND b.tanggal >= v_senin AND b.tanggal <= v_sabtu;

  SELECT coalesce(sum(mar_act - retur_act), 0), count(*)
  INTO v_denom, v_n FROM _sg_draf;
  v_sisa := v_pool;
  v_i := 0;
  FOR rec IN SELECT * FROM _sg_draf d ORDER BY d.rute
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
    UPDATE _sg_draf d SET ongkir_a = v_v WHERE d.rute = rec.rute;
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
  WHERE b.ditutup
    AND b.tanggal >= v_senin AND b.tanggal <= v_sabtu;

  v_sisa := v_pool;
  v_i := 0;
  FOR rec IN SELECT * FROM _sg_draf d ORDER BY d.rute
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
    UPDATE _sg_draf d SET selisih_a = v_v WHERE d.rute = rec.rute;
  END LOOP;

  SELECT * INTO rec FROM _sg_draf d WHERE d.rute = v_rute;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Rute sales tidak ditemukan.';
  END IF;

  v_net_t := rec.mar - rec.bop_t - rec.ongkir_t;
  v_net_a := rec.mar_act - rec.retur_act - rec.bop_a - rec.ongkir_a + rec.selisih_a;
  v_pct := CASE WHEN v_net_t = 0 THEN 0 ELSE v_net_a::numeric / v_net_t END;
  v_ben_net := round(v_sales_net * v_pct);

  SELECT count(*)::int INTO v_toko
  FROM public.pelanggan p
  WHERE btrim(p.rute) = v_rute
    AND COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%';

  SELECT count(DISTINCT k.id_pelanggan)::int INTO v_visit
  FROM public.kunjungan_sales k
  WHERE btrim(k.rute) = v_rute
    AND k.tanggal >= v_senin AND k.tanggal <= v_sabtu
    AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
    AND public.toko_jadwal_pada(k.id_pelanggan, k.tanggal, v_rute);

  SELECT count(DISTINCT t.id_pelanggan)::int INTO v_ec
  FROM public.transaksi t
  WHERE t.status = 'terkirim'
    AND btrim(t.rute) = v_rute
    AND btrim(COALESCE(t.id_pelanggan, '')) <> ''
    AND (timezone('Asia/Jakarta', t.waktu_order))::date >= v_senin
    AND (timezone('Asia/Jakarta', t.waktu_order))::date <= v_sabtu;

  IF v_toko <= 0 THEN
    v_ben_v := 0;
    v_ben_e := 0;
  ELSE
    v_ben_v := round((v_sales_visit::numeric * v_visit) / v_toko);
    v_ben_e := round((v_sales_ec::numeric * v_ec) / v_toko);
  END IF;
  v_tot := v_ben_net + v_ben_v + v_ben_e;

  v_omset_t := rec.omset;
  v_rasio_t := rec.rasio;
  SELECT
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint,
    coalesce(sum(i.subtotal_beli_actual), 0)::bigint
  INTO v_omset_a, v_modal_dash
  FROM public.transaksi t
  JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  WHERE t.status <> 'batal'
    AND btrim(t.rute) = v_rute
    AND (timezone('Asia/Jakarta', t.waktu_order))::date >= v_senin
    AND (timezone('Asia/Jakarta', t.waktu_order))::date <= v_sabtu;
  v_omset_a := COALESCE(v_omset_a, 0);
  v_modal_dash := COALESCE(v_modal_dash, 0);
  v_rasio_a := CASE
    WHEN v_modal_dash <= 0 THEN 0
    ELSE ((v_omset_a - v_modal_dash)::numeric / v_modal_dash) * 100
  END;

  v_bop_p := 0;
  IF rec.pengirim <> '' THEN
    SELECT coalesce(sum(s.jumlah_bop::bigint), 0) INTO v_bop_p
    FROM public.setoran_pengirim s
    JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
    WHERE b.tanggal >= v_senin AND b.tanggal <= v_sabtu
      AND btrim(s.rute_pengirim) = rec.pengirim;
  END IF;

  senin := v_senin;
  sabtu := v_sabtu;
  rute := v_rute;
  nama := v_nama;
  rasio_actual := v_rasio_a;
  rasio_target := v_rasio_t;
  pct_rasio := CASE WHEN v_rasio_t = 0 THEN 0 ELSE v_rasio_a / v_rasio_t END;
  omset_actual := v_omset_a;
  omset_target := v_omset_t;
  pct_omset := CASE WHEN v_omset_t = 0 THEN 0 ELSE v_omset_a::numeric / v_omset_t END;
  ben_omset := v_ben_net;
  ec := v_ec;
  ec_target := GREATEST(v_toko, 1);
  pct_ec := CASE WHEN v_toko <= 0 THEN 0 ELSE v_ec::numeric / v_toko END;
  ben_ec := v_ben_e;
  visit := v_visit;
  visit_target := GREATEST(v_toko, 1);
  pct_visit := CASE WHEN v_toko <= 0 THEN 0 ELSE v_visit::numeric / v_toko END;
  ben_visit := v_ben_v;
  bop_pengirim := v_bop_p;
  total := v_tot;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.salesman_gaji_minggu(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.salesman_gaji_minggu(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.salesman_gaji_minggu(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.salesman_gaji_minggu(date) IS
  'Perkiraan gaji sales: visit jadwal + omset/rasio tanggal order seperti dashboard admin.';

NOTIFY pgrst, 'reload schema';
