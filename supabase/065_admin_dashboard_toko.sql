-- Dialog toko dashboard: per sales, satu hari Jakarta (jadwal visit + kunjungan + nota).
-- Jalankan SETELAH 061. SQL Editor → Run. Boleh di-Run ulang.

DROP FUNCTION IF EXISTS public.admin_dashboard_toko(date, text);

CREATE FUNCTION public.admin_dashboard_toko(p_hari date, p_rute text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hari date;
  v_rute text;
  v_nama_hari text;
  v_toko jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_hari := COALESCE(p_hari, (timezone('Asia/Jakarta', now()))::date);
  v_rute := nullif(btrim(coalesce(p_rute, '')), '');
  IF v_rute IS NULL THEN
    RAISE EXCEPTION 'Rute sales wajib.';
  END IF;

  v_nama_hari := CASE EXTRACT(ISODOW FROM v_hari)::integer
    WHEN 1 THEN 'Senin'
    WHEN 2 THEN 'Selasa'
    WHEN 3 THEN 'Rabu'
    WHEN 4 THEN 'Kamis'
    WHEN 5 THEN 'Jumat'
    WHEN 6 THEN 'Sabtu'
    ELSE 'Minggu'
  END;

  WITH kunci AS (
    SELECT btrim(p.id_pelanggan) AS id_pelanggan
    FROM public.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(p.id_pelanggan) <> ''
      AND p.id_pelanggan NOT LIKE 'TMP%'
      AND btrim(COALESCE(p.visit, '')) = v_nama_hari
    UNION
    SELECT btrim(k.id_pelanggan)
    FROM public.kunjungan_sales k
    WHERE btrim(k.rute) = v_rute
      AND k.tanggal = v_hari
      AND btrim(COALESCE(k.id_pelanggan, '')) <> ''
    UNION
    SELECT btrim(t.id_pelanggan)
    FROM public.transaksi t
    WHERE btrim(t.rute) = v_rute
      AND btrim(COALESCE(t.id_pelanggan, '')) <> ''
      AND (timezone('Asia/Jakarta', t.waktu_order))::date = v_hari
  ),
  nota AS (
    SELECT
      t.id_transaksi,
      btrim(t.id_pelanggan) AS id_pelanggan,
      t.nama_pelanggan,
      t.status,
      t.pending
    FROM public.transaksi t
    WHERE btrim(t.rute) = v_rute
      AND btrim(COALESCE(t.id_pelanggan, '')) <> ''
      AND (timezone('Asia/Jakarta', t.waktu_order))::date = v_hari
  ),
  omset AS (
    SELECT
      n.id_transaksi,
      n.id_pelanggan,
      n.nama_pelanggan,
      n.status,
      n.pending,
      coalesce(sum(i.subtotal_jual_order), 0)::bigint AS jual_order,
      coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS jual_actual,
      coalesce(sum(i.subtotal_beli_order), 0)::bigint AS beli_order,
      coalesce(sum(i.subtotal_beli_packed), 0)::bigint AS beli_packed,
      coalesce(sum(i.subtotal_beli_actual), 0)::bigint AS beli_actual
    FROM nota n
    JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    GROUP BY
      n.id_transaksi, n.id_pelanggan, n.nama_pelanggan, n.status, n.pending
  ),
  sku_nota AS (
    SELECT
      x.id_transaksi,
      jsonb_agg(x.sku ORDER BY x.sku->>'id_barang') AS sku
    FROM (
      SELECT
        n.id_transaksi,
        jsonb_build_object(
          'id_barang', i.id_barang,
          'nama', max(i.nama_barang),
          'qty', sum(coalesce(i.qty_order, 0))::integer,
          'nilai', sum(coalesce(i.subtotal_jual_order, 0))::bigint,
          'qty_order', sum(coalesce(i.qty_order, 0))::integer,
          'order', sum(coalesce(i.subtotal_jual_order, 0))::bigint,
          'modal_order', sum(coalesce(i.subtotal_beli_order, 0))::bigint,
          'qty_packed', sum(coalesce(i.qty_packed, 0))::integer,
          'packed', sum(coalesce(i.subtotal_jual_packed, 0))::bigint,
          'modal_packed', sum(coalesce(i.subtotal_beli_packed, 0))::bigint,
          'qty_batal', sum(
            CASE
              WHEN o.status = 'batal' THEN coalesce(i.qty_packed, i.qty_order, 0)
              WHEN o.status = 'terkirim'
                THEN greatest(
                  coalesce(i.qty_packed, 0) - coalesce(i.qty_actual, 0),
                  0
                )
              ELSE 0
            END
          )::integer,
          'batal', sum(
            CASE
              WHEN o.status = 'batal' THEN coalesce(i.subtotal_jual_packed, i.subtotal_jual_order, 0)
              WHEN o.status = 'terkirim'
                THEN greatest(
                  coalesce(i.subtotal_jual_packed, 0)
                    - coalesce(i.subtotal_jual_actual, 0),
                  0
                )
              ELSE 0
            END
          )::bigint,
          'qty_actual', sum(coalesce(i.qty_actual, 0))::integer,
          'actual', sum(coalesce(i.subtotal_jual_actual, 0))::bigint,
          'modal_actual', sum(coalesce(i.subtotal_beli_actual, 0))::bigint
        ) AS sku
      FROM nota n
      JOIN omset o ON o.id_transaksi = n.id_transaksi
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
      GROUP BY n.id_transaksi, i.id_barang
    ) x
    GROUP BY x.id_transaksi
  ),
  sku_toko AS (
    SELECT
      x.id_pelanggan,
      jsonb_agg(
        jsonb_build_object(
          'id_barang', x.id_barang,
          'nama', x.nama_barang,
          'qty', x.qty,
          'nilai', x.nilai
        )
        ORDER BY x.id_barang
      ) AS sku
    FROM (
      SELECT
        n.id_pelanggan,
        i.id_barang,
        max(i.nama_barang) AS nama_barang,
        sum(coalesce(i.qty_order, 0))::integer AS qty,
        sum(coalesce(i.subtotal_jual_order, 0))::bigint AS nilai
      FROM nota n
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
      GROUP BY n.id_pelanggan, i.id_barang
    ) x
    GROUP BY x.id_pelanggan
  ),
  nota_toko AS (
    SELECT
      o.id_pelanggan,
      jsonb_agg(
        jsonb_build_object(
          'id', o.id_transaksi,
          'rute', v_rute,
          'order', o.jual_order,
          'packed', o.jual_packed,
          'batal', CASE
            WHEN o.status = 'batal' THEN o.jual_packed
            WHEN o.status = 'terkirim'
              THEN greatest(o.jual_packed - o.jual_actual, 0)
            ELSE 0
          END,
          'pending', CASE WHEN o.pending THEN o.jual_packed ELSE 0 END,
          'actual', o.jual_actual,
          'retur', 0,
          'modal_order', o.beli_order,
          'modal_packed', o.beli_packed,
          'modal_pending', CASE WHEN o.pending THEN o.beli_packed ELSE 0 END,
          'modal_actual', o.beli_actual,
          'status', CASE WHEN o.pending THEN 'pending' ELSE o.status END,
          'sku', coalesce(sn.sku, '[]'::jsonb)
        )
        ORDER BY o.id_transaksi
      ) AS nota_list
    FROM omset o
    LEFT JOIN sku_nota sn ON sn.id_transaksi = o.id_transaksi
    GROUP BY o.id_pelanggan
  ),
  visit AS (
    SELECT DISTINCT ON (btrim(k.id_pelanggan))
      btrim(k.id_pelanggan) AS id_pelanggan,
      k.waktu_masuk,
      k.waktu_keluar
    FROM public.kunjungan_sales k
    WHERE btrim(k.rute) = v_rute
      AND k.tanggal = v_hari
    ORDER BY btrim(k.id_pelanggan), k.waktu_masuk NULLS LAST
  ),
  jadwal AS (
    SELECT btrim(p.id_pelanggan) AS id_pelanggan
    FROM public.pelanggan p
    WHERE btrim(p.rute) = v_rute
      AND COALESCE(p.aktif, true)
      AND btrim(COALESCE(p.visit, '')) = v_nama_hari
      AND p.id_pelanggan NOT LIKE 'TMP%'
  ),
  baris AS (
    SELECT
      k.id_pelanggan,
      coalesce(
        nullif(btrim(p.nama_pelanggan), ''),
        nullif(max(o.nama_pelanggan), ''),
        k.id_pelanggan
      ) AS nama,
      coalesce(sum(o.jual_order), 0)::bigint AS jual_order,
      count(DISTINCT o.id_transaksi)::integer AS n_nota,
      coalesce(sum(o.jual_packed), 0)::bigint AS jual_packed,
      coalesce(sum(
        CASE
          WHEN o.status = 'batal' THEN o.jual_packed
          WHEN o.status = 'terkirim'
            THEN greatest(o.jual_packed - o.jual_actual, 0)
          ELSE 0
        END
      ), 0)::bigint AS jual_batal,
      coalesce(sum(
        CASE WHEN o.pending THEN o.jual_packed ELSE 0 END
      ), 0)::bigint AS jual_pending,
      coalesce(sum(o.jual_actual), 0)::bigint AS jual_actual,
      coalesce(sum(o.beli_order), 0)::bigint AS beli_order,
      coalesce(sum(o.beli_packed), 0)::bigint AS beli_packed,
      coalesce(sum(
        CASE WHEN o.pending THEN o.beli_packed ELSE 0 END
      ), 0)::bigint AS beli_pending,
      coalesce(sum(o.beli_actual), 0)::bigint AS beli_actual,
      CASE
        WHEN bool_or(o.status = 'diproses') THEN 'diproses'
        WHEN bool_or(o.status = 'dikirim' AND NOT o.pending) THEN 'dikirim'
        WHEN bool_or(o.pending) THEN 'pending'
        WHEN bool_or(o.status = 'terkirim') THEN 'terkirim'
        WHEN bool_or(o.status = 'batal') THEN 'batal'
        ELSE '—'
      END AS status,
      v.waktu_masuk,
      v.waktu_keluar,
      (j.id_pelanggan IS NOT NULL) AS jadwal,
      coalesce(st.sku, '[]'::jsonb) AS sku,
      coalesce(nb.nota_list, '[]'::jsonb) AS nota_list
    FROM kunci k
    LEFT JOIN public.pelanggan p ON p.id_pelanggan = k.id_pelanggan
    LEFT JOIN omset o ON o.id_pelanggan = k.id_pelanggan
    LEFT JOIN visit v ON v.id_pelanggan = k.id_pelanggan
    LEFT JOIN jadwal j ON j.id_pelanggan = k.id_pelanggan
    LEFT JOIN sku_toko st ON st.id_pelanggan = k.id_pelanggan
    LEFT JOIN nota_toko nb ON nb.id_pelanggan = k.id_pelanggan
    GROUP BY
      k.id_pelanggan,
      p.nama_pelanggan,
      v.waktu_masuk,
      v.waktu_keluar,
      j.id_pelanggan,
      st.sku,
      nb.nota_list
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_pelanggan', b.id_pelanggan,
        'nama', b.nama,
        'rute_pengirim', v_rute,
        'nilai', b.jual_order,
        'nota', b.n_nota,
        'order', b.jual_order,
        'packed', b.jual_packed,
        'batal', b.jual_batal,
        'pending', b.jual_pending,
        'actual', b.jual_actual,
        'modal_order', b.beli_order,
        'modal_packed', b.beli_packed,
        'modal_pending', b.beli_pending,
        'modal_actual', b.beli_actual,
        'retur', 0,
        'status', b.status,
        'visit_masuk', b.waktu_masuk,
        'visit_keluar', b.waktu_keluar,
        'jadwal', b.jadwal,
        'sku', b.sku,
        'nota_list', b.nota_list
      )
      ORDER BY b.nama, b.id_pelanggan
    ),
    '[]'::jsonb
  )
  INTO v_toko
  FROM baris b;

  RETURN jsonb_build_object(
    'hari', v_hari,
    'rute', v_rute,
    'toko', coalesce(v_toko, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_toko(date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_dashboard_toko(date, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_toko(date, text)
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_dashboard_toko(date, text) IS
  'Daftar toko satu sales satu hari dashboard (jadwal, visit, nota).';

NOTIFY pgrst, 'reload schema';
