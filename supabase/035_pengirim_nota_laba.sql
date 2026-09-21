-- Kartu nota pengirim: laba per tahap untuk rasio % (sama seperti sales/gudang).
-- RETURNS TABLE berubah → DROP dulu.

DROP FUNCTION IF EXISTS public.pengirim_nota_toko(date, text);

CREATE FUNCTION public.pengirim_nota_toko(
  p_tanggal date,
  p_id_pelanggan text
)
RETURNS TABLE (
  id_transaksi text,
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
  v_sales text[];
  v_hari date;
  v_today date;
  v_id text;
  v_id_buku bigint;
  v_id_buka bigint;
  v_tgl_buka date;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  IF p_tanggal IS NULL OR v_id = '' THEN
    RAISE EXCEPTION 'Tanggal dan toko wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();
  v_hari := p_tanggal;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;

  SELECT b.id, b.tanggal INTO v_id_buka, v_tgl_buka
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  LIMIT 1;
  IF v_id_buka IS NOT NULL AND (v_hari = v_today OR v_hari = v_tgl_buka) THEN
    v_id_buku := v_id_buka;
  ELSE
    SELECT b.id INTO v_id_buku
    FROM public.setoran_buku b
    WHERE b.tanggal = v_hari
    ORDER BY b.id DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    t.id_transaksi,
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
  WHERE t.rute = ANY (v_sales)
    AND t.id_pelanggan = v_id
    AND t.waktu_packed IS NOT NULL
    AND (
      (t.status = 'dikirim' AND v_hari = v_today)
      OR (
        t.status IN ('terkirim', 'batal')
        AND t.waktu_actual IS NOT NULL
        AND CASE
          WHEN v_id_buku IS NOT NULL THEN t.id_setoran_buku = v_id_buku
          ELSE (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
        END
      )
    )
  GROUP BY
    t.id_transaksi, t.status, t.pending, t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_nota_toko(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_toko(date, text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
