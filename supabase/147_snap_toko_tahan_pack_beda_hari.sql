-- Snapshot jumlah toko per rute SEBELUM pindah rute (gaji/ringkasan minggu < 12-10-2026).
-- Packing nota ketik ≠ tanggal buku terbuka ditolak (Senin tidak nempel buku 10).
-- Nota Minggu boleh packing di buku Sabtu yang masih terbuka (siklus Sabtu→Senin).
-- Nota yang SUDAH punya id_setoran_buku tetap boleh ubah packing.
-- Rumus gaji Excel TIDAK di sini. Jangan UPDATE pelanggan di sini.
-- Jalankan SETELAH packing malam buku 10 selesai. Boleh diulang:
-- snapshot hanya diisi jika rute belum ada (jangan timpa setelah pindah rute).

CREATE TABLE IF NOT EXISTS public.gaji_toko_rute_snap (
  rute text PRIMARY KEY,
  n_toko integer NOT NULL CHECK (n_toko >= 0)
);

COMMENT ON TABLE public.gaji_toko_rute_snap IS
  'Jumlah toko aktif per rute sebelum pindah rute 12-10-2026. Untuk gaji/ringkasan minggu lama.';

ALTER TABLE public.gaji_toko_rute_snap ENABLE ROW LEVEL SECURITY;

INSERT INTO public.gaji_toko_rute_snap (rute, n_toko)
SELECT
  btrim(p.rute) AS rute,
  count(*)::integer AS n_toko
FROM public.pelanggan p
WHERE COALESCE(p.aktif, true)
  AND btrim(p.id_pelanggan) <> ''
  AND p.id_pelanggan NOT LIKE 'TMP%'
  AND nullif(btrim(p.rute), '') IS NOT NULL
GROUP BY btrim(p.rute)
ON CONFLICT (rute) DO NOTHING;

CREATE OR REPLACE FUNCTION public.gaji_n_toko_rute(p_rute text, p_senin date)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer;
BEGIN
  IF p_senin IS NOT NULL AND p_senin < DATE '2026-10-12' THEN
    SELECT s.n_toko INTO v_n
    FROM public.gaji_toko_rute_snap s
    WHERE s.rute = btrim(COALESCE(p_rute, ''));
    IF FOUND THEN
      RETURN GREATEST(COALESCE(v_n, 0), 0);
    END IF;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.pelanggan p
  WHERE btrim(p.rute) = btrim(COALESCE(p_rute, ''))
    AND COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%';
  RETURN GREATEST(COALESCE(v_n, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_n_toko_semua(p_senin date)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer;
BEGIN
  IF p_senin IS NOT NULL AND p_senin < DATE '2026-10-12' THEN
    SELECT coalesce(sum(s.n_toko), 0)::integer INTO v_n
    FROM public.gaji_toko_rute_snap s
    WHERE s.rute IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );
    IF COALESCE(v_n, 0) > 0 THEN
      RETURN v_n;
    END IF;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(p.rute, '')) IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );
  RETURN GREATEST(COALESCE(v_n, 0), 0);
END;
$$;

