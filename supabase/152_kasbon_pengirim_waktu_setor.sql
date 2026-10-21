-- Kasbon tampil = GREATEST(overlay, setoran_pengirim + public.kasbon).
-- Pengirim: D=supir, H=kenek; waktu setor + tanggal buku Senin–Sabtu.
-- Overlay tidak boleh lebih kecil dari lapangan. Overlay 0 dihapus.
-- Jalankan SETELAH 148. Boleh diulang.

CREATE OR REPLACE FUNCTION public.gaji_kasbon_orang(p_email text, p_senin date)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_sabtu date;
  v_setor bigint := 0;
  v_opname bigint := 0;
  v_overlay bigint := 0;
BEGIN
  IF v_email = '' OR p_senin IS NULL THEN
    RETURN 0;
  END IF;
  v_sabtu := p_senin + 5;

  SELECT coalesce(sum(
    CASE
      WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'D'
        THEN s.kasbon_supir
      WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'H'
        THEN s.kasbon_kenek
      ELSE 0
    END
  ), 0)::bigint
  INTO v_setor
  FROM public.users u
  JOIN public.setoran_pengirim s
    ON s.rute_pengirim = CASE
      WHEN length(btrim(coalesce(u.rute, ''))) > 1
        AND upper(right(btrim(u.rute), 1)) IN ('D', 'H')
        THEN left(btrim(u.rute), char_length(btrim(u.rute)) - 1)
      ELSE btrim(coalesce(u.rute, ''))
    END
  JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
  WHERE u.peran = 'pengirim'
    AND lower(btrim(u.email)) = v_email
    AND (timezone('Asia/Jakarta', s.waktu_setor))::date >= p_senin
    AND (timezone('Asia/Jakarta', s.waktu_setor))::date <= v_sabtu
    AND b.tanggal >= p_senin
    AND b.tanggal <= v_sabtu;

  SELECT coalesce(sum(k.nilai), 0)::bigint INTO v_opname
  FROM public.kasbon k
  JOIN public.setoran_buku b ON b.id = k.id_setoran_buku
  WHERE lower(btrim(k.email)) = v_email
    AND b.tanggal >= p_senin
    AND b.tanggal <= v_sabtu;

  SELECT g.nilai INTO v_overlay
  FROM public.gaji_kasbon_minggu g
  WHERE g.senin = p_senin
    AND lower(btrim(g.email)) = v_email
    AND g.nilai > 0
  LIMIT 1;

  RETURN GREATEST(
    COALESCE(v_setor, 0) + COALESCE(v_opname, 0),
    COALESCE(v_overlay, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_gaji_kasbon(p_senin date, p_sabtu date)
RETURNS TABLE (email text, nilai bigint)
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
  WITH opname AS (
    SELECT
      lower(btrim(k.email)) AS email,
      sum(k.nilai)::bigint AS n
    FROM public.kasbon k
    JOIN public.setoran_buku b ON b.id = k.id_setoran_buku
    WHERE b.tanggal >= p_senin
      AND b.tanggal <= p_sabtu
    GROUP BY lower(btrim(k.email))
  ),
  kirim AS (
    SELECT
      lower(btrim(u.email)) AS email,
      sum(
        CASE
          WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'D'
            THEN s.kasbon_supir
          WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'H'
            THEN s.kasbon_kenek
          ELSE 0
        END
      )::bigint AS n
    FROM public.users u
    JOIN public.setoran_pengirim s
      ON s.rute_pengirim = CASE
        WHEN length(btrim(coalesce(u.rute, ''))) > 1
          AND upper(right(btrim(u.rute), 1)) IN ('D', 'H')
          THEN left(btrim(u.rute), char_length(btrim(u.rute)) - 1)
        ELSE btrim(coalesce(u.rute, ''))
      END
    JOIN public.setoran_buku b ON b.id = s.id_setoran_buku
    WHERE u.peran = 'pengirim'
      AND (timezone('Asia/Jakarta', s.waktu_setor))::date >= p_senin
      AND (timezone('Asia/Jakarta', s.waktu_setor))::date <= p_sabtu
      AND b.tanggal >= p_senin
      AND b.tanggal <= p_sabtu
    GROUP BY lower(btrim(u.email))
  )
  SELECT
    x.email,
    sum(x.n)::bigint
  FROM (
    SELECT k.email, k.n FROM kirim k
    UNION ALL
    SELECT o.email, o.n FROM opname o
  ) x
  GROUP BY x.email
  HAVING sum(x.n) <> 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_gaji_kasbon_minggu(p_senin date)
RETURNS TABLE (email text, nilai bigint)
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
  IF p_senin IS NULL THEN
    RAISE EXCEPTION 'Senin minggu kosong.';
  END IF;

  RETURN QUERY
  SELECT lower(btrim(g.email)), g.nilai
  FROM public.gaji_kasbon_minggu g
  WHERE g.senin = p_senin
    AND g.nilai > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_gaji_kasbon_minggu_simpan(p_senin date, p_isi jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  el jsonb;
  v_email text;
  v_nilai bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_senin IS NULL THEN
    RAISE EXCEPTION 'Senin minggu kosong.';
  END IF;
  IF p_isi IS NULL OR jsonb_typeof(p_isi) <> 'array' THEN
    RAISE EXCEPTION 'Isi kasbon gaji tidak sah.';
  END IF;

  FOR el IN SELECT jsonb_array_elements(p_isi)
  LOOP
    v_email := lower(btrim(COALESCE(el ->> 'email', '')));
    IF v_email = '' THEN
      CONTINUE;
    END IF;
    v_nilai := GREATEST(COALESCE((el ->> 'nilai')::bigint, 0), 0);
    IF v_nilai = 0 THEN
      DELETE FROM public.gaji_kasbon_minggu g
      WHERE g.senin = p_senin AND lower(btrim(g.email)) = v_email;
      CONTINUE;
    END IF;

    INSERT INTO public.gaji_kasbon_minggu (senin, email, nilai)
    VALUES (p_senin, v_email, v_nilai)
    ON CONFLICT (senin, email) DO UPDATE SET
      nilai = EXCLUDED.nilai;
  END LOOP;
END;
$$;

DELETE FROM public.gaji_kasbon_minggu WHERE nilai = 0;

REVOKE ALL ON FUNCTION public.gaji_kasbon_orang(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_kasbon_orang(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_kasbon(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon(date, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_kasbon_minggu(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon_minggu(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_kasbon_minggu_simpan(date, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon_minggu_simpan(date, jsonb)
  TO authenticated, postgres, service_role;

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

  v_kb := COALESCE(public.gaji_kasbon_orang(v_email, v_senin), 0);

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

  v_kb := COALESCE(public.gaji_kasbon_orang(v_email, v_senin), 0);

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
  'Benefit gudang: rasio/omset total semua rute; gaji dari net perusahaan x slot.';


NOTIFY pgrst, 'reload schema';

