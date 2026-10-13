-- Gaji senin >= 12-10-2026: rumus Excel (Visit/EC vs 90/70 tanpa net%, kolam 7jt,
-- EC 300rb, ongkir 1,6jt, BOP 1jt/truk, pengirim/gudang 1,8jt, admin 900rb).
-- Senin < 12-10: rumus lama + snapshot toko/target/patokan. 4 poin tidak dihitung.
-- Jalankan SETELAH 147. Boleh diulang: snapshot tidak ditimpa; patokan baru
-- hanya diisi sekali. Jangan UPDATE pelanggan di sini.
-- Flutter admin ikut (jangan simpan omset_semua = 0).

ALTER TABLE public.gaji_setelan
  ADD COLUMN IF NOT EXISTS visit_target numeric NOT NULL DEFAULT 90
    CHECK (visit_target > 0);
ALTER TABLE public.gaji_setelan
  ADD COLUMN IF NOT EXISTS ec_target numeric NOT NULL DEFAULT 70
    CHECK (ec_target > 0);

COMMENT ON COLUMN public.gaji_setelan.omset_semua IS
  'Kolam benefit omset semua rute (Excel 7jt). 0 = rumus lama sales_net per rute.';
COMMENT ON COLUMN public.gaji_setelan.visit_target IS
  'Target scan % (Excel 90). Benefit visit = plafon × (scan% / angka ini), tanpa net%.';
COMMENT ON COLUMN public.gaji_setelan.ec_target IS
  'Target EC % (Excel 70). Benefit EC = plafon × (EC% / angka ini), tanpa net%.';

CREATE TABLE IF NOT EXISTS public.gaji_setelan_snap (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  bop_mobil bigint NOT NULL,
  ongkir_semua bigint NOT NULL,
  sales_net bigint NOT NULL,
  sales_visit bigint NOT NULL,
  sales_ec bigint NOT NULL,
  pengirim bigint NOT NULL,
  gudang bigint NOT NULL,
  gudang_slot integer NOT NULL,
  admin bigint NOT NULL,
  omset_semua bigint NOT NULL DEFAULT 0,
  rasio_sales numeric NOT NULL DEFAULT 0,
  visit_target numeric NOT NULL DEFAULT 90,
  ec_target numeric NOT NULL DEFAULT 70
);

CREATE TABLE IF NOT EXISTS public.gaji_target_rute_snap (
  rute text PRIMARY KEY,
  omset bigint NOT NULL DEFAULT 0,
  rasio numeric NOT NULL DEFAULT 0
);

ALTER TABLE public.gaji_setelan_snap ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gaji_target_rute_snap ENABLE ROW LEVEL SECURITY;

INSERT INTO public.gaji_target_rute_snap (rute, omset, rasio)
SELECT
  btrim(u.rute),
  GREATEST(COALESCE(t.target_omset, 0), 0),
  GREATEST(COALESCE(t.target_persen_laba, 0), 0)
FROM public.users u
LEFT JOIN public.target_sales t ON lower(btrim(t.email)) = lower(btrim(u.email))
WHERE u.peran = 'sales'
  AND nullif(btrim(u.rute), '') IS NOT NULL
ON CONFLICT (rute) DO NOTHING;

DO $$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.gaji_setelan_snap;
  INSERT INTO public.gaji_setelan_snap (
    id, bop_mobil, ongkir_semua, sales_net, sales_visit, sales_ec,
    pengirim, gudang, gudang_slot, admin, omset_semua, rasio_sales,
    visit_target, ec_target
  )
  SELECT
    g.id, g.bop_mobil, g.ongkir_semua, g.sales_net, g.sales_visit, g.sales_ec,
    g.pengirim, g.gudang, g.gudang_slot, g.admin, g.omset_semua, g.rasio_sales,
    g.visit_target, g.ec_target
  FROM public.gaji_setelan g
  WHERE g.id = 1
  ON CONFLICT (id) DO NOTHING;

  IF COALESCE(v_n, 0) = 0 THEN
    UPDATE public.gaji_setelan SET
      bop_mobil = 1000000,
      ongkir_semua = 1600000,
      omset_semua = 7000000,
      sales_ec = 300000,
      pengirim = 1800000,
      gudang = 1800000,
      admin = 900000,
      visit_target = 90,
      ec_target = 70
    WHERE id = 1;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_pakai_excel(p_senin date)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_senin IS NOT NULL AND p_senin >= DATE '2026-10-12';
