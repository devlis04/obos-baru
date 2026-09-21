-- Rinci toko + SKU dari kartu setoran admin.
-- Jalankan SETELAH 048. Boleh diulang.
-- p_jenis: kiriman | batal | pending | actual | retur
-- p_rute: rute_pengirim, atau kosong / Jumlah = semua rute.

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

  IF v_jenis = 'retur' THEN
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
            'nilai', b.nilai
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
            'sku', t.sku
          )
          ORDER BY t.nama, t.id_pelanggan
        ),
        '[]'::jsonb
      ),
      coalesce(sum(t.nilai), 0)::bigint
    INTO v_toko, v_total
    FROM toko t;
  ELSE
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
          (v_jenis = 'kiriman')
          OR (v_jenis = 'batal' AND t.status = 'batal')
          OR (v_jenis = 'pending' AND t.pending)
          OR (v_jenis = 'actual' AND t.status <> 'batal')
        )
    ),
    baris AS (
      SELECT
        n.id_pelanggan,
        n.nama_pelanggan AS nama,
        n.rute_pengirim,
        i.id_barang,
        i.nama_barang,
        CASE
          WHEN v_jenis = 'actual' THEN coalesce(i.qty_actual, 0)
          ELSE coalesce(i.qty_packed, 0)
        END::integer AS qty,
        CASE
          WHEN v_jenis = 'actual' THEN coalesce(i.subtotal_jual_actual, 0)
          ELSE coalesce(i.subtotal_jual_packed, 0)
        END::bigint AS nilai
      FROM nota n
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
    ),
    sku AS (
      SELECT
        b.id_pelanggan,
        max(b.nama) AS nama,
        b.rute_pengirim,
        b.id_barang,
        max(b.nama_barang) AS nama_barang,
        sum(b.qty)::integer AS qty,
        sum(b.nilai)::bigint AS nilai
      FROM baris b
      WHERE b.qty > 0
      GROUP BY b.id_pelanggan, b.rute_pengirim, b.id_barang
    ),
    toko AS (
      SELECT
        s.id_pelanggan,
        max(s.nama) AS nama,
        s.rute_pengirim,
        coalesce(sum(s.nilai), 0)::bigint AS nilai,
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
    )
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id_pelanggan', t.id_pelanggan,
            'nama', t.nama,
            'rute_pengirim', t.rute_pengirim,
            'nilai', t.nilai,
            'sku', t.sku
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
