-- Kalender "hari ini" memakai buku terbuka meski label tanggal berurutan beda
-- (mis. buku 24, order/packing 25). Hidup hanya hari ini atau H+1, selaras kunci malam.
-- Extra packing = toko bukan jadwal pada hari order Jakarta.
-- Jalankan SETELAH 105. SQL Editor → Run. Boleh diulang.

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
  v_today date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesi tidak aktif';
  END IF;

  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;

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
    IF v_hari = v_today AND v_hari <= v_tgl + 1 THEN
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
  laba_actual bigint,
  extra boolean
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

  SELECT x.id, x.hidup INTO v_id, v_hidup
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
    ), 0)::bigint,
    (NOT public.toko_jadwal_pada(
      t.id_pelanggan,
      (timezone('Asia/Jakarta', t.waktu_order))::date,
      NULL
    )) AS extra
  FROM public.transaksi t
  LEFT JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
  WHERE t.rute = p_rute
    AND public.gudang_nota_ikut_buku(
      v_id, v_tgl, v_hidup, t.id_setoran_buku, t.waktu_order
    )
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_buku_untuk_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_untuk_hari(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gudang_nota_rute(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_rute(date, text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
