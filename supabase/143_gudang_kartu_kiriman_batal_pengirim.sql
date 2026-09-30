-- Kartu packing: Kiriman tetap menghitung batal pengirim (sudah ada qty packed).
-- Batal gudang qty 0 tidak naikkan Kiriman. Actual tetap tanpa batal.
-- Order tetap seperti 142. Jalankan SETELAH 142. Boleh diulang. Jangan ubah admin.

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
    SELECT
      t.id_transaksi,
      t.rute,
      t.status,
      t.waktu_packed,
      (
        t.waktu_packed IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM public.transaksi_items x
          WHERE x.id_transaksi = t.id_transaksi
            AND x.qty_packed IS NOT NULL
        )
      ) AS punya_packed,
      (
        t.status = 'batal'
        AND t.waktu_packed IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM public.transaksi_items x
          WHERE x.id_transaksi = t.id_transaksi
            AND coalesce(x.qty_packed, 0) > 0
        )
      ) AS batal_gudang
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
      coalesce(sum(i.subtotal_jual_order), 0)::bigint AS omset_order,
      coalesce(sum(i.subtotal_jual_packed) FILTER (
        WHERE n.punya_packed AND NOT n.batal_gudang
      ), 0)::bigint AS omset_packed,
      coalesce(sum(i.subtotal_jual_actual) FILTER (WHERE n.status <> 'batal'), 0)::bigint AS omset_actual,
      coalesce(sum(i.subtotal_jual_order - i.subtotal_beli_order), 0)::bigint AS laba_order,
      coalesce(sum(
        CASE
          WHEN i.qty_packed IS NULL THEN 0
          ELSE coalesce(i.subtotal_jual_packed, 0) - coalesce(i.subtotal_beli_packed, 0)
        END
      ) FILTER (
        WHERE n.punya_packed AND NOT n.batal_gudang
      ), 0)::bigint AS laba_packed,
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

REVOKE ALL ON FUNCTION public.gudang_kartu_rute(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_kartu_rute(date)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.gudang_kartu_rute(date) IS
  'Kartu packing: Order termasuk batal gudang; Kiriman termasuk batal pengirim; Actual tanpa batal.';

NOTIFY pgrst, 'reload schema';