REVOKE ALL ON FUNCTION public.gaji_n_toko_rute(text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_n_toko_rute(text, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_n_toko_rute(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_n_toko_semua(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_n_toko_semua(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_n_toko_semua(date)
  TO authenticated, postgres, service_role;

-- Tutup celah 104: order hari ini tidak boleh nempel buku terbuka beda tanggal.
CREATE OR REPLACE FUNCTION public.transaksi_tolak_beda_hari_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_tgl date;
  v_order date;
  v_tutup boolean;
BEGIN
  IF NEW.id_setoran_buku IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.id_setoran_buku IS NOT DISTINCT FROM NEW.id_setoran_buku THEN
    RETURN NEW;
  END IF;
  IF current_setting('obos.boleh_pindah_pending', true) = 'on' THEN
    RETURN NEW;
  END IF;

  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = NEW.id_setoran_buku;
  IF v_tgl IS NULL OR NEW.waktu_order IS NULL THEN
    RETURN NEW;
  END IF;

  v_order := (NEW.waktu_order AT TIME ZONE 'Asia/Jakarta')::date;
  IF v_order IS NOT DISTINCT FROM v_tgl THEN
    RETURN NEW;
  END IF;

  -- Siklus Sabtu→Senin: nota Minggu boleh packing di buku Sabtu yang belum tutup.
  IF NOT COALESCE(v_tutup, false)
     AND EXTRACT(ISODOW FROM v_order)::int = 7
     AND EXTRACT(ISODOW FROM v_tgl)::int = 6
     AND v_order = v_tgl + 1 THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION
    'Nota ketik % belum bisa packing di buku %. Tutup buku itu dulu.',
    to_char(v_order, 'DD/MM'),
    to_char(v_tgl, 'DD/MM');
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
  SELECT
    COALESCE(t.target_omset, 0),
    COALESCE(t.target_persen_laba, 0)
  INTO v_omset, v_persen
  FROM public.target_sales t
  WHERE lower(trim(t.email)) = p_email;

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

CREATE OR REPLACE FUNCTION public._admin_dashboard_jumlah(
  p_rute jsonb,
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
  v_bobot numeric := 0;
  v_persen numeric := 0;
  v_n integer := 0;
  v_toko integer := 0;
  v_toko_hari integer := 0;
  v_m jsonb;
  v_h jsonb;
  el jsonb;
BEGIN
  FOR el IN SELECT jsonb_array_elements(COALESCE(p_rute, '[]'::jsonb))
  LOOP
    v_n := v_n + 1;
    v_omset := v_omset + COALESCE((el ->> 'target_omset')::bigint, 0);
    v_bobot := v_bobot
      + COALESCE((el ->> 'target_omset')::numeric, 0)
      * COALESCE((el ->> 'target_persen')::numeric, 0);
    v_persen := v_persen + COALESCE((el ->> 'target_persen')::numeric, 0);
  END LOOP;

  IF v_omset > 0 THEN
    v_persen := v_bobot / v_omset;
  ELSIF v_n > 0 THEN
    v_persen := v_persen / v_n;
  ELSE
    v_persen := 0;
  END IF;

  v_toko := public.gaji_n_toko_semua(p_senin);

  SELECT count(*)::integer
  INTO v_toko_hari
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(p.visit, '')) = p_nama_hari
    AND btrim(COALESCE(p.rute, '')) IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );

  v_m := public._admin_dashboard_capaian_semua(p_senin, p_sabtu, v_toko);
  v_h := public._admin_dashboard_capaian_semua(p_hari, p_hari, v_toko_hari);

  RETURN jsonb_build_object(
    'rute', '',
    'nama', 'Total',
    'target_omset', v_omset,
    'target_persen', v_persen,
    'minggu', v_m,
    'hari', v_h
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.salesman_ringkas(p_dari date, p_sampai date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_nama text;
  v_email text;
  v_toko integer := 1;
  v_omset bigint := 0;
  v_persen numeric := 0;
  v_cap jsonb;
  v_senin date;
BEGIN
  IF NOT public.sales_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun sales yang boleh melihat ringkasan ini.';
  END IF;
  IF p_dari IS NULL OR p_sampai IS NULL OR p_sampai < p_dari THEN
    RAISE EXCEPTION 'Rentang tanggal ringkasan tidak sah.';
  END IF;

  SELECT
    btrim(u.rute),
    coalesce(nullif(btrim(u.nama), ''), btrim(u.email)),
    lower(btrim(u.email))
  INTO v_rute, v_nama, v_email
  FROM public.users u
  WHERE u.peran = 'sales'
    AND lower(btrim(u.email)) = public.email_jwt()
  LIMIT 1;

  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Akun sales belum punya rute.';
  END IF;

  SELECT COALESCE(t.target_omset, 0), COALESCE(t.target_persen_laba, 0)
  INTO v_omset, v_persen
  FROM public.target_sales t
  WHERE lower(trim(t.email)) = v_email;

  v_senin := p_dari - ((EXTRACT(ISODOW FROM p_dari)::int) - 1);

  IF p_dari IS NOT DISTINCT FROM p_sampai THEN
    SELECT count(*)::integer
    INTO v_toko
    FROM public.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(p.id_pelanggan) <> ''
      AND p.id_pelanggan NOT LIKE 'TMP%'
      AND btrim(COALESCE(p.visit, '')) = public.hari_visit_nama(p_dari);
  ELSE
    v_toko := public.gaji_n_toko_rute(v_rute, v_senin);
  END IF;
  v_toko := GREATEST(COALESCE(v_toko, 0), 1);

  v_cap := public._admin_dashboard_capaian(v_rute, p_dari, p_sampai, v_toko);

  RETURN coalesce(v_cap, '{}'::jsonb) || jsonb_build_object(
    'rute', v_rute,
    'nama', v_nama,
    'target_omset', v_omset,
    'target_persen', COALESCE(v_persen, 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.salesman_ringkas(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.salesman_ringkas(date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.salesman_ringkas(date, date)
  TO authenticated, postgres, service_role;

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

  v_toko := public.gaji_n_toko_rute(v_rute, v_senin);

  v_cap := public._admin_dashboard_capaian(
    v_rute,
    v_senin,
    v_sabtu,
    GREATEST(v_toko, 1)
  );
  v_ec := COALESCE((v_cap->>'ec_actual')::int, 0);
  v_visit := COALESCE((v_cap->>'visit')::int, 0);

  IF v_toko <= 0 THEN
    v_ben_v := 0;
    v_ben_e := 0;
  ELSE
    v_ben_v := round((v_sales_visit::numeric * v_visit) / v_toko);
    v_ben_e := round((v_sales_ec::numeric * v_ec) / v_toko);
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
  'Omset/rasio per buku; n_toko minggu lama dari snapshot sampai 12-10-2026.';

NOTIFY pgrst, 'reload schema';
