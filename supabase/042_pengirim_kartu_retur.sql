-- Kartu toko pengirim: nilai retur untuk chip di beranda.
-- Jalankan SETELAH 040. Boleh diulang.

DROP FUNCTION IF EXISTS public.pengirim_kartu_toko(date);

CREATE FUNCTION public.pengirim_kartu_toko(p_tanggal date)
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute_sales text,
  latitude double precision,
  longitude double precision,
  jumlah_nota integer,
  omset_order bigint,
  omset_packed bigint,
  omset_actual bigint,
  omset_batal bigint,
  omset_retur bigint,
  wajib_kunci integer,
  ada_dikirim boolean,
  ada_pending boolean,
  ada_batal boolean,
  ada_terkirim boolean,
  waktu_masuk timestamptz,
  waktu_keluar timestamptz
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
  v_grup text;
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
  v_grup := public.pengirim_grup_rute(public.pengirim_rute_saya());
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
        (v_id_buku IS NOT NULL AND t.id_setoran_buku = v_id_buku)
        OR (
          t.status = 'dikirim'
          AND t.id_setoran_buku IS NULL
          AND v_hari = v_today
        )
        OR (
          v_id_buku IS NULL
          AND t.status IN ('terkirim', 'batal')
          AND t.waktu_actual IS NOT NULL
          AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_hari
        )
      )
  ),
  hitung AS (
    SELECT
      n.id_pelanggan,
      max(n.nama_pelanggan) AS nama_pelanggan,
      max(n.rute) AS rute_sales,
      count(*)::integer AS jumlah_nota,
      coalesce(sum((
        SELECT coalesce(sum(i.subtotal_jual_order), 0)
        FROM public.v_transaksi_item i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_order,
      coalesce(sum((
        SELECT coalesce(sum(i.subtotal_jual_packed), 0)
        FROM public.v_transaksi_item i
        WHERE i.id_transaksi = n.id_transaksi
      )), 0)::bigint AS omset_packed,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN 0
             ELSE (
               SELECT coalesce(sum(i.subtotal_jual_actual), 0)
               FROM public.v_transaksi_item i
               WHERE i.id_transaksi = n.id_transaksi
             )
        END
      ), 0)::bigint AS omset_actual,
      coalesce(sum(
        CASE WHEN n.status = 'batal' THEN (
          SELECT coalesce(sum(i.subtotal_jual_packed), 0)
          FROM public.v_transaksi_item i
          WHERE i.id_transaksi = n.id_transaksi
        ) ELSE 0 END
      ), 0)::bigint AS omset_batal,
      count(*) FILTER (
        WHERE n.status = 'dikirim' AND NOT n.pending
      )::integer AS wajib_kunci,
      bool_or(n.status = 'dikirim') AS ada_dikirim,
      bool_or(n.pending) AS ada_pending,
      bool_or(n.status = 'batal') AS ada_batal,
      bool_or(n.status = 'terkirim') AS ada_terkirim
    FROM nota n
    GROUP BY n.id_pelanggan
  ),
  retur AS (
    SELECT
      i.id_pelanggan,
      coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS omset_retur
    FROM public.retur_toko i
    WHERE v_id_buku IS NOT NULL
      AND i.id_setoran_buku = v_id_buku
      AND i.rute_pengirim = v_grup
    GROUP BY i.id_pelanggan
  )
  SELECT
    h.id_pelanggan,
    h.nama_pelanggan,
    h.rute_sales,
    pl.latitude,
    pl.longitude,
    h.jumlah_nota,
    h.omset_order,
    h.omset_packed,
    h.omset_actual,
    h.omset_batal,
    coalesce(r.omset_retur, 0)::bigint,
    h.wajib_kunci,
    h.ada_dikirim,
    h.ada_pending,
    h.ada_batal,
    h.ada_terkirim,
    k.waktu_masuk,
    k.waktu_keluar
  FROM hitung h
  LEFT JOIN retur r ON r.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.pelanggan pl ON pl.id_pelanggan = h.id_pelanggan
  LEFT JOIN public.kunjungan_pengirim k
    ON k.id_pelanggan = h.id_pelanggan
   AND k.rute_pengirim = v_grup
   AND k.tanggal = v_hari
  ORDER BY lower(h.nama_pelanggan), h.id_pelanggan;
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_kartu_toko(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_kartu_toko(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
