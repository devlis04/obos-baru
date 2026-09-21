-- Daftar packing gudang: jangan tampilkan nota batal sales (belum packing).
-- Batal setelah packing (qty 0 di gudang / batal pengirim) tetap tampil.

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
BEGIN
  IF NOT public.gudang_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF p_tanggal IS NULL OR btrim(COALESCE(p_rute, '')) = '' THEN
    RAISE EXCEPTION 'Tanggal dan rute wajib.';
  END IF;

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
  WHERE (t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal
    AND t.rute = p_rute
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL)
  GROUP BY
    t.id_transaksi, t.id_pelanggan, t.nama_pelanggan, t.status, t.pending,
    t.waktu_order, t.waktu_packed, t.waktu_actual
  ORDER BY t.waktu_order DESC;
END;
$$;
