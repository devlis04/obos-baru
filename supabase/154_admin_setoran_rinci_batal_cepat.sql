-- Dialog Batal timeout: rinci join v_transaksi_item 3x untuk SEMUA nota terkirim.
-- Batal hanya nota yang ada sisa/batal. Item view sekali (MATERIALIZED).
-- Jalankan SETELAH 081. Boleh diulang.
CREATE OR REPLACE FUNCTION public.admin_setoran_rinci(
  p_jenis text,
  p_rute text DEFAULT NULL,
  p_id_setoran_buku bigint DEFAULT NULL
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
  v_tutup boolean;
BEGIN
  PERFORM set_config('statement_timeout', '60s', true);
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

  SELECT x.id, x.tanggal, x.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

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
        t.id_setoran_buku,
        t.waktu_actual,
        rp.rute_pengirim
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      WHERE t.waktu_packed IS NOT NULL
        AND (v_rute IS NULL OR rp.rute_pengirim = v_rute)
        AND public.admin_transaksi_ikut_buku(
          v_id, v_tgl, v_tutup, t.id_setoran_buku, t.status, t.waktu_actual
        )
        AND (
          v_jenis = 'kiriman'
          OR (
            v_jenis = 'batal'
            AND t.status IN ('batal', 'terkirim')
            AND NOT public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, t.id_setoran_buku, t.pending, t.waktu_actual
            )
            AND (
              t.status = 'batal'
              OR EXISTS (
                SELECT 1
                FROM public.transaksi_items x
                WHERE x.id_transaksi = t.id_transaksi
                  AND coalesce(x.qty_packed, 0) > coalesce(x.qty_actual, 0)
              )
            )
          )
          OR (
            v_jenis = 'pending'
            AND public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, t.id_setoran_buku, t.pending, t.waktu_actual
            )
          )
          OR (
            v_jenis = 'actual'
            AND t.status = 'terkirim'
            AND NOT public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, t.id_setoran_buku, t.pending, t.waktu_actual
            )
          )
        )
    ),
    item AS MATERIALIZED (
      SELECT i.*
      FROM public.v_transaksi_item i
      WHERE i.id_transaksi IN (SELECT n.id_transaksi FROM nota n)
    ),
    omset AS (
      SELECT
        n.id_transaksi,
        n.id_pelanggan,
        n.nama_pelanggan,
        n.status,
        n.pending,
        n.id_setoran_buku,
        n.waktu_actual,
        n.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed,
        coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS jual_actual
      FROM nota n
      JOIN item i ON i.id_transaksi = n.id_transaksi
      GROUP BY
        n.id_transaksi, n.id_pelanggan, n.nama_pelanggan,
        n.status, n.pending, n.id_setoran_buku, n.waktu_actual, n.rute_pengirim
    ),
    sku AS (
      SELECT
        n.id_pelanggan,
        n.rute_pengirim,
        i.id_barang,
        max(i.nama_barang) AS nama_barang,
        sum(
          CASE
            WHEN v_jenis = 'batal' AND n.status = 'terkirim'
              THEN greatest(coalesce(i.qty_packed, 0) - coalesce(i.qty_actual, 0), 0)
            WHEN v_jenis = 'batal' THEN coalesce(i.qty_packed, 0)
            ELSE coalesce(i.qty_packed, 0)
          END
        )::integer AS qty,
        sum(
          CASE
            WHEN v_jenis = 'batal'
              THEN public.admin_omset_batal(
                n.status, i.subtotal_jual_packed, i.subtotal_jual_actual
              )
            ELSE coalesce(i.subtotal_jual_packed, 0)
          END
        )::bigint AS nilai
      FROM nota n
      JOIN item i ON i.id_transaksi = n.id_transaksi
      WHERE coalesce(i.qty_packed, 0) > 0
        AND (
          v_jenis <> 'batal'
          OR n.status = 'batal'
          OR (
            n.status = 'terkirim'
            AND coalesce(i.qty_packed, 0) > coalesce(i.qty_actual, 0)
          )
        )
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
            'qty', sum(
              CASE
                WHEN v_jenis = 'batal' AND o.status = 'terkirim'
                  THEN greatest(coalesce(i.qty_packed, 0) - coalesce(i.qty_actual, 0), 0)
                ELSE coalesce(i.qty_packed, 0)
              END
            )::integer,
            'nilai', sum(
              CASE
                WHEN v_jenis = 'batal'
                  THEN public.admin_omset_batal(
                    o.status, i.subtotal_jual_packed, i.subtotal_jual_actual
                  )
                ELSE coalesce(i.subtotal_jual_packed, 0)
              END
            )::bigint,
            'qty_packed', sum(coalesce(i.qty_packed, 0))::integer,
            'packed', sum(coalesce(i.subtotal_jual_packed, 0))::bigint,
            'qty_batal', sum(
              public.admin_omset_batal(
                o.status, i.qty_packed, i.qty_actual
              )
            )::integer,
            'batal', sum(
              public.admin_omset_batal(
                o.status, i.subtotal_jual_packed, i.subtotal_jual_actual
              )
            )::bigint,
            'qty_actual', sum(coalesce(i.qty_actual, 0))::integer,
            'actual', sum(coalesce(i.subtotal_jual_actual, 0))::bigint
          ) AS sku
        FROM nota n
        JOIN omset o ON o.id_transaksi = n.id_transaksi
        JOIN item i ON i.id_transaksi = n.id_transaksi
        WHERE coalesce(i.qty_packed, 0) > 0
          AND (
            v_jenis <> 'batal'
            OR o.status = 'batal'
            OR (
              o.status = 'terkirim'
              AND coalesce(i.qty_packed, 0) > coalesce(i.qty_actual, 0)
            )
          )
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
        count(DISTINCT o.id_transaksi) FILTER (
          WHERE v_jenis <> 'batal' OR public.admin_omset_batal(
            o.status, o.jual_packed, o.jual_actual
          ) > 0
        )::integer AS n_nota,
        coalesce(sum(o.jual_packed), 0)::bigint AS jual_packed,
        coalesce(sum(
          CASE
            WHEN public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, o.id_setoran_buku, o.pending, o.waktu_actual
            ) THEN 0
            ELSE public.admin_omset_batal(o.status, o.jual_packed, o.jual_actual)
          END
        ), 0)::bigint AS jual_batal,
        coalesce(sum(
          CASE
            WHEN public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, o.id_setoran_buku, o.pending, o.waktu_actual
            ) THEN o.jual_packed
            ELSE 0
          END
        ), 0)::bigint AS jual_pending,
        coalesce(max(r.nilai), 0)::bigint AS jual_retur,
        coalesce(sum(
          CASE
            WHEN public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, o.id_setoran_buku, o.pending, o.waktu_actual
            ) THEN 0
            ELSE o.jual_actual
          END
        ), 0)::bigint AS jual_actual,
        CASE
          WHEN bool_or(o.status = 'dikirim') THEN 'dikirim'
          WHEN bool_or(
            public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, o.id_setoran_buku, o.pending, o.waktu_actual
            )
          ) THEN 'pending'
          WHEN bool_or(o.status = 'batal') THEN 'batal'
          WHEN bool_or(o.status = 'terkirim') THEN 'terkirim'
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
                WHEN public.admin_setoran_pending_halaman(
                  v_id, v_tgl, v_tutup, o2.id_setoran_buku, o2.pending, o2.waktu_actual
                ) THEN 0
                ELSE public.admin_omset_batal(
                  o2.status, o2.jual_packed, o2.jual_actual
                )
              END,
              'pending', CASE
                WHEN public.admin_setoran_pending_halaman(
                  v_id, v_tgl, v_tutup, o2.id_setoran_buku, o2.pending, o2.waktu_actual
                ) THEN o2.jual_packed
                ELSE 0
              END,
              'actual', CASE
                WHEN public.admin_setoran_pending_halaman(
                  v_id, v_tgl, v_tutup, o2.id_setoran_buku, o2.pending, o2.waktu_actual
                ) THEN 0
                ELSE o2.jual_actual
              END,
              'retur', 0,
              'status', CASE
                WHEN public.admin_setoran_pending_halaman(
                  v_id, v_tgl, v_tutup, o2.id_setoran_buku, o2.pending, o2.waktu_actual
                ) THEN 'pending'
                ELSE o2.status
              END,
              'sku', coalesce(sn.sku, '[]'::jsonb)
            )
            ORDER BY o2.id_transaksi
          ) FILTER (
            WHERE v_jenis <> 'batal'
              OR public.admin_omset_batal(
                o2.status, o2.jual_packed, o2.jual_actual
              ) > 0
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
    FROM toko t
    WHERE v_jenis <> 'batal' OR t.jual_batal > 0;
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
REVOKE ALL ON FUNCTION public.admin_setoran_rinci(text, text, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_rinci(text, text, bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
