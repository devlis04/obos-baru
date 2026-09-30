-- Layar gudang per tanggal kalender, selaras ringkasan:
--   belum cetak = hari ketik;
--   setelah pack = cap buku terbuka (hilang dari hari ketik jika beda);
--   sisa dikirim belum actual hanya di label buku hidup;
--   hari buku tutup: arsip terkirim/batal, bukan antrean dikirim.
-- Jalankan SETELAH 138. Lalu 137. Boleh diulang.

DROP FUNCTION IF EXISTS public.gudang_nota_ikut_buku(bigint, date, boolean, bigint, timestamptz);
DROP FUNCTION IF EXISTS public.gudang_nota_ikut_buku(bigint, date, boolean, bigint, timestamptz, timestamptz, text, timestamptz);
DROP FUNCTION IF EXISTS public.gudang_nota_ikut_buku(date, bigint, boolean, bigint, bigint, timestamptz, timestamptz, text, timestamptz);
DROP FUNCTION IF EXISTS public.gudang_nota_rute(date, text);

CREATE FUNCTION public.gudang_nota_ikut_buku(
  p_lihat date,
  p_id_buku_label bigint,
  p_layar_buku_hidup boolean,
  p_id_buku_hidup bigint,
  p_id_setoran_buku bigint,
  p_waktu_order timestamptz,
  p_waktu_packed timestamptz,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_lihat IS NOT NULL
    AND p_waktu_order IS NOT NULL
    AND (
      (
        p_waktu_packed IS NULL
        AND coalesce(p_status, '') IS DISTINCT FROM 'batal'
        AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_lihat
      )
      OR (
        coalesce(p_layar_buku_hidup, false)
        AND p_id_buku_hidup IS NOT NULL
        AND p_id_setoran_buku = p_id_buku_hidup
        AND p_waktu_packed IS NOT NULL
        AND p_waktu_actual IS NULL
        AND coalesce(p_status, '') = 'dikirim'
      )
      OR (
        coalesce(p_layar_buku_hidup, false)
        AND p_id_buku_hidup IS NOT NULL
        AND p_id_setoran_buku IS NOT NULL
        AND p_id_setoran_buku <> p_id_buku_hidup
        AND p_waktu_packed IS NOT NULL
        AND p_waktu_actual IS NULL
        AND coalesce(p_status, '') = 'dikirim'
      )
      OR (
        p_id_buku_label IS NOT NULL
        AND p_id_setoran_buku = p_id_buku_label
        AND p_waktu_packed IS NOT NULL
        AND (
          p_waktu_actual IS NOT NULL
          OR coalesce(p_status, '') IN ('terkirim', 'batal')
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.gudang_kartu_rute(p_tanggal date)
RETURNS TABLE (
  rute text,
  nama_sales text,
  jumlah_nota integer,
  sudah_siap integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_lihat date;
  v_label bigint;
  v_hidup_id bigint;
  v_hidup_tgl date;
  v_layar_hidup boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_lihat := p_tanggal;

  SELECT b.id INTO v_label
  FROM public.setoran_buku b
  WHERE b.tanggal = v_lihat
  ORDER BY b.id DESC
  LIMIT 1;

  SELECT b.id, b.tanggal INTO v_hidup_id, v_hidup_tgl
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  v_layar_hidup := (v_hidup_id IS NOT NULL AND v_hidup_tgl = v_lihat);

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM public.transaksi t
    WHERE public.gudang_nota_ikut_buku(
      v_lihat, v_label, v_layar_hidup, v_hidup_id,
      t.id_setoran_buku, t.waktu_order, t.waktu_packed, t.status, t.waktu_actual
    )
      AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  ),
  hitung AS (
    SELECT
      n.rute,
      count(DISTINCT n.id_transaksi)::integer AS jumlah_nota,
      count(DISTINCT n.id_transaksi) FILTER (
        WHERE n.status IN ('dikirim', 'terkirim') OR n.waktu_packed IS NOT NULL
      )::integer AS sudah_siap,
      coalesce(sum(i.subtotal_jual_order) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_order,
      coalesce(sum(i.subtotal_jual_packed) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_packed,
      coalesce(sum(i.subtotal_jual_actual) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_actual,
      coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS laba_order,
      coalesce(sum(
        CASE
          WHEN i.qty_packed IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
        END
      ) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS laba_packed,
      coalesce(sum(
        CASE
          WHEN i.qty_actual IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
        END
      ) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS laba_actual
    FROM nota n
    LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.rute
  )
  SELECT
    h.rute,
    coalesce(
      (
        SELECT u.nama
        FROM public.users u
        WHERE u.peran = 'sales'
          AND u.rute = h.rute
        LIMIT 1
      ),
      h.rute
    ),
    h.jumlah_nota,
    h.sudah_siap,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.laba_order,
    h.laba_packed,
    h.laba_actual
  FROM hitung h
  ORDER BY h.rute;
END;
$$;

CREATE FUNCTION public.gudang_nota_rute(p_tanggal date, p_rute text)
RETURNS TABLE (
  id_transaksi text,
  id_pelanggan text,
  nama_pelanggan text,
  status text,
  pending boolean,
  waktu_order timestamptz,
  waktu_packed timestamptz,
  waktu_actual timestamptz,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  laba_order bigint,
  laba_packed bigint,
  laba_actual bigint,
  extra boolean,
  tanggal_buku date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_lihat date;
  v_label bigint;
  v_hidup_id bigint;
  v_hidup_tgl date;
  v_layar_hidup boolean;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;

  v_lihat := p_tanggal;

  SELECT b.id INTO v_label
  FROM public.setoran_buku b
  WHERE b.tanggal = v_lihat
  ORDER BY b.id DESC
  LIMIT 1;

  SELECT b.id, b.tanggal INTO v_hidup_id, v_hidup_tgl
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  v_layar_hidup := (v_hidup_id IS NOT NULL AND v_hidup_tgl = v_lihat);

  RETURN QUERY
  SELECT
    t.id_transaksi,
    t.id_pelanggan,
    t.nama_pelanggan,
    t.status,
    t.pending,
    t.waktu_order,
    t.waktu_packed,
    t.waktu_actual,
    coalesce(sum(i.subtotal_jual_order), 0)::bigint,
    coalesce(sum(i.subtotal_jual_packed), 0)::bigint,
    coalesce(sum(i.subtotal_jual_actual), 0)::bigint,
    coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_packed IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
      END
    ), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN i.qty_actual IS NULL THEN 0
        ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
      END
    ), 0)::bigint,
    (NOT public.toko_jadwal_pada(
      t.id_pelanggan,
      (timezone('Asia/Jakarta', t.waktu_order))::date,
      NULL
    )) AS extra,
    b.tanggal
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  LEFT JOIN public.setoran_buku b ON b.id = t.id_setoran_buku
  WHERE t.rute = p_rute
    AND public.gudang_nota_ikut_buku(
      v_lihat, v_label, v_layar_hidup, v_hidup_id,
      t.id_setoran_buku, t.waktu_order, t.waktu_packed, t.status, t.waktu_actual
    )
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual, b.tanggal
  ORDER BY t.waktu_order DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_nota_ikut_buku(date, bigint, boolean, bigint, bigint, timestamptz, timestamptz, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_ikut_buku(date, bigint, boolean, bigint, bigint, timestamptz, timestamptz, text, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_kartu_rute(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_kartu_rute(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_rute(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_rute(date, text)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.gudang_nota_ikut_buku(date, bigint, boolean, bigint, bigint, timestamptz, timestamptz, text, timestamptz) IS
  'Layar T: order belum cetak hari T; dikirim cap buku hanya di label buku hidup; arsip actual di hari label.';

NOTIFY pgrst, 'reload schema';
