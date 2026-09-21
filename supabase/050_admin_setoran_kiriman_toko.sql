-- Dialog kiriman admin: omset per toko (nota, order, packed, batal, retur, actual, status).
-- Jalankan SETELAH 049. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_setoran_rinci(
  p_jenis text,
  p_rute text DEFAULT NULL
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
  v_jenis text;
  v_rute text;
  v_toko jsonb;
  v_total bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_jenis := lower(btrim(coalesce(p_jenis, '')));
  IF v_jenis NOT IN ('kiriman', 'batal', 'pending', 'actual', 'retur') THEN
    RAISE EXCEPTION 'Jenis rincian tidak dikenal.';
  END IF;

  v_rute := nullif(btrim(coalesce(p_rute, '')), '');
  IF v_rute IS NOT NULL AND lower(v_rute) IN ('jumlah', 'semua') THEN
    v_rute := NULL;
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    SELECT b.id, b.tanggal
    INTO v_id, v_tgl
    FROM public.setoran_buku b
    ORDER BY b.id DESC
    LIMIT 1;
  ELSE
    SELECT b.tanggal INTO v_tgl
    FROM public.setoran_buku b
    WHERE b.id = v_id;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'jenis', v_jenis,
      'rute', v_rute,
      'tanggal', NULL,
      'total', 0,
      'toko', '[]'::jsonb
    );
  END IF;

  IF v_jenis IN ('kiriman', 'batal', 'pending', 'actual') THEN
    WITH nota AS (
      SELECT
        t.id_transaksi,
        t.id_pelanggan,
        t.nama_pelanggan,
        t.status,
        t.pending,
        rp.rute_pengirim
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      WHERE t.waktu_packed IS NOT NULL
        AND (v_rute IS NULL OR rp.rute_pengirim = v_rute)
        AND (
          t.id_setoran_buku = v_id
          OR (
            t.id_setoran_buku IS NULL
            AND (
              t.status = 'dikirim'
              OR (
                t.status IN ('terkirim', 'batal')
                AND t.waktu_actual IS NOT NULL
                AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_tgl
              )
            )
          )
        )
        AND (
          v_jenis = 'kiriman'
          OR (v_jenis = 'batal' AND t.status = 'batal')
          OR (v_jenis = 'pending' AND t.pending)
          OR (v_jenis = 'actual' AND t.status = 'terkirim')
        )
    ),
    omset AS (
      SELECT
        n.id_transaksi,
        n.id_pelanggan,
        n.nama_pelanggan,
        n.status,
        n.pending,
        n.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed,
        coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS jual_actual
      FROM nota n
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
      GROUP BY
        n.id_transaksi, n.id_pelanggan, n.nama_pelanggan,
        n.status, n.pending, n.rute_pengirim
    ),
    sku AS (
      SELECT
        n.id_pelanggan,
        n.rute_pengirim,
        i.id_barang,
        max(i.nama_barang) AS nama_barang,
        sum(coalesce(i.qty_packed, 0))::integer AS qty,
        sum(coalesce(i.subtotal_jual_packed, 0))::bigint AS nilai
      FROM nota n
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
      WHERE coalesce(i.qty_packed, 0) > 0
      GROUP BY n.id_pelanggan, n.rute_pengirim, i.id_barang
    ),
    sku_toko AS (
      SELECT
        s.id_pelanggan,
        s.rute_pengirim,
        jsonb_agg(
          jsonb_build_object(
            'id_barang', s.id_barang,
            'nama', s.nama_barang,
            'qty', s.qty,
            'nilai', s.nilai
          )
          ORDER BY s.id_barang
        ) AS sku
      FROM sku s
      GROUP BY s.id_pelanggan, s.rute_pengirim
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
            'qty', sum(coalesce(i.qty_packed, 0))::integer,
            'nilai', sum(coalesce(i.subtotal_jual_packed, 0))::bigint,
            'qty_packed', sum(coalesce(i.qty_packed, 0))::integer,
            'packed', sum(coalesce(i.subtotal_jual_packed, 0))::bigint,
            'qty_batal', sum(
              CASE
                WHEN o.status = 'batal' THEN coalesce(i.qty_packed, 0)
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
                WHEN o.status = 'batal' THEN coalesce(i.subtotal_jual_packed, 0)
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
            'actual', sum(coalesce(i.subtotal_jual_actual, 0))::bigint
          ) AS sku
        FROM nota n
        JOIN omset o ON o.id_transaksi = n.id_transaksi
        JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
        WHERE coalesce(i.qty_packed, 0) > 0
        GROUP BY n.id_transaksi, i.id_barang
      ) x
      GROUP BY x.id_transaksi
    ),
    retur AS (
      SELECT
        i.id_pelanggan,
        i.rute_pengirim,
        max(coalesce(nullif(btrim(p.nama_pelanggan), ''), i.id_pelanggan)) AS nama,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM public.retur_toko i
      LEFT JOIN public.pelanggan p ON p.id_pelanggan = i.id_pelanggan
      WHERE i.id_setoran_buku = v_id
        AND (v_rute IS NULL OR i.rute_pengirim = v_rute)
        AND i.qty > 0
      GROUP BY i.id_pelanggan, i.rute_pengirim
    ),
    kunci AS (
      SELECT id_pelanggan, rute_pengirim FROM omset
      UNION
      SELECT id_pelanggan, rute_pengirim FROM retur
      WHERE v_jenis = 'kiriman'
    ),
    toko AS (
      SELECT
        k.id_pelanggan,
        coalesce(
          nullif(max(o.nama_pelanggan), ''),
          nullif(max(r.nama), ''),
          k.id_pelanggan
        ) AS nama,
        k.rute_pengirim,
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
        coalesce(max(r.nilai), 0)::bigint AS jual_retur,
        coalesce(sum(o.jual_actual), 0)::bigint AS jual_actual,
        CASE
          WHEN bool_or(o.status = 'dikirim') THEN 'dikirim'
          WHEN bool_or(o.pending) THEN 'pending'
          WHEN bool_or(o.status = 'terkirim') THEN 'terkirim'
          WHEN bool_or(o.status = 'batal') THEN 'batal'
          ELSE '-'
        END AS status,
        coalesce(s.sku, '[]'::jsonb) AS sku,
        coalesce(nb.nota_list, '[]'::jsonb) AS nota_list
      FROM kunci k
      LEFT JOIN omset o
        ON o.id_pelanggan = k.id_pelanggan
       AND o.rute_pengirim = k.rute_pengirim
      LEFT JOIN retur r
        ON r.id_pelanggan = k.id_pelanggan
       AND r.rute_pengirim = k.rute_pengirim
      LEFT JOIN sku_toko s
        ON s.id_pelanggan = k.id_pelanggan
       AND s.rute_pengirim = k.rute_pengirim
      LEFT JOIN (
        SELECT
          o2.id_pelanggan,
          o2.rute_pengirim,
          jsonb_agg(
            jsonb_build_object(
              'id', o2.id_transaksi,
              'rute', o2.rute_pengirim,
              'packed', o2.jual_packed,
              'batal', CASE
                WHEN o2.status = 'batal' THEN o2.jual_packed
                WHEN o2.status = 'terkirim'
                  THEN greatest(o2.jual_packed - o2.jual_actual, 0)
                ELSE 0
              END,
              'pending', CASE WHEN o2.pending THEN o2.jual_packed ELSE 0 END,
              'actual', o2.jual_actual,
              'retur', 0,
              'status', CASE
                WHEN o2.pending THEN 'pending'
                ELSE o2.status
              END,
              'sku', coalesce(sn.sku, '[]'::jsonb)
            )
            ORDER BY o2.id_transaksi
          ) AS nota_list
        FROM omset o2
        LEFT JOIN sku_nota sn ON sn.id_transaksi = o2.id_transaksi
        GROUP BY o2.id_pelanggan, o2.rute_pengirim
      ) nb
        ON nb.id_pelanggan = k.id_pelanggan
       AND nb.rute_pengirim = k.rute_pengirim
      GROUP BY k.id_pelanggan, k.rute_pengirim, s.sku, nb.nota_list
    )
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id_pelanggan', t.id_pelanggan,
            'nama', t.nama,
            'rute_pengirim', t.rute_pengirim,
            'nilai', CASE v_jenis
              WHEN 'batal' THEN t.jual_batal
              WHEN 'pending' THEN t.jual_pending
              WHEN 'actual' THEN t.jual_actual
              ELSE t.jual_packed
            END,
            'nota', t.n_nota,
            'packed', t.jual_packed,
            'batal', t.jual_batal,
            'pending', t.jual_pending,
            'actual', t.jual_actual,
            'retur', t.jual_retur,
            'status', t.status,
            'sku', t.sku,
            'nota_list', t.nota_list
          )
          ORDER BY t.nama, t.id_pelanggan
        ),
        '[]'::jsonb
      ),
      CASE v_jenis
        WHEN 'batal' THEN coalesce(sum(t.jual_batal), 0)::bigint
        WHEN 'pending' THEN coalesce(sum(t.jual_pending), 0)::bigint
        WHEN 'actual' THEN coalesce(sum(t.jual_actual), 0)::bigint
        ELSE coalesce(sum(t.jual_packed), 0)::bigint
      END
    INTO v_toko, v_total
    FROM toko t;
  ELSIF v_jenis = 'retur' THEN
    WITH baris AS (
      SELECT
        i.id_pelanggan,
        coalesce(nullif(btrim(p.nama_pelanggan), ''), i.id_pelanggan) AS nama,
        i.rute_pengirim,
        i.kode_barang AS id_barang,
        coalesce(nullif(btrim(i.nama_barang), ''), i.kode_barang) AS nama_barang,
        i.qty::integer AS qty,
        (i.qty * i.harga_jual)::bigint AS nilai
      FROM public.retur_toko i
      LEFT JOIN public.pelanggan p ON p.id_pelanggan = i.id_pelanggan
      WHERE i.id_setoran_buku = v_id
        AND (v_rute IS NULL OR i.rute_pengirim = v_rute)
        AND i.qty > 0
    ),
    toko AS (
      SELECT
        b.id_pelanggan,
        max(b.nama) AS nama,
        b.rute_pengirim,
        coalesce(sum(b.nilai), 0)::bigint AS nilai,
        jsonb_agg(
          jsonb_build_object(
            'id_barang', b.id_barang,
            'nama', b.nama_barang,
            'qty', b.qty,
            'nilai', b.nilai,
            'qty_packed', 0,
            'packed', 0,
            'qty_batal', 0,
            'batal', 0,
            'qty_actual', 0,
            'actual', 0,
            'qty_retur', b.qty,
            'retur', b.nilai
          )
          ORDER BY b.id_barang
        ) AS sku
      FROM baris b
      GROUP BY b.id_pelanggan, b.rute_pengirim
    )
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id_pelanggan', t.id_pelanggan,
            'nama', t.nama,
            'rute_pengirim', t.rute_pengirim,
            'nilai', t.nilai,
            'nota', 1,
            'packed', 0,
            'batal', 0,
            'pending', 0,
            'actual', 0,
            'retur', t.nilai,
            'status', 'retur',
            'sku', t.sku,
            'nota_list', jsonb_build_array(
              jsonb_build_object(
                'id', 'Retur',
                'rute', t.rute_pengirim,
                'packed', 0,
                'batal', 0,
                'pending', 0,
                'actual', 0,
                'retur', t.nilai,
                'status', 'retur',
                'sku', t.sku
              )
            )
          )
          ORDER BY t.nama, t.id_pelanggan
        ),
        '[]'::jsonb
      ),
      coalesce(sum(t.nilai), 0)::bigint
    INTO v_toko, v_total
    FROM toko t;
  END IF;

  RETURN jsonb_build_object(
    'jenis', v_jenis,
    'rute', v_rute,
    'tanggal', v_tgl,
    'total', coalesce(v_total, 0),
    'toko', coalesce(v_toko, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_setoran_rinci(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_rinci(text, text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
