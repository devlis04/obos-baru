-- Ringkasan setoran hari ini (omset + laba + pending) untuk sheet pengirim.
-- Jalankan SETELAH 033. Boleh diulang.

CREATE OR REPLACE FUNCTION public.pengirim_ringkas_hari(p_tanggal date)
RETURNS TABLE (
  jumlah_toko integer,
  jumlah_nota integer,
  wajib_kunci integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_pending bigint,
  omset_retur bigint,
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
  v_id_buku bigint;
  v_id_buka bigint;
  v_tgl_buka date;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal kosong';
  END IF;

  v_sales := public.pengirim_rute_sales();
  v_hari := p_tanggal;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  IF cardinality(v_sales) IS NULL OR cardinality(v_sales) = 0 THEN
    RETURN;
  END IF;

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
  WITH nota AS (
    SELECT t.*
    FROM public.transaksi t
    WHERE t.rute = ANY (v_sales)
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
  ),
  item AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.status,
      n.pending,
      coalesce(sum(i.subtotal_jual_order), 0) AS jual_order,
      coalesce(sum(i.subtotal_beli_order), 0) AS beli_order,
      coalesce(sum(i.subtotal_jual_packed), 0) AS jual_packed,
      coalesce(sum(i.subtotal_beli_packed), 0) AS beli_packed,
      coalesce(sum(i.subtotal_jual_actual), 0) AS jual_actual,
      coalesce(sum(i.subtotal_beli_actual), 0) AS beli_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY n.id_transaksi, n.id_pelanggan, n.status, n.pending
  )
  SELECT
    count(DISTINCT i.id_pelanggan)::integer,
    count(*)::integer,
    count(*) FILTER (WHERE i.status = 'dikirim' AND NOT i.pending)::integer,
    coalesce(sum(i.jual_order), 0)::bigint,
    coalesce(sum(i.jual_packed), 0)::bigint,
    coalesce(sum(CASE WHEN i.status = 'batal' THEN 0 ELSE i.jual_actual END), 0)::bigint,
    coalesce(sum(CASE WHEN i.status = 'batal' THEN i.jual_packed ELSE 0 END), 0)::bigint,
    coalesce(sum(CASE WHEN i.pending THEN i.jual_packed ELSE 0 END), 0)::bigint,
    0::bigint,
    coalesce(sum(i.jual_order - i.beli_order), 0)::bigint,
    coalesce(sum(i.jual_packed - i.beli_packed), 0)::bigint,
    coalesce(sum(
      CASE WHEN i.status = 'batal' THEN 0 ELSE i.jual_actual - i.beli_actual END
    ), 0)::bigint
  FROM item i;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_ringkas_hari(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_ringkas_hari(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
