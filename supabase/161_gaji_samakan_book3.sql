-- Samakan gaji minggu Excel Book3. Snapshot minggu < 12-10 tidak diubah.
-- Jalankan SETELAH 160 (boleh diulang). Jangan UPDATE pelanggan.

UPDATE public.gaji_setelan SET
  bop_mobil = 1000000,
  ongkir_semua = 1600000,
  sales_net = 600000,
  sales_visit = 300000,
  sales_ec = 300000,
  pengirim = 1800000,
  gudang = 1800000,
  gudang_slot = 4,
  admin = 900000,
  omset_semua = 4200000,
  visit_target = 100,
  ec_target = 80
WHERE id = 1;

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
  net_actual bigint,
  net_target bigint,
  pct_net numeric,
  omset_actual bigint,
  omset_target bigint,
  pct_omset numeric,
  ben_omset bigint,
  ben_insentif bigint,
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
  v_ben_ins bigint := 0;
  v_bop_p bigint;
  v_cap jsonb;
  v_omset_pool bigint := 0;
  v_visit_tgt numeric := 90;
  v_ec_tgt numeric := 70;
  v_sum_m bigint := 0;
  v_ah bigint := 0;
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
    g.bop_mobil, g.ongkir_semua, g.sales_net, g.sales_visit, g.sales_ec,
    g.omset_semua, g.visit_target, g.ec_target
  INTO v_bop_mobil, v_ongkir_semua, v_sales_net, v_sales_visit, v_sales_ec,
       v_omset_pool, v_visit_tgt, v_ec_tgt
  FROM public.gaji_baca_patokan(v_senin) g;
  v_bop_mobil := GREATEST(COALESCE(v_bop_mobil, 1000000), 0);
  v_ongkir_semua := GREATEST(COALESCE(v_ongkir_semua, 1600000), 0);
  v_sales_net := GREATEST(COALESCE(v_sales_net, 600000), 0);
  v_sales_visit := GREATEST(COALESCE(v_sales_visit, 300000), 0);
  v_sales_ec := GREATEST(COALESCE(v_sales_ec, 300000), 0);
  v_omset_pool := GREATEST(COALESCE(v_omset_pool, 0), 0);
  v_visit_tgt := GREATEST(COALESCE(v_visit_tgt, 100), 1);
  v_ec_tgt := GREATEST(COALESCE(v_ec_tgt, 80), 1);

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
    GREATEST(COALESCE(tg.omset, 0), 0),
    GREATEST(COALESCE(tg.rasio, 0), 0),
    0
  FROM public.users u
  LEFT JOIN LATERAL public.gaji_target_pada(btrim(u.rute), v_senin) tg ON true
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

  IF public.gaji_pakai_excel(v_senin) THEN
    FOR v_pas IN
      SELECT DISTINCT pengirim FROM _sg_draf WHERE pengirim <> ''
    LOOP
      SELECT coalesce(sum(mar - ongkir_t), 0), count(*)
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
          v_v := round(((rec.mar - rec.ongkir_t)::numeric / v_denom) * v_bop_mobil);
        END IF;
        v_sisa := v_sisa - v_v;
        UPDATE _sg_draf d SET bop_t = v_v WHERE d.rute = rec.rute;
      END LOOP;
    END LOOP;
  END IF;

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

  v_toko := public.gaji_n_toko_rute(v_rute, v_senin);

  v_cap := public._admin_dashboard_capaian(
    v_rute,
    v_senin,
    v_sabtu,
    GREATEST(v_toko, 1)
  );
  v_ec := COALESCE((v_cap->>'ec_actual')::int, 0);
  v_visit := COALESCE((v_cap->>'visit')::int, 0);

  IF public.gaji_pakai_excel(v_senin) THEN
    v_ben_net := public.gaji_mround(v_pct * v_sales_net, 500);
    IF v_toko <= 0 OR COALESCE(v_visit_tgt, 0) <= 0 THEN
      v_ben_v := 0;
    ELSE
      v_ben_v := public.gaji_mround(
        v_sales_visit * ((v_visit::numeric * 100 / v_toko) / v_visit_tgt),
        500
      );
    END IF;
    IF v_toko <= 0 OR COALESCE(v_ec_tgt, 0) <= 0 THEN
      v_ben_e := 0;
    ELSE
      v_ben_e := public.gaji_mround(
        v_sales_ec * ((v_ec::numeric * 100 / v_toko) / v_ec_tgt),
        500
      );
    END IF;
  ELSE
    v_ben_net := round(v_sales_net * v_pct);
    IF v_toko <= 0 THEN
      v_ben_v := 0;
      v_ben_e := 0;
    ELSE
      v_ben_v := round((v_sales_visit::numeric * v_visit) / v_toko);
      v_ben_e := round((v_sales_ec::numeric * v_ec) / v_toko);
    END IF;
  END IF;

  v_omset_a := rec.omset_act;
  v_omset_t := rec.omset;
  v_ben_ins := 0;
  IF public.gaji_pakai_excel(v_senin)
     AND v_omset_t > 0
     AND (v_omset_a::numeric / v_omset_t) >= 0.80 THEN
    v_ben_ins := round((v_omset_a::numeric / v_omset_t) * 300000);
  END IF;
  v_tot := v_ben_net + v_ben_v + v_ben_e + v_ben_ins;
  v_rasio_t := rec.rasio;
  v_rasio_a := CASE
    WHEN rec.modal_act <= 0 THEN 0
    ELSE ((rec.omset_act - rec.modal_act)::numeric / rec.modal_act) * 100
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
  net_actual := v_net_a;
  net_target := v_net_t;
  pct_net := v_pct;
  omset_actual := v_omset_a;
  omset_target := v_omset_t;
  pct_omset := CASE WHEN v_omset_t = 0 THEN 0 ELSE v_omset_a::numeric / v_omset_t END;
  ben_omset := v_ben_net;
  ben_insentif := v_ben_ins;
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
  'Book3: Ben. net 600rb×net%; scan 300rb/100%; EC 300rb/80%; insentif omset%≥80.';

