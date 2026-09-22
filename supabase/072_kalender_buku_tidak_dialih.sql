-- Kalender gudang/pengirim: tanggal yang dipilih = buku hari order itu.
-- Jangan alihkan "hari ini" ke buku terbuka jika tanggal bukunya beda.
-- Jalankan SETELAH 071. Boleh diulang.

CREATE OR REPLACE FUNCTION public.setoran_buku_untuk_hari(p_tanggal date DEFAULT NULL)
RETURNS TABLE (
  id bigint,
  tanggal date,
  ditutup boolean,
  hidup boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hari date;
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_buka bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;

  SELECT b.id INTO v_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  IF p_tanggal IS NULL THEN
    IF v_buka IS NULL THEN
      RETURN;
    END IF;
    SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_buka;
    id := v_id;
    tanggal := v_tgl;
    ditutup := COALESCE(v_tutup, false);
    hidup := true;
    RETURN NEXT;
    RETURN;
  END IF;

  v_hari := p_tanggal;

  IF v_buka IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
      INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_buka;
    IF v_tgl = v_hari THEN
      id := v_id;
      tanggal := v_tgl;
      ditutup := COALESCE(v_tutup, false);
      hidup := true;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.tanggal = v_hari
  ORDER BY b.id DESC
  LIMIT 1;
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  id := v_id;
  tanggal := v_tgl;
  ditutup := COALESCE(v_tutup, false);
  hidup := (v_buka IS NOT NULL AND v_id = v_buka);
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_buku_untuk_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_untuk_hari(date)
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.gudang_nota_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_waktu_order timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_tgl IS NOT NULL
    AND p_waktu_order IS NOT NULL
    AND (
      (p_id_buku IS NOT NULL AND p_id_setoran_buku = p_id_buku)
      OR (
        (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
        AND p_id_setoran_buku IS NULL
        AND (p_id_buku IS NULL OR coalesce(p_hidup, false))
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
  v_id bigint;
  v_tgl date;
  v_hidup boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  SELECT x.id, x.tanggal, x.hidup INTO v_id, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

  RETURN QUERY
  WITH nota AS (
    SELECT t.id_transaksi, t.rute, t.status, t.waktu_packed
    FROM public.transaksi t
    WHERE t.status IS DISTINCT FROM 'batal'
      AND public.gudang_nota_ikut_buku(
        v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
      )
  ),
  hitung AS (
    SELECT
      n.rute,
      count(DISTINCT n.id_transaksi)::integer AS jumlah_nota,
      count(DISTINCT n.id_transaksi) FILTER (
        WHERE n.status IN ('dikirim', 'terkirim') OR n.waktu_packed IS NOT NULL
      )::integer AS sudah_siap,
      coalesce(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS omset_packed,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS omset_actual,
      coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint AS laba_order,
      coalesce(sum(
        CASE
          WHEN i.qty_packed IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
        END
      ), 0)::bigint AS laba_packed,
      coalesce(sum(
        CASE
          WHEN i.qty_actual IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_actual, 0) - coalesce(i.subtotal_beli_actual, 0)
        END
      ), 0)::bigint AS laba_actual
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

CREATE OR REPLACE FUNCTION public.gudang_nota_rute(p_tanggal date, p_rute text)
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
  laba_actual bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_hidup boolean;
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;

  SELECT x.id, x.tanggal, x.hidup INTO v_id, v_tgl, v_hidup
  FROM public.setoran_buku_untuk_hari(p_tanggal) x;
  v_tgl := p_tanggal;
  v_hidup := COALESCE(v_hidup, false);

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
    ), 0)::bigint
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  WHERE t.rute = p_rute
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
    AND public.gudang_nota_ikut_buku(
      v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
    )
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.gudang_nota_ikut_buku(bigint, date, boolean, bigint, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_ikut_buku(bigint, date, boolean, bigint, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_kartu_rute(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_kartu_rute(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_rute(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_rute(date, text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
