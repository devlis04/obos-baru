-- Pending cap buku lama (mis. 21/09) tampil di kiriman buku terbuka (22/09).
-- Halaman buku packing tetap pending (termasuk setelah actual di hari lain).
-- Cap id_setoran_buku tidak dipindah. Packing gudang tidak diubah.
-- Jalankan SETELAH 080. Boleh diulang. Jangan jalankan 076/077 setelah ini.

CREATE OR REPLACE FUNCTION public.admin_transaksi_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_id_buku IS NOT NULL
    AND (
      p_id_setoran_buku = p_id_buku
      OR (
        p_id_setoran_buku IS NULL
        AND NOT coalesce(p_tutup, false)
        AND (
          p_status = 'dikirim'
          OR (
            p_status IN ('terkirim', 'batal')
            AND p_waktu_actual IS NOT NULL
            AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
          )
        )
      )
      OR (
        NOT coalesce(p_tutup, false)
        AND p_id_setoran_buku IS NOT NULL
        AND p_id_setoran_buku <> p_id_buku
        AND p_status = 'dikirim'
        AND p_waktu_actual IS NULL
      )
      OR (
        NOT coalesce(p_tutup, false)
        AND p_id_setoran_buku IS NOT NULL
        AND p_id_setoran_buku <> p_id_buku
        AND p_status IN ('terkirim', 'batal')
        AND p_waktu_actual IS NOT NULL
        AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.pengirim_nota_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_order timestamptz,
  p_waktu_actual timestamptz,
  p_tanggal_lihat date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (
      p_id_buku IS NOT NULL
      AND p_id_setoran_buku = p_id_buku
    )
    OR (
      p_tgl IS NOT NULL
      AND p_waktu_order IS NOT NULL
      AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      AND p_id_setoran_buku IS NULL
      AND p_status = 'dikirim'
      AND (p_id_buku IS NULL OR coalesce(p_hidup, false))
    )
    OR (
      p_id_buku IS NULL
      AND p_id_setoran_buku IS NULL
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    )
    OR (
      coalesce(p_hidup, false)
      AND p_id_buku IS NOT NULL
      AND p_id_setoran_buku IS NOT NULL
      AND p_id_setoran_buku <> p_id_buku
      AND p_status = 'dikirim'
      AND p_waktu_actual IS NULL
    )
    OR (
      coalesce(p_hidup, false)
      AND p_id_buku IS NOT NULL
      AND p_id_setoran_buku IS NOT NULL
      AND p_id_setoran_buku <> p_id_buku
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_setoran_pending_halaman(
  p_lihat bigint,
  p_tgl date,
  p_tutup boolean,
  p_cap bigint,
  p_pending boolean,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(p_pending, false);
$$;

CREATE OR REPLACE FUNCTION public.admin_omset_batal(
  p_status text,
  p_packed numeric,
  p_actual numeric
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_status = 'batal' THEN round(coalesce(p_packed, 0))::bigint
    WHEN p_status = 'terkirim' THEN
      greatest(round(coalesce(p_packed, 0) - coalesce(p_actual, 0)), 0)::bigint
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.admin_setoran_kartu_hidup(p_id bigint)
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
  v_tutup boolean;
  v_baris jsonb;
BEGIN
  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'dari_snapshot', false,
      'rute', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(q.baris ORDER BY q.rute_pengirim), '[]'::jsonb)
  INTO v_baris
  FROM (
    SELECT
      p.rute_pengirim,
      jsonb_build_object(
        'rute_pengirim', p.rute_pengirim,
        'kiriman', coalesce(o.kiriman, 0),
        'batal', coalesce(o.batal, 0),
        'pending', coalesce(o.pending, 0),
        'actual', coalesce(o.actual, 0),
        'wajib_kunci', coalesce(o.wajib_kunci, 0),
        'transfer', coalesce(s.jumlah_transfer, 0),
        'tunai', coalesce(s.jumlah_tunai, 0),
        'bop', coalesce(s.jumlah_bop, 0),
        'kasbon', coalesce(s.kasbon_supir, 0) + coalesce(s.kasbon_kenek, 0),
        'kasbon_supir', coalesce(s.kasbon_supir, 0),
        'kasbon_kenek', coalesce(s.kasbon_kenek, 0),
        'nama_supir', coalesce(nm.nama_supir, ''),
        'nama_kenek', coalesce(nm.nama_kenek, ''),
        'retur', coalesce(r.nilai, 0),
        'sudah_setor', s.id IS NOT NULL
      ) AS baris
    FROM (
      SELECT DISTINCT rute_pengirim
      FROM public.rute_peta
    ) p
    LEFT JOIN (
      SELECT
        rp.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS kiriman,
        coalesce(sum(
          CASE
            WHEN public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, t.id_setoran_buku, t.pending, t.waktu_actual
            ) THEN 0
            ELSE public.admin_omset_batal(
              t.status, i.subtotal_jual_packed, i.subtotal_jual_actual
            )
          END
        ), 0)::bigint AS batal,
        coalesce(sum(
          CASE
            WHEN public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, t.id_setoran_buku, t.pending, t.waktu_actual
            ) THEN i.subtotal_jual_packed
            ELSE 0
          END
        ), 0)::bigint AS pending,
        coalesce(sum(
          CASE
            WHEN t.status = 'batal' THEN 0
            WHEN public.admin_setoran_pending_halaman(
              v_id, v_tgl, v_tutup, t.id_setoran_buku, t.pending, t.waktu_actual
            ) THEN 0
            ELSE i.subtotal_jual_actual
          END
        ), 0)::bigint AS actual,
        count(DISTINCT t.id_transaksi) FILTER (
          WHERE t.status = 'dikirim' AND NOT t.pending
        )::integer AS wajib_kunci
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
      WHERE t.waktu_packed IS NOT NULL
        AND public.admin_transaksi_ikut_buku(
          v_id, v_tgl, v_tutup, t.id_setoran_buku, t.status, t.waktu_actual
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN public.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        public.pengirim_grup_rute(u.rute) AS rute_pengirim,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'D' THEN u.nama END) AS nama_supir,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'H' THEN u.nama END) AS nama_kenek
      FROM public.users u
      WHERE u.peran = 'pengirim'
      GROUP BY public.pengirim_grup_rute(u.rute)
    ) nm ON nm.rute_pengirim = p.rute_pengirim
    LEFT JOIN (
      SELECT
        i.rute_pengirim,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM public.retur_toko i
      WHERE i.id_setoran_buku = v_id
      GROUP BY i.rute_pengirim
    ) r ON r.rute_pengirim = p.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', coalesce(v_tutup, false),
    'dari_snapshot', false,
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_setoran_rinci(text, text);
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
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
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
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
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
        JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
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

REVOKE ALL ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_pending_halaman(bigint, date, boolean, bigint, boolean, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_pending_halaman(bigint, date, boolean, bigint, boolean, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_omset_batal(text, numeric, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_omset_batal(text, numeric, numeric)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_kartu_hidup(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu_hidup(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_rinci(text, text, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_rinci(text, text, bigint)
  TO authenticated, postgres, service_role;

CREATE OR REPLACE FUNCTION public.pengirim_boleh_kerja_nota(
  p_cap bigint,
  p_terbuka bigint,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    p_terbuka IS NOT NULL
    AND (
      p_cap IS NULL
      OR p_cap = p_terbuka
      OR (
        p_cap < p_terbuka
        AND (
          (p_status = 'dikirim' AND p_waktu_actual IS NULL)
          OR (
            p_status IN ('terkirim', 'batal')
            AND p_waktu_actual IS NOT NULL
            AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date
              = (timezone('Asia/Jakarta', clock_timestamp()))::date
          )
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.pengirim_pending_nota(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_sales text[];
  v_status text;
  v_pending boolean;
  v_actual timestamptz;
  v_buku bigint;
  v_buku_nota bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa diubah.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.pending, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_pending, v_actual, v_buku_nota
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF NOT public.pengirim_boleh_kerja_nota(v_buku_nota, v_buku, v_status, v_actual) THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF v_status <> 'dikirim' OR v_actual IS NOT NULL THEN
    RAISE EXCEPTION 'Hanya nota sedang dikirim yang bisa di-pending.';
  END IF;
  IF v_pending THEN
    RAISE EXCEPTION 'Nota sudah pending.';
  END IF;

  UPDATE public.transaksi
  SET pending = true
  WHERE id_transaksi = v_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_batal_nota(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_sales text[];
  v_status text;
  v_actual timestamptz;
  v_sku text;
  v_qty integer;
  v_buku bigint;
  v_buku_nota bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa diubah.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_actual, v_buku_nota
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF NOT public.pengirim_boleh_kerja_nota(v_buku_nota, v_buku, v_status, v_actual) THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF v_status = 'batal' THEN
    RAISE EXCEPTION 'Nota sudah batal.';
  END IF;
  IF v_status <> 'dikirim' OR v_actual IS NOT NULL THEN
    RAISE EXCEPTION 'Hanya nota sedang dikirim atau pending yang bisa dibatalkan.';
  END IF;

  FOR v_sku, v_qty IN
    SELECT i.id_barang, COALESCE(i.qty_packed, 0)
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
      AND COALESCE(i.qty_packed, 0) > 0
    FOR UPDATE
  LOOP
    PERFORM public.stok_kembali_packing(v_sku, v_qty);
  END LOOP;

  UPDATE public.transaksi_items
  SET qty_actual = 0
  WHERE id_transaksi = v_id;

  UPDATE public.transaksi
  SET
    status = 'batal',
    pending = false,
    waktu_actual = clock_timestamp()
  WHERE id_transaksi = v_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_buka_kunci_nota(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_sales text[];
  v_status text;
  v_packed timestamptz;
  v_buku_nota bigint;
  v_buku bigint;
  v_actual timestamptz;
  rec record;
  v_sisa numeric;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa diubah.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  v_sales := public.pengirim_rute_sales();

  PERFORM pg_advisory_xact_lock(88221019);

  SELECT t.status, t.waktu_packed, t.id_setoran_buku, t.waktu_actual
  INTO v_status, v_packed, v_buku_nota, v_actual
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF v_packed IS NULL THEN
    RAISE EXCEPTION 'Nota belum dikirim gudang.';
  END IF;
  IF v_status = 'dikirim' THEN
    RETURN true;
  END IF;
  IF v_status NOT IN ('terkirim', 'batal') THEN
    RAISE EXCEPTION 'Nota ini tidak bisa dibuka lagi.';
  END IF;
  IF NOT public.pengirim_boleh_kerja_nota(v_buku_nota, v_buku, v_status, v_actual) THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
      AND COALESCE(i.qty_packed, 0) > 0
  ) THEN
    RAISE EXCEPTION 'Nota batal gudang tidak bisa dibuka lagi.';
  END IF;

  FOR rec IN
    SELECT
      i.id_barang,
      COALESCE(i.qty_packed, 0) AS qty_packed,
      COALESCE(i.qty_actual, 0) AS qty_actual
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
    FOR UPDATE
  LOOP
    v_sisa := GREATEST(rec.qty_packed - rec.qty_actual, 0);
    IF v_sisa > 0 THEN
      PERFORM public.stok_catat_batal(rec.id_barang, -v_sisa);
    END IF;
  END LOOP;

  UPDATE public.transaksi_items
  SET qty_actual = NULL
  WHERE id_transaksi = v_id;

  UPDATE public.transaksi
  SET
    status = 'dikirim',
    pending = false,
    waktu_actual = NULL
  WHERE id_transaksi = v_id;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_kunci_nota(
  p_id_transaksi text,
  p_baris jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_status text;
  v_sales text[];
  v_item jsonb;
  v_sku text;
  v_qty integer;
  v_ada_isi boolean;
  rec record;
  v_buku bigint;
  v_buku_nota bigint;
  v_actual timestamptz;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa dikunci.';
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  v_sales := public.pengirim_rute_sales();
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar tebus wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  DROP TABLE IF EXISTS pengirim_qty_baru;

  SELECT t.status, t.id_setoran_buku, t.waktu_actual
  INTO v_status, v_buku_nota, v_actual
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
  END IF;
  IF NOT public.pengirim_boleh_kerja_nota(v_buku_nota, v_buku, v_status, v_actual) THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF v_status IN ('terkirim', 'batal') THEN
    PERFORM public.pengirim_buka_kunci_nota(v_id);
    v_status := 'dikirim';
  END IF;
  IF v_status IS DISTINCT FROM 'dikirim' THEN
    RAISE EXCEPTION 'Nota sudah terkunci atau belum dikirim.';
  END IF;

  CREATE TEMP TABLE pengirim_qty_baru (
    id_barang text PRIMARY KEY,
    qty integer NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_sku := btrim(COALESCE(v_item ->> 'id_barang', ''));
    IF v_sku = '' THEN
      CONTINUE;
    END IF;
    v_qty := COALESCE((v_item ->> 'qty_actual')::integer, 0);
    IF v_qty < 0 THEN
      RAISE EXCEPTION 'Qty tebus tidak boleh negatif (SKU %).', v_sku;
    END IF;
    INSERT INTO pengirim_qty_baru (id_barang, qty)
    VALUES (v_sku, v_qty)
    ON CONFLICT (id_barang) DO UPDATE SET qty = EXCLUDED.qty;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pengirim_qty_baru n
    LEFT JOIN public.transaksi_items i
      ON i.id_transaksi = v_id
     AND i.id_barang = n.id_barang
    WHERE i.id_barang IS NULL
  ) THEN
    RAISE EXCEPTION 'Ada SKU yang tidak ada di nota.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
      AND n.id_barang IS NULL
      AND COALESCE(i.qty_packed, 0) > 0
  ) THEN
    RAISE EXCEPTION 'Semua SKU packed harus diisi qty tebus.';
  END IF;

  FOR rec IN
    SELECT
      i.id_barang,
      COALESCE(n.qty, 0) AS qty,
      COALESCE(i.qty_packed, 0) AS qty_packed
    FROM public.transaksi_items i
    LEFT JOIN pengirim_qty_baru n ON n.id_barang = i.id_barang
    WHERE i.id_transaksi = v_id
  LOOP
    IF rec.qty > rec.qty_packed THEN
      RAISE EXCEPTION 'Qty tebus melebihi packed (SKU %).', rec.id_barang;
    END IF;

    UPDATE public.transaksi_items
    SET qty_actual = rec.qty
    WHERE id_transaksi = v_id
      AND id_barang = rec.id_barang;

    IF rec.qty_packed - rec.qty > 0 THEN
      PERFORM public.stok_kembali_packing(
        rec.id_barang,
        rec.qty_packed - rec.qty
      );
    END IF;
  END LOOP;

  UPDATE public.transaksi_items
  SET qty_actual = 0
  WHERE id_transaksi = v_id
    AND qty_actual IS NULL;

  SELECT EXISTS (
    SELECT 1
    FROM public.transaksi_items i
    WHERE i.id_transaksi = v_id
      AND COALESCE(i.qty_actual, 0) > 0
  ) INTO v_ada_isi;

  UPDATE public.transaksi
  SET
    pending = false,
    waktu_actual = clock_timestamp(),
    status = CASE WHEN v_ada_isi THEN 'terkirim' ELSE 'batal' END
  WHERE id_transaksi = v_id
    AND status = 'dikirim';
END;
$$;

REVOKE ALL ON FUNCTION public.pengirim_boleh_kerja_nota(bigint, bigint, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_boleh_kerja_nota(bigint, bigint, text, timestamptz)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