DROP FUNCTION IF EXISTS public.admin_gaji_rute_minggu(date);

CREATE FUNCTION public.admin_gaji_rute_minggu(p_senin date)
RETURNS TABLE (
  rute text,
  nama text,
  omset bigint,
  rasio numeric,
  visit integer,
  toko integer,
  ec integer,
  omset_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
SET statement_timeout = '60s'
AS $$
DECLARE
  v_senin date;
  v_sabtu date;
  r record;
  v_omset bigint;
  v_rasio numeric;
  v_toko integer;
  v_cap jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_senin := COALESCE(p_senin, (timezone('Asia/Jakarta', now()))::date);
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::integer) - 1);
  v_sabtu := v_senin + 5;

  FOR r IN
    SELECT btrim(u.rute) AS rute, btrim(u.nama) AS nama
    FROM public.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
    ORDER BY u.rute
  LOOP
    SELECT COALESCE(tg.omset, 0), COALESCE(tg.rasio, 0)
    INTO v_omset, v_rasio
    FROM public.gaji_target_pada(r.rute, v_senin) tg
    LIMIT 1;
    v_toko := public.gaji_n_toko_rute(r.rute, v_senin);
    v_cap := public._admin_dashboard_capaian(r.rute, v_senin, v_sabtu, v_toko);
    rute := r.rute;
    nama := r.nama;
    omset := COALESCE(v_omset, 0);
    rasio := COALESCE(v_rasio, 0);
    visit := COALESCE((v_cap->>'visit')::integer, 0);
    toko := GREATEST(COALESCE(v_toko, 0), 0);
    ec := COALESCE((v_cap->>'ec_actual')::integer, 0);
    omset_actual := COALESCE((v_cap->>'omset_actual')::bigint, 0);
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gaji_rute_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_rute_minggu(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_gaji_rute_minggu(date) IS
  'Target + visit/EC + omset actual minggu untuk insentif omset Book3.';

NOTIFY pgrst, 'reload schema';

