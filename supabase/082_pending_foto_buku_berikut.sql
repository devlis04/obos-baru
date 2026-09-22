-- Pending seperti admin lama: foto di buku tutup, nota jadi kiriman buku berikutnya
-- (pending dilepas, cap pindah). Halaman buku lama tetap pending via foto/snapshot.
-- Juga mengembalikan filter nota biasa (081 terlalu berat, bikin pilih tanggal gagal).
-- Jalankan SETELAH 081. Boleh diulang.
-- SQL editor timeout / 502: jangan ulang 082. Jalankan 083_pindah_pending_tanpa_timeout.sql.

CREATE TABLE IF NOT EXISTS public.setoran_buku_pending_foto (
  id_setoran_buku bigint NOT NULL
    REFERENCES public.setoran_buku (id) ON DELETE CASCADE,
  id_transaksi text NOT NULL,
  PRIMARY KEY (id_setoran_buku, id_transaksi)
);

CREATE INDEX IF NOT EXISTS setoran_buku_pending_foto_nota_idx
  ON public.setoran_buku_pending_foto (id_transaksi);

REVOKE ALL ON TABLE public.setoran_buku_pending_foto FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.setoran_buku_pending_foto
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.setoran_pending_foto_catat(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  INSERT INTO public.setoran_buku_pending_foto (id_setoran_buku, id_transaksi)
  SELECT p_id, t.id_transaksi
  FROM public.transaksi t
  WHERE t.id_setoran_buku = p_id
    AND t.status = 'dikirim'
    AND COALESCE(t.pending, false)
  ON CONFLICT DO NOTHING;
END;
$$;

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
BEGIN
  IF NEW.id_setoran_buku IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.id_setoran_buku IS NOT DISTINCT FROM NEW.id_setoran_buku THEN
    RETURN NEW;
  END IF;
  -- Pending foto: nota sisa buku tutup jadi kiriman buku berikutnya.
  IF current_setting('obos.boleh_pindah_pending', true) = 'on' THEN
    RETURN NEW;
  END IF;

  SELECT b.tanggal INTO v_tgl
  FROM public.setoran_buku b
  WHERE b.id = NEW.id_setoran_buku;
  IF v_tgl IS NULL OR NEW.waktu_order IS NULL THEN
    RETURN NEW;
  END IF;

  v_order := (NEW.waktu_order AT TIME ZONE 'Asia/Jakarta')::date;
  IF v_order IS DISTINCT FROM v_tgl THEN
    RAISE EXCEPTION
      'Nota ini orderan %. Buku terbuka untuk orderan %. Tutup buku dulu.',
      to_char(v_order, 'FMDD-MM-YYYY'),
      to_char(v_tgl, 'FMDD-MM-YYYY');
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_pending_foto_pindah(p_baru bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF p_baru IS NULL THEN
    RETURN;
  END IF;
  PERFORM set_config('obos.boleh_pindah_pending', 'on', true);
  UPDATE public.transaksi t
  SET
    id_setoran_buku = p_baru,
    pending = false
  FROM public.setoran_buku_pending_foto f
  JOIN public.setoran_buku b ON b.id = f.id_setoran_buku
  WHERE b.ditutup
    AND f.id_transaksi = t.id_transaksi
    AND t.status = 'dikirim'
    AND COALESCE(t.pending, false)
    AND t.id_setoran_buku IS DISTINCT FROM p_baru;
END;
$$;

DO $$
DECLARE
  v_lama bigint;
  v_baru bigint;
BEGIN
  SELECT b.id INTO v_baru
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  FOR v_lama IN
    SELECT b.id
    FROM public.setoran_buku b
    WHERE b.ditutup
    ORDER BY b.id
  LOOP
    PERFORM public.setoran_pending_foto_catat(v_lama);
  END LOOP;

  IF v_baru IS NOT NULL THEN
    PERFORM public.setoran_pending_foto_pindah(v_baru);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_transaksi_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_id_buku IS NOT NULL
    AND (
      p_id_setoran_buku = p_id_buku
      OR (
        p_id_setoran_buku IS NULL
        AND NOT coalesce(p_tutup, false)
        AND (
          p_status = 'dikirim'
          OR (
            p_status IN ('terkirim', 'batal')
            AND p_waktu_actual IS NOT NULL
            AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
          )
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.pengirim_nota_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_order timestamptz,
  p_waktu_actual timestamptz,
  p_tanggal_lihat date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (
      p_id_buku IS NOT NULL
      AND p_id_setoran_buku = p_id_buku
    )
    OR (
      p_tgl IS NOT NULL
      AND p_waktu_order IS NOT NULL
      AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      AND p_id_setoran_buku IS NULL
      AND p_status = 'dikirim'
      AND (p_id_buku IS NULL OR coalesce(p_hidup, false))
    )
    OR (
      p_id_buku IS NULL
      AND p_id_setoran_buku IS NULL
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_setoran_kartu_hidup(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_baris jsonb;
BEGIN
  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'dari_snapshot', false,
      'rute', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(q.baris ORDER BY q.rute_pengirim), '[]'::jsonb)
  INTO v_baris
  FROM (
    SELECT
      p.rute_pengirim,
      jsonb_build_object(
        'rute_pengirim', p.rute_pengirim,
        'kiriman', coalesce(o.kiriman, 0),
        'batal', coalesce(o.batal, 0),
        'pending', coalesce(o.pending, 0),
        'actual', coalesce(o.actual, 0),
        'wajib_kunci', coalesce(o.wajib_kunci, 0),
        'transfer', coalesce(s.jumlah_transfer, 0),
        'tunai', coalesce(s.jumlah_tunai, 0),
        'bop', coalesce(s.jumlah_bop, 0),
        'kasbon', coalesce(s.kasbon_supir, 0) + coalesce(s.kasbon_kenek, 0),
        'kasbon_supir', coalesce(s.kasbon_supir, 0),
        'kasbon_kenek', coalesce(s.kasbon_kenek, 0),
        'nama_supir', coalesce(nm.nama_supir, ''),
        'nama_kenek', coalesce(nm.nama_kenek, ''),
        'retur', coalesce(r.nilai, 0),
        'sudah_setor', s.id IS NOT NULL
      ) AS baris
    FROM (
      SELECT DISTINCT rute_pengirim
      FROM public.rute_peta
    ) p
    LEFT JOIN (
      SELECT
        rp.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS kiriman,
        coalesce(sum(
          public.admin_omset_batal(
            t.status, i.subtotal_jual_packed, i.subtotal_jual_actual
          )
        ), 0)::bigint AS batal,
        coalesce(sum(
          CASE
            WHEN t.pending THEN i.subtotal_jual_packed
            WHEN EXISTS (
              SELECT 1
              FROM public.setoran_buku_pending_foto f
              WHERE f.id_setoran_buku = v_id
                AND f.id_transaksi = t.id_transaksi
            ) THEN i.subtotal_jual_packed
            ELSE 0
          END
        ), 0)::bigint AS pending,
        coalesce(sum(
          CASE
            WHEN t.status = 'batal' THEN 0
            WHEN EXISTS (
              SELECT 1
              FROM public.setoran_buku_pending_foto f
              WHERE f.id_setoran_buku = v_id
                AND f.id_transaksi = t.id_transaksi
            ) THEN 0
            ELSE i.subtotal_jual_actual
          END
        ), 0)::bigint AS actual,
        count(DISTINCT t.id_transaksi) FILTER (
          WHERE t.status = 'dikirim' AND NOT t.pending
        )::integer AS wajib_kunci
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
      WHERE t.waktu_packed IS NOT NULL
        AND (
          public.admin_transaksi_ikut_buku(
            v_id, v_tgl, v_tutup, t.id_setoran_buku, t.status, t.waktu_actual
          )
          OR EXISTS (
            SELECT 1
            FROM public.setoran_buku_pending_foto f
            WHERE f.id_setoran_buku = v_id
              AND f.id_transaksi = t.id_transaksi
          )
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN public.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        public.pengirim_grup_rute(u.rute) AS rute_pengirim,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'D' THEN u.nama END) AS nama_supir,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'H' THEN u.nama END) AS nama_kenek
      FROM public.users u
      WHERE u.peran = 'pengirim'
      GROUP BY public.pengirim_grup_rute(u.rute)
    ) nm ON nm.rute_pengirim = p.rute_pengirim
    LEFT JOIN (
      SELECT
        i.rute_pengirim,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM public.retur_toko i
      WHERE i.id_setoran_buku = v_id
      GROUP BY i.rute_pengirim
    ) r ON r.rute_pengirim = p.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', coalesce(v_tutup, false),
    'dari_snapshot', false,
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_buka_jika_perlu()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_lama date;
BEGIN
  v_id := public.setoran_buku_terbuka();
  IF v_id IS NOT NULL THEN
    v_tgl := public.setoran_tanggal_order_sales(v_id);
    SELECT b.tanggal INTO v_lama
    FROM public.setoran_buku b
    WHERE b.id = v_id;
    IF v_tgl IS NOT NULL AND v_lama IS DISTINCT FROM v_tgl THEN
      UPDATE public.setoran_buku
      SET tanggal = v_tgl
      WHERE id = v_id;
      UPDATE public.stok_opname
      SET tanggal = v_tgl
      WHERE id_setoran_buku = v_id;
    END IF;
    RETURN v_id;
  END IF;

  v_tgl := public.setoran_tanggal_order_sales(NULL);

  INSERT INTO public.setoran_buku (tanggal, ditutup)
  VALUES (v_tgl, false)
  RETURNING id INTO v_id;

  INSERT INTO public.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
  )
  SELECT
    v_id,
    v_tgl,
    b.id_barang,
    b.nama_barang,
    GREATEST(COALESCE(b.stok, 0), 0),
    0
  FROM public.barang b
  WHERE btrim(b.id_barang) <> '';

  PERFORM public.setoran_pending_foto_pindah(v_id);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_tutup_setoran_buku()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_sku text;
  v_n integer;
  v_fisik integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menutup buku.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);
  IF v_n > 0 THEN
    RAISE EXCEPTION
      'Masih ada % nota dikirim. Pengirim selesaikan dulu, lalu tutup buku.',
      v_n;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'pengirim')
    AND a.id_setoran_buku = v_id;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada absensi yang belum pulang. Scan pulang dulu, lalu tutup buku.';
  END IF;

  SELECT count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer
  INTO v_fisik
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id;
  IF COALESCE(v_fisik, 0) <= 0 THEN
    RAISE EXCEPTION 'Opname fisik belum diisi. Gudang isi fisik dulu, lalu tutup buku.';
  END IF;

  SELECT so.id_barang
  INTO v_sku
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) < 0
    AND so.putusan IS DISTINCT FROM 'kasbon'
    AND so.putusan IS DISTINCT FROM 'beban'
  ORDER BY lower(so.nama_barang)
  LIMIT 1;
  IF v_sku IS NOT NULL THEN
    RAISE EXCEPTION
      'Masih ada selisih kurang belum diputuskan (SKU %). Kasbon atau potong margin dulu.',
      v_sku;
  END IF;

  UPDATE public.stok_opname so
  SET
    putusan = 'margin_plus',
    nilai_putusan = round(so.selisih * GREATEST(COALESCE(b.harga_beli, 0), 0))::integer,
    harga_beli_putusan = GREATEST(COALESCE(b.harga_beli, 0), 0)::integer,
    qty_selisih_putusan = so.selisih,
    kasbon_email = NULL,
    kasbon_nama = NULL,
    waktu_putusan = clock_timestamp()
  FROM public.barang b
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) > 0;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  PERFORM public.setoran_pending_foto_catat(v_id);

  UPDATE public.setoran_buku
  SET
    ditutup = true,
    waktu_tutup = clock_timestamp()
  WHERE id = v_id
    AND NOT ditutup;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_pending_foto_catat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_pending_foto_catat(bigint)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_pending_foto_pindah(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_pending_foto_pindah(bigint)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_kartu_hidup(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu_hidup(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buka_jika_perlu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buka_jika_perlu()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_tutup_setoran_buku() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tutup_setoran_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
