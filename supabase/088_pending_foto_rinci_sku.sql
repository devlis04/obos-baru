-- Pending buku tutup: rinci SKU kosong + nota hilang jika rute_peta absen.
-- Jalankan SETELAH 087. Pendek. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_setoran_pending_foto_rinci(
  p_jenis text,
  p_rute text,
  p_id_setoran_buku bigint
)
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
  v_rute text;
  v_toko jsonb;
  v_total bigint;
BEGIN
  v_id := p_id_setoran_buku;
  v_rute := nullif(btrim(coalesce(p_rute, '')), '');
  SELECT b.tanggal INTO v_tgl
  FROM public.setoran_buku b
  WHERE b.id = v_id;

  WITH nota AS (
    SELECT
      t.id_transaksi,
      t.id_pelanggan,
      t.nama_pelanggan,
      t.rute AS rute_sales,
      coalesce(nullif(btrim(rp.rute_pengirim), ''), t.rute) AS rute_pengirim,
      t.status
    FROM public.setoran_buku_pending_foto f
    JOIN public.transaksi t ON t.id_transaksi = f.id_transaksi
    LEFT JOIN public.rute_peta rp ON rp.rute_sales = t.rute
    WHERE f.id_setoran_buku = v_id
      AND (
        v_rute IS NULL
        OR coalesce(nullif(btrim(rp.rute_pengirim), ''), t.rute) = v_rute
      )
  ),
  omset AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.nama_pelanggan,
      n.rute_sales,
      n.rute_pengirim,
      coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY
      n.id_transaksi, n.id_pelanggan, n.nama_pelanggan,
      n.rute_sales, n.rute_pengirim
  ),
  sku_item AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.rute_pengirim,
      i.id_barang,
      max(i.nama_barang) AS nama,
      sum(coalesce(i.qty_packed, 0))::integer AS qty,
      sum(coalesce(i.subtotal_jual_packed, 0))::bigint AS nilai
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    WHERE coalesce(i.qty_packed, 0) > 0
    GROUP BY n.id_transaksi, n.id_pelanggan, n.rute_pengirim, i.id_barang
  ),
  sku_nota AS (
    SELECT
      s.id_transaksi,
      jsonb_agg(
        jsonb_build_object(
          'id_barang', s.id_barang,
          'nama', s.nama,
          'qty', s.qty,
          'nilai', s.nilai,
          'qty_packed', s.qty,
          'packed', s.nilai,
          'qty_batal', 0,
          'batal', 0,
          'qty_actual', 0,
          'actual', 0
        )
        ORDER BY s.id_barang
      ) AS sku
    FROM sku_item s
    GROUP BY s.id_transaksi
  ),
  sku_toko AS (
    SELECT
      x.id_pelanggan,
      x.rute_pengirim,
      jsonb_agg(x.sku ORDER BY x.sku->>'id_barang') AS sku
    FROM (
      SELECT
        s.id_pelanggan,
        s.rute_pengirim,
        jsonb_build_object(
          'id_barang', s.id_barang,
          'nama', max(s.nama),
          'qty', sum(s.qty),
          'nilai', sum(s.nilai),
          'qty_packed', sum(s.qty),
          'packed', sum(s.nilai),
          'qty_batal', 0,
          'batal', 0,
          'qty_actual', 0,
          'actual', 0
        ) AS sku
      FROM sku_item s
      GROUP BY s.id_pelanggan, s.rute_pengirim, s.id_barang
    ) x
    GROUP BY x.id_pelanggan, x.rute_pengirim
  )
  SELECT
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id_pelanggan', q.id_pelanggan,
          'nama', q.nama,
          'rute_pengirim', q.rute_pengirim,
          'rute_sales', q.rute_sales,
          'nilai', q.jual_packed,
          'nota', q.n_nota,
          'packed', q.jual_packed,
          'batal', 0,
          'pending', q.jual_packed,
          'actual', 0,
          'retur', 0,
          'status', 'pending',
          'sku', coalesce(q.sku, '[]'::jsonb),
          'nota_list', q.nota_list
        )
        ORDER BY q.nama, q.id_pelanggan
      ),
      '[]'::jsonb
    ),
    coalesce(sum(q.jual_packed), 0)::bigint
  INTO v_toko, v_total
  FROM (
    SELECT
      o.id_pelanggan,
      max(o.nama_pelanggan) AS nama,
      o.rute_pengirim,
      min(o.rute_sales) AS rute_sales,
      count(*)::integer AS n_nota,
      coalesce(sum(o.jual_packed), 0)::bigint AS jual_packed,
      (
        SELECT st.sku FROM sku_toko st
        WHERE st.id_pelanggan = o.id_pelanggan
          AND st.rute_pengirim = o.rute_pengirim
        LIMIT 1
      ) AS sku,
      jsonb_agg(
        jsonb_build_object(
          'id', o.id_transaksi,
          'rute', o.rute_sales,
          'packed', o.jual_packed,
          'batal', 0,
          'pending', o.jual_packed,
          'actual', 0,
          'retur', 0,
          'status', 'pending',
          'sku', coalesce(sn.sku, '[]'::jsonb)
        )
        ORDER BY o.id_transaksi
      ) AS nota_list
    FROM omset o
    LEFT JOIN sku_nota sn ON sn.id_transaksi = o.id_transaksi
    GROUP BY o.id_pelanggan, o.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'jenis', 'pending',
    'rute', v_rute,
    'tanggal', v_tgl,
    'id_setoran_buku', v_id,
    'total', coalesce(v_total, 0),
    'toko', coalesce(v_toko, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_setoran_pending_foto_rinci(text, text, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_pending_foto_rinci(text, text, bigint)
  TO authenticated, postgres, service_role;