$$;

CREATE OR REPLACE FUNCTION public.gaji_mround(p_nilai numeric, p_kelipatan bigint)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_kelipatan IS NULL OR p_kelipatan = 0 THEN round(COALESCE(p_nilai, 0))::bigint
    ELSE (round(COALESCE(p_nilai, 0) / p_kelipatan) * p_kelipatan)::bigint
  END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_baca_patokan(p_senin date)
RETURNS TABLE (
  bop_mobil bigint,
  ongkir_semua bigint,
  sales_net bigint,
  sales_visit bigint,
  sales_ec bigint,
  pengirim bigint,
  gudang bigint,
  gudang_slot integer,
  admin bigint,
  omset_semua bigint,
  rasio_sales numeric,
  visit_target numeric,
  ec_target numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF p_senin IS NOT NULL AND p_senin < DATE '2026-10-12' THEN
    RETURN QUERY
    SELECT
      s.bop_mobil, s.ongkir_semua, s.sales_net, s.sales_visit, s.sales_ec,
      s.pengirim, s.gudang, s.gudang_slot, s.admin, s.omset_semua, s.rasio_sales,
      s.visit_target, s.ec_target
    FROM public.gaji_setelan_snap s
    WHERE s.id = 1;
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    g.bop_mobil, g.ongkir_semua, g.sales_net, g.sales_visit, g.sales_ec,
    g.pengirim, g.gudang, g.gudang_slot, g.admin, g.omset_semua, g.rasio_sales,
    g.visit_target, g.ec_target
  FROM public.gaji_setelan g
  WHERE g.id = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_target_pada(p_rute text, p_senin date)
RETURNS TABLE (omset bigint, rasio numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF p_senin IS NOT NULL AND p_senin < DATE '2026-10-12' THEN
    RETURN QUERY
    SELECT s.omset, s.rasio
    FROM public.gaji_target_rute_snap s
    WHERE s.rute = btrim(COALESCE(p_rute, ''));
    IF FOUND THEN
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    GREATEST(COALESCE(t.target_omset, 0), 0)::bigint,
    GREATEST(COALESCE(t.target_persen_laba, 0), 0)
  FROM public.users u
  LEFT JOIN public.target_sales t ON lower(btrim(t.email)) = lower(btrim(u.email))
  WHERE u.peran = 'sales'
    AND btrim(u.rute) = btrim(COALESCE(p_rute, ''))
  ORDER BY u.email
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_gaji_setelan_minggu(p_senin date)
RETURNS public.gaji_setelan
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  rec public.gaji_setelan;
  v_bop bigint;
  v_ongkir bigint;
  v_net bigint;
  v_vis bigint;
  v_ec bigint;
  v_kirim bigint;
  v_gud bigint;
  v_slot integer;
  v_adm bigint;
  v_omset bigint;
  v_rasio numeric;
  v_vt numeric;
  v_et numeric;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT
    p.bop_mobil, p.ongkir_semua, p.sales_net, p.sales_visit, p.sales_ec,
    p.pengirim, p.gudang, p.gudang_slot, p.admin, p.omset_semua, p.rasio_sales,
    p.visit_target, p.ec_target
  INTO
    v_bop, v_ongkir, v_net, v_vis, v_ec,
    v_kirim, v_gud, v_slot, v_adm, v_omset, v_rasio, v_vt, v_et
  FROM public.gaji_baca_patokan(p_senin) p;

  rec.id := 1;
  rec.bop_mobil := COALESCE(v_bop, 0);
  rec.ongkir_semua := COALESCE(v_ongkir, 0);
  rec.sales_net := COALESCE(v_net, 0);
  rec.sales_visit := COALESCE(v_vis, 0);
  rec.sales_ec := COALESCE(v_ec, 0);
  rec.pengirim := COALESCE(v_kirim, 0);
  rec.gudang := COALESCE(v_gud, 0);
  rec.gudang_slot := GREATEST(COALESCE(v_slot, 4), 1);
  rec.admin := COALESCE(v_adm, 0);
  rec.omset_semua := COALESCE(v_omset, 0);
  rec.rasio_sales := COALESCE(v_rasio, 0);
  rec.visit_target := COALESCE(v_vt, 90);
  rec.ec_target := COALESCE(v_et, 70);
  RETURN rec;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint,
  bigint, numeric
);

CREATE FUNCTION public.admin_gaji_setelan_simpan(
  p_bop_mobil bigint,
  p_ongkir_semua bigint,
  p_sales_net bigint,
  p_sales_visit bigint,
  p_sales_ec bigint,
  p_pengirim bigint,
  p_gudang bigint,
  p_gudang_slot integer,
  p_admin bigint,
  p_omset_semua bigint,
  p_rasio_sales numeric,
  p_visit_target numeric,
  p_ec_target numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  INSERT INTO public.gaji_setelan (
    id, bop_mobil, ongkir_semua, sales_net, sales_visit, sales_ec,
    pengirim, gudang, gudang_slot, admin, omset_semua, rasio_sales,
    visit_target, ec_target
  )
  VALUES (
    1, GREATEST(p_bop_mobil, 0), GREATEST(p_ongkir_semua, 0),
    GREATEST(p_sales_net, 0), GREATEST(p_sales_visit, 0),
    GREATEST(p_sales_ec, 0), GREATEST(p_pengirim, 0),
    GREATEST(p_gudang, 0), GREATEST(p_gudang_slot, 1), GREATEST(p_admin, 0),
    GREATEST(p_omset_semua, 0), GREATEST(p_rasio_sales, 0),
    GREATEST(COALESCE(p_visit_target, 90), 1),
    GREATEST(COALESCE(p_ec_target, 70), 1)
  )
  ON CONFLICT (id) DO UPDATE SET
    bop_mobil = EXCLUDED.bop_mobil,
    ongkir_semua = EXCLUDED.ongkir_semua,
    sales_net = EXCLUDED.sales_net,
    sales_visit = EXCLUDED.sales_visit,
    sales_ec = EXCLUDED.sales_ec,
    pengirim = EXCLUDED.pengirim,
    gudang = EXCLUDED.gudang,
    gudang_slot = EXCLUDED.gudang_slot,
    admin = EXCLUDED.admin,
    omset_semua = EXCLUDED.omset_semua,
    rasio_sales = EXCLUDED.rasio_sales,
    visit_target = EXCLUDED.visit_target,
    ec_target = EXCLUDED.ec_target;
END;
$$;

CREATE OR REPLACE FUNCTION public._admin_dashboard_rute(
  p_rute text,
  p_nama text,
  p_email text,
  p_senin date,
  p_sabtu date,
  p_hari date,
  p_nama_hari text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_omset bigint := 0;
  v_persen numeric := 0;
  v_toko integer := 0;
  v_toko_hari integer := 0;
  v_m jsonb;
  v_h jsonb;
BEGIN
  SELECT COALESCE(tg.omset, 0), COALESCE(tg.rasio, 0)
  INTO v_omset, v_persen
  FROM public.gaji_target_pada(p_rute, p_senin) tg;

  IF NOT FOUND THEN
    v_omset := 0;
    v_persen := 0;
  END IF;

  v_toko := public.gaji_n_toko_rute(p_rute, p_senin);

  SELECT count(*)::integer
  INTO v_toko_hari
  FROM public.pelanggan p
  WHERE btrim(p.rute) = p_rute
    AND COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(p.visit, '')) = p_nama_hari;

  v_m := public._admin_dashboard_capaian(p_rute, p_senin, p_sabtu, v_toko);
  v_h := public._admin_dashboard_capaian(p_rute, p_hari, p_hari, v_toko_hari);

  RETURN jsonb_build_object(
    'rute', p_rute,
    'nama', p_nama,
    'target_omset', v_omset,
    'target_persen', v_persen,
    'minggu', v_m,
    'hari', v_h
  );
END;
$$;

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
  v_bop_mobil := GREATEST(COALESCE(v_bop_mobil, 1020000), 0);
  v_ongkir_semua := GREATEST(COALESCE(v_ongkir_semua, 2000000), 0);
  v_sales_net := GREATEST(COALESCE(v_sales_net, 800000), 0);
  v_sales_visit := GREATEST(COALESCE(v_sales_visit, 200000), 0);
  v_sales_ec := GREATEST(COALESCE(v_sales_ec, 200000), 0);
  v_omset_pool := GREATEST(COALESCE(v_omset_pool, 0), 0);
  v_visit_tgt := GREATEST(COALESCE(v_visit_tgt, 90), 1);
  v_ec_tgt := GREATEST(COALESCE(v_ec_tgt, 70), 1);

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
    SELECT coalesce(sum(d.mar - d.bop_t - d.ongkir_t), 0) INTO v_sum_m FROM _sg_draf d;
    IF v_sum_m <= 0 THEN
      v_ben_net := 0;
    ELSE
      v_ah := public.gaji_mround(
        (v_omset_pool::numeric * v_net_t) / v_sum_m,
        5000
      );
      v_ben_net := public.gaji_mround(v_pct * v_ah, 500);
    END IF;
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
  v_tot := v_ben_net + v_ben_v + v_ben_e;

  v_omset_a := rec.omset_act;
  v_omset_t := rec.omset;
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
  'Senin>=12-10 rumus Excel; minggu lama snapshot + rumus lama.';


DROP FUNCTION IF EXISTS public.pengirim_gaji_minggu(date);

CREATE FUNCTION public.pengirim_gaji_minggu(p_senin date DEFAULT NULL)
RETURNS TABLE (
  senin date,
  sabtu date,
  rute text,
  nama text,
  net_actual bigint,
  net_target bigint,
  pct_net numeric,
  rasio_actual numeric,
  rasio_target numeric,
  pct_rasio numeric,
  omset_actual bigint,
  omset_target bigint,
  pct_omset numeric,
  hari integer,
  hari_target integer,
  pct_hari numeric,
  bop_actual bigint,
  bop_target bigint,
  pct_bop numeric,
  gaji bigint,
  kasbon bigint,
  terima bigint
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
  v_grup text;
  v_bop_mobil bigint := 1020000;
  v_ongkir_semua bigint := 2000000;
  v_patokan bigint := 800000;
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
  v_net_a bigint;
  v_pct numeric;
  v_rasio_a numeric;
  v_rasio_t numeric;
  v_omset_a bigint;
  v_omset_t bigint;
  v_bop_a bigint;
  v_penuh bigint;
  v_hari_tot int;
  v_hari_saya int;
  v_gaji bigint;
  v_kb bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun pengirim yang boleh melihat gaji ini.';
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
  WHERE u.peran = 'pengirim'
    AND lower(btrim(u.email)) = public.email_jwt()
  LIMIT 1;

  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Akun pengirim belum punya rute.';
  END IF;

  v_grup := public.pengirim_grup_rute(v_rute);
  IF v_grup IS NULL OR v_grup = '' THEN
    RAISE EXCEPTION 'Akun pengirim belum punya rute.';
  END IF;

  SELECT g.bop_mobil, g.ongkir_semua, g.pengirim
  INTO v_bop_mobil, v_ongkir_semua, v_patokan
  FROM public.gaji_baca_patokan(v_senin) g;
  v_bop_mobil := GREATEST(COALESCE(v_bop_mobil, 1020000), 0);
  v_ongkir_semua := GREATEST(COALESCE(v_ongkir_semua, 2000000), 0);
  v_patokan := GREATEST(COALESCE(v_patokan, 800000), 0);

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

  SELECT
    coalesce(sum(d.mar - d.bop_t - d.ongkir_t), 0),
    coalesce(sum(
      d.mar_act - d.retur_act - d.bop_a - d.ongkir_a + d.selisih_a
    ), 0),
    coalesce(sum(d.omset_act), 0),
    coalesce(sum(d.omset), 0)
  INTO v_net_t, v_net_a, v_omset_a, v_omset_t
  FROM _sg_draf d
  WHERE public.pengirim_grup_rute(d.pengirim) = v_grup;

  v_pct := CASE WHEN v_net_t = 0 THEN 0 ELSE v_net_a::numeric / v_net_t END;

  SELECT
    coalesce(avg(
      CASE
        WHEN d.modal_act <= 0 THEN 0
        ELSE ((d.omset_act - d.modal_act)::numeric / d.modal_act) * 100
      END
    ), 0),
    coalesce(avg(d.rasio), 0)
  INTO v_rasio_a, v_rasio_t
  FROM _sg_draf d
  WHERE public.pengirim_grup_rute(d.pengirim) = v_grup;

  IF public.gaji_pakai_excel(v_senin) THEN
    v_penuh := public.gaji_mround(v_patokan * v_pct, 500);
    v_pool := v_penuh;
  ELSE
    v_penuh := round(v_patokan * v_pct);
    v_pool := v_penuh * 2;
  END IF;

  SELECT coalesce(sum(s.jumlah_bop::bigint), 0) INTO v_bop_a
  FROM public.setoran_pengirim s
  JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
  WHERE b.tanggal >= v_senin AND b.tanggal <= v_sabtu
    AND public.pengirim_grup_rute(s.rute_pengirim) = v_grup;

  DROP TABLE IF EXISTS _pg_orang;
  CREATE TEMP TABLE _pg_orang (
    email text PRIMARY KEY,
    nama text,
    rute text,
    hari integer DEFAULT 0,
    gaji bigint DEFAULT 0
  ) ON COMMIT DROP;

  INSERT INTO _pg_orang (email, nama, rute)
  SELECT
    lower(btrim(u.email)),
    coalesce(nullif(btrim(u.nama), ''), btrim(u.email)),
    btrim(u.rute)
  FROM public.users u
  WHERE u.peran = 'pengirim'
    AND public.pengirim_grup_rute(u.rute) = v_grup
  ON CONFLICT (email) DO NOTHING;

  UPDATE _pg_orang o
  SET hari = h.hari
  FROM (
    SELECT
      lower(btrim(a.email)) AS email,
      count(DISTINCT a.id_setoran_buku)::integer AS hari
    FROM public.absensi a
    JOIN public.setoran_buku b ON b.id = a.id_setoran_buku
    WHERE a.waktu_masuk IS NOT NULL
      AND b.tanggal >= v_senin AND b.tanggal <= v_sabtu
    GROUP BY lower(btrim(a.email))
  ) h
  WHERE h.email = o.email;

  SELECT coalesce(sum(hari), 0), count(*)
  INTO v_hari_tot, v_n
  FROM _pg_orang WHERE hari > 0;
  v_sisa := v_pool;
  v_i := 0;
  FOR rec IN
    SELECT * FROM _pg_orang o WHERE o.hari > 0 ORDER BY o.email
  LOOP
    v_i := v_i + 1;
    IF public.gaji_pakai_excel(v_senin) THEN
      IF v_hari_tot <= 0 THEN
        v_v := 0;
      ELSE
        v_v := public.gaji_mround((v_pool::numeric * rec.hari) / v_hari_tot, 500);
      END IF;
    ELSIF v_i = v_n THEN
      v_v := v_sisa;
    ELSIF v_hari_tot <= 0 THEN
      v_v := 0;
    ELSE
      v_v := round((v_pool::numeric * rec.hari) / v_hari_tot);
    END IF;
    v_sisa := v_sisa - v_v;
    UPDATE _pg_orang o SET gaji = v_v WHERE o.email = rec.email;
  END LOOP;

  SELECT o.hari, o.gaji INTO v_hari_saya, v_gaji
  FROM _pg_orang o WHERE o.email = v_email;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Rute pengirim tidak ditemukan.';
  END IF;
  v_hari_saya := COALESCE(v_hari_saya, 0);
  v_gaji := COALESCE(v_gaji, 0);

  SELECT g.nilai INTO v_kb
  FROM public.gaji_kasbon_minggu g
  WHERE g.senin = v_senin AND lower(btrim(g.email)) = v_email;
  v_kb := COALESCE(v_kb, 0);

  senin := v_senin;
  sabtu := v_sabtu;
  rute := v_rute;
  nama := v_nama;
  net_actual := v_net_a;
  net_target := v_net_t;
  pct_net := v_pct;
  rasio_actual := v_rasio_a;
  rasio_target := v_rasio_t;
  pct_rasio := CASE WHEN v_rasio_t = 0 THEN 0 ELSE v_rasio_a / v_rasio_t END;
  omset_actual := v_omset_a;
  omset_target := v_omset_t;
  pct_omset := CASE WHEN v_omset_t = 0 THEN 0 ELSE v_omset_a::numeric / v_omset_t END;
  hari := v_hari_saya;
  hari_target := 6;
  pct_hari := v_hari_saya::numeric / 6;
  bop_actual := COALESCE(v_bop_a, 0);
  bop_target := v_bop_mobil;
  pct_bop := CASE WHEN v_bop_mobil = 0 THEN 0 ELSE v_bop_a::numeric / v_bop_mobil END;
  gaji := v_gaji;
  kasbon := v_kb;
  terima := v_gaji - v_kb;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_gaji_minggu(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pengirim_gaji_minggu(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.pengirim_gaji_minggu(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.pengirim_gaji_minggu(date) IS
  'Gaji dari net pasangan. Kartu atas: rata-rata rasio laba sales.';


DROP FUNCTION IF EXISTS public.gudang_gaji_minggu(date);

CREATE FUNCTION public.gudang_gaji_minggu(p_senin date DEFAULT NULL)
RETURNS TABLE (
  senin date,
  sabtu date,
  rute text,
  nama text,
  net_actual bigint,
  net_target bigint,
  pct_net numeric,
  rasio_actual numeric,
  rasio_target numeric,
  pct_rasio numeric,
  omset_actual bigint,
  omset_target bigint,
  pct_omset numeric,
  hari integer,
  hari_target integer,
  pct_hari numeric,
  bop_actual bigint,
  bop_target bigint,
  pct_bop numeric,
  gaji bigint,
  kasbon bigint,
  terima bigint
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
  v_patokan bigint := 500000;
  v_slot int := 4;
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
  v_net_a bigint;
  v_pct numeric;
  v_rasio_a numeric;
  v_rasio_t numeric;
  v_omset_a bigint;
  v_omset_t bigint;
  v_modal_a bigint;
  v_bop_a bigint;
  v_bop_t bigint;
  v_penuh bigint;
  v_hari_tot int;
  v_hari_saya int;
  v_gaji bigint;
  v_kb bigint;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun gudang yang boleh melihat gaji ini.';
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
  WHERE lower(btrim(u.email)) = public.email_jwt()
    AND u.peran IN ('gudang', 'admin')
  LIMIT 1;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Akun gudang tidak ditemukan.';
  END IF;

  SELECT g.bop_mobil, g.ongkir_semua, g.gudang, g.gudang_slot
  INTO v_bop_mobil, v_ongkir_semua, v_patokan, v_slot
  FROM public.gaji_baca_patokan(v_senin) g;
  v_bop_mobil := GREATEST(COALESCE(v_bop_mobil, 1020000), 0);
  v_ongkir_semua := GREATEST(COALESCE(v_ongkir_semua, 2000000), 0);
  v_patokan := GREATEST(COALESCE(v_patokan, 500000), 0);
  v_slot := GREATEST(COALESCE(v_slot, 4), 1);

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

  SELECT
    coalesce(sum(d.mar - d.bop_t - d.ongkir_t), 0),
    coalesce(sum(
      d.mar_act - d.retur_act - d.bop_a - d.ongkir_a + d.selisih_a
    ), 0),
    coalesce(sum(d.omset_act), 0),
    coalesce(sum(d.omset), 0),
    coalesce(sum(d.modal_act), 0)
  INTO v_net_t, v_net_a, v_omset_a, v_omset_t, v_modal_a
  FROM _sg_draf d;

  v_pct := CASE WHEN v_net_t = 0 THEN 0 ELSE v_net_a::numeric / v_net_t END;

  v_rasio_a := CASE
    WHEN coalesce(v_modal_a, 0) <= 0 THEN 0
    ELSE ((v_omset_a - v_modal_a)::numeric / v_modal_a) * 100
  END;
  SELECT coalesce(avg(d.rasio), 0) INTO v_rasio_t FROM _sg_draf d;

  IF public.gaji_pakai_excel(v_senin) THEN
    v_penuh := public.gaji_mround(v_patokan * v_pct, 500);
    v_pool := v_penuh;
  ELSE
    v_penuh := round(v_patokan * v_pct);
    v_pool := v_penuh * v_slot;
  END IF;

  SELECT coalesce(sum(s.jumlah_bop::bigint), 0) INTO v_bop_a
  FROM public.setoran_pengirim s
  JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
  WHERE b.tanggal >= v_senin AND b.tanggal <= v_sabtu;

  SELECT count(DISTINCT d.pengirim) INTO v_n
  FROM _sg_draf d
  WHERE d.pengirim <> '';
  v_bop_t := v_bop_mobil * GREATEST(COALESCE(v_n, 0), 0);

  DROP TABLE IF EXISTS _pg_orang;
  CREATE TEMP TABLE _pg_orang (
    email text PRIMARY KEY,
    nama text,
    rute text,
    hari integer DEFAULT 0,
    gaji bigint DEFAULT 0
  ) ON COMMIT DROP;

  INSERT INTO _pg_orang (email, nama, rute)
  SELECT
    lower(btrim(u.email)),
    coalesce(nullif(btrim(u.nama), ''), btrim(u.email)),
    btrim(u.rute)
  FROM public.users u
  WHERE u.peran = 'gudang'
  ON CONFLICT (email) DO NOTHING;

  UPDATE _pg_orang o
  SET hari = h.hari
  FROM (
    SELECT
      lower(btrim(a.email)) AS email,
      count(DISTINCT a.id_setoran_buku)::integer AS hari
    FROM public.absensi a
    JOIN public.setoran_buku b ON b.id = a.id_setoran_buku
    WHERE a.waktu_masuk IS NOT NULL
      AND b.tanggal >= v_senin AND b.tanggal <= v_sabtu
    GROUP BY lower(btrim(a.email))
  ) h
  WHERE h.email = o.email;

  SELECT coalesce(sum(hari), 0), count(*)
  INTO v_hari_tot, v_n
  FROM _pg_orang WHERE hari > 0;
  v_sisa := v_pool;
  v_i := 0;
  FOR rec IN
    SELECT * FROM _pg_orang o WHERE o.hari > 0 ORDER BY o.email
  LOOP
    v_i := v_i + 1;
    IF public.gaji_pakai_excel(v_senin) THEN
      IF v_hari_tot <= 0 THEN
        v_v := 0;
      ELSE
        v_v := public.gaji_mround((v_pool::numeric * rec.hari) / v_hari_tot, 500);
      END IF;
    ELSIF v_i = v_n THEN
      v_v := v_sisa;
    ELSIF v_hari_tot <= 0 THEN
      v_v := 0;
    ELSE
      v_v := round((v_pool::numeric * rec.hari) / v_hari_tot);
    END IF;
    v_sisa := v_sisa - v_v;
    UPDATE _pg_orang o SET gaji = v_v WHERE o.email = rec.email;
  END LOOP;

  SELECT o.hari, o.gaji INTO v_hari_saya, v_gaji
  FROM _pg_orang o WHERE o.email = v_email;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Akun gudang tidak ditemukan.';
  END IF;
  v_hari_saya := COALESCE(v_hari_saya, 0);
  v_gaji := COALESCE(v_gaji, 0);

  SELECT g.nilai INTO v_kb
  FROM public.gaji_kasbon_minggu g
  WHERE g.senin = v_senin AND lower(btrim(g.email)) = v_email;
  v_kb := COALESCE(v_kb, 0);

  senin := v_senin;
  sabtu := v_sabtu;
  rute := v_rute;
  nama := v_nama;
  net_actual := v_net_a;
  net_target := v_net_t;
  pct_net := v_pct;
  rasio_actual := v_rasio_a;
  rasio_target := v_rasio_t;
  pct_rasio := CASE WHEN v_rasio_t = 0 THEN 0 ELSE v_rasio_a / v_rasio_t END;
  omset_actual := v_omset_a;
  omset_target := v_omset_t;
  pct_omset := CASE WHEN v_omset_t = 0 THEN 0 ELSE v_omset_a::numeric / v_omset_t END;
  hari := v_hari_saya;
  hari_target := 6;
  pct_hari := v_hari_saya::numeric / 6;
  bop_actual := COALESCE(v_bop_a, 0);
  bop_target := COALESCE(v_bop_t, 0);
  pct_bop := CASE WHEN coalesce(v_bop_t, 0) = 0 THEN 0 ELSE v_bop_a::numeric / v_bop_t END;
  gaji := v_gaji;
  kasbon := v_kb;
  terima := v_gaji - v_kb;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_gaji_minggu(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gudang_gaji_minggu(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gudang_gaji_minggu(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.gudang_gaji_minggu(date) IS
  'Benefit gudang: rasio/omset total semua rute; gaji dari net perusahaan × slot.';



REVOKE ALL ON FUNCTION public.gaji_pakai_excel(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_pakai_excel(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_mround(numeric, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_mround(numeric, bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_baca_patokan(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_baca_patokan(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_target_pada(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_target_pada(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_setelan_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_setelan_minggu(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint,
  bigint, numeric, numeric, numeric
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint,
  bigint, numeric, numeric, numeric
) TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
