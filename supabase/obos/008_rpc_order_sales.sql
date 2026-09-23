-- RPC order salesman: simpan / ubah / batal sebelum packing.
-- Jalankan SETELAH 007. Uji SQL Editor (postgres). Tidak cek sesi HP.
-- Harga jual strata per id_grup (grup kosong = SKU). public/app tidak diubah.

CREATE OR REPLACE FUNCTION obos.isi_item_order(p_id text, p_items jsonb)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  n integer;
  v_hilang text;
BEGIN
  SELECT string_agg(DISTINCT p.id_barang, ', ')
  INTO v_hilang
  FROM (
    SELECT btrim(e->>'id_barang') AS id_barang
    FROM jsonb_array_elements(p_items) AS e
    WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
      AND COALESCE((e->>'qty')::integer, 0) > 0
  ) p
  LEFT JOIN obos.barang b ON b.id_barang = p.id_barang
  WHERE b.id_barang IS NULL
     OR NOT COALESCE(b.aktif, true);
  IF v_hilang IS NOT NULL THEN
    RAISE EXCEPTION 'SKU tidak ada di katalog: %.', v_hilang;
  END IF;

  INSERT INTO obos.transaksi_items (
    id_transaksi,
    id_barang,
    id_grup,
    nama_barang,
    harga_beli,
    harga_jual,
    qty_order,
    min_strat_1,
    jual_strat_1,
    min_strat_2,
    jual_strat_2,
    min_strat_3,
    jual_strat_3,
    min_strat_4,
    jual_strat_4,
    min_strat_5,
    jual_strat_5
  )
  WITH pesan AS (
    SELECT
      btrim(e->>'id_barang') AS id_barang,
      SUM((e->>'qty')::integer) AS qty
    FROM jsonb_array_elements(p_items) AS e
    WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
      AND COALESCE((e->>'qty')::integer, 0) > 0
    GROUP BY 1
  )
  SELECT
    p_id,
    p.id_barang,
    NULLIF(btrim(COALESCE(b.id_grup, '')), ''),
    b.nama_barang,
    COALESCE(b.harga_beli, 0),
    COALESCE(b.harga_jual, 0),
    p.qty,
    COALESCE(b.min_strat_1, 0),
    COALESCE(b.jual_strat_1, 0),
    COALESCE(b.min_strat_2, 0),
    COALESCE(b.jual_strat_2, 0),
    COALESCE(b.min_strat_3, 0),
    COALESCE(b.jual_strat_3, 0),
    COALESCE(b.min_strat_4, 0),
    COALESCE(b.jual_strat_4, 0),
    COALESCE(b.min_strat_5, 0),
    COALESCE(b.jual_strat_5, 0)
  FROM pesan p
  JOIN obos.barang b ON b.id_barang = p.id_barang
    AND COALESCE(b.aktif, true);

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN COALESCE(n, 0);
END;
$$;

CREATE OR REPLACE FUNCTION obos.simpan_order(
  p_rute text,
  p_id_transaksi text,
  p_id_pelanggan text,
  p_nama_pelanggan text,
  p_items jsonb
)
RETURNS text
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_pelanggan text;
  v_nama text;
  v_jumlah integer;
BEGIN
  v_rute := btrim(COALESCE(p_rute, ''));
  IF v_rute = '' THEN
    RAISE EXCEPTION 'Rute salesman wajib.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM obos.rute_peta rp WHERE rp.rute_sales = v_rute) THEN
    RAISE EXCEPTION 'Rute % tidak ada di peta.', v_rute;
  END IF;

  v_id := btrim(COALESCE(p_id_transaksi, ''));
  v_pelanggan := btrim(COALESCE(p_id_pelanggan, ''));
  IF v_pelanggan = '' THEN
    RAISE EXCEPTION 'Toko wajib.';
  END IF;
  IF left(upper(v_pelanggan), 3) = 'TMP' THEN
    RAISE EXCEPTION 'Toko sementara tidak bisa disimpan.';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Daftar barang wajib.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM obos.pelanggan
    WHERE id_pelanggan = v_pelanggan
      AND rute = v_rute
      AND COALESCE(aktif, true)
  ) THEN
    RAISE EXCEPTION 'Toko tidak ada di rute %.', v_rute;
  END IF;

  SELECT COUNT(*) INTO v_jumlah
  FROM jsonb_array_elements(p_items) AS e
  WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
    AND COALESCE((e->>'qty')::integer, 0) > 0;
  IF COALESCE(v_jumlah, 0) <= 0 THEN
    RAISE EXCEPTION 'Item nota kosong.';
  END IF;

  IF v_id = '' THEN
    v_id := v_rute || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS');
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);
  PERFORM pg_advisory_xact_lock(hashtext(v_id));

  IF EXISTS (SELECT 1 FROM obos.transaksi WHERE id_transaksi = v_id) THEN
    RETURN v_id;
  END IF;

  SELECT COALESCE(NULLIF(btrim(p_nama_pelanggan), ''), p.nama_pelanggan)
  INTO v_nama
  FROM obos.pelanggan p
  WHERE p.id_pelanggan = v_pelanggan;

  INSERT INTO obos.transaksi (
    id_transaksi, id_pelanggan, nama_pelanggan, rute, status, waktu_order, pending
  ) VALUES (
    v_id,
    v_pelanggan,
    upper(btrim(COALESCE(v_nama, ''))),
    v_rute,
    'diproses',
    clock_timestamp(),
    false
  );

  v_jumlah := obos.isi_item_order(v_id, p_items);
  IF v_jumlah <= 0 THEN
    DELETE FROM obos.transaksi WHERE id_transaksi = v_id;
    RAISE EXCEPTION 'Item nota kosong.';
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION obos.ubah_order(p_id_transaksi text, p_items jsonb)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id text;
  v_status text;
  v_packed timestamptz;
  v_jumlah integer;
BEGIN
  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Daftar barang wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);

  SELECT t.status, t.waktu_packed
  INTO v_status, v_packed
  FROM obos.transaksi t
  WHERE t.id_transaksi = v_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada.';
  END IF;
  IF v_status IS DISTINCT FROM 'diproses' OR v_packed IS NOT NULL THEN
    RAISE EXCEPTION 'Nota sudah dipacking. Salesman tidak bisa mengubah.';
  END IF;

  SELECT COUNT(*) INTO v_jumlah
  FROM jsonb_array_elements(p_items) AS e
  WHERE btrim(COALESCE(e->>'id_barang', '')) <> ''
    AND COALESCE((e->>'qty')::integer, 0) > 0;
  IF COALESCE(v_jumlah, 0) <= 0 THEN
    RAISE EXCEPTION 'Item nota kosong.';
  END IF;

  DELETE FROM obos.transaksi_items WHERE id_transaksi = v_id;
  v_jumlah := obos.isi_item_order(v_id, p_items);
  IF v_jumlah <= 0 THEN
    RAISE EXCEPTION 'Item nota kosong.';
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION obos.batal_order(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id text;
BEGIN
  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);

  UPDATE obos.transaksi
  SET status = 'batal', pending = false
  WHERE id_transaksi = v_id
    AND status = 'diproses'
    AND waktu_packed IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak bisa dibatal. Hanya order belum packing.';
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION obos.order_lihat(p_id_transaksi text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id text;
  v_head jsonb;
  v_item jsonb;
BEGIN
  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'id_transaksi', t.id_transaksi,
    'id_pelanggan', t.id_pelanggan,
    'nama_pelanggan', t.nama_pelanggan,
    'rute', t.rute,
    'status', t.status,
    'pending', t.pending,
    'waktu_order', t.waktu_order,
    'waktu_packed', t.waktu_packed,
    'waktu_actual', t.waktu_actual,
    'id_setoran_buku', t.id_setoran_buku,
    'jual_order', o.jual_order,
    'jual_packed', o.jual_packed,
    'jual_actual', o.jual_actual
  )
  INTO v_head
  FROM obos.transaksi t
  JOIN obos.v_omset_nota o ON o.id_transaksi = t.id_transaksi
  WHERE t.id_transaksi = v_id;
  IF v_head IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_barang', i.id_barang,
        'id_grup', i.id_grup,
        'nama_barang', i.nama_barang,
        'qty_order', i.qty_order,
        'qty_packed', i.qty_packed,
        'qty_actual', i.qty_actual,
        'harga_beli', i.harga_beli,
        'harga_jual', i.harga_jual,
        'harga_jual_order', i.harga_jual_order,
        'harga_jual_packed', i.harga_jual_packed,
        'harga_jual_actual', i.harga_jual_actual,
        'subtotal_jual_order', i.subtotal_jual_order,
        'subtotal_jual_packed', i.subtotal_jual_packed,
        'subtotal_jual_actual', i.subtotal_jual_actual
      )
      ORDER BY lower(i.nama_barang), i.id_barang
    ),
    '[]'::jsonb
  )
  INTO v_item
  FROM obos.v_transaksi_item i
  WHERE i.id_transaksi = v_id;

  RETURN v_head || jsonb_build_object('items', coalesce(v_item, '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION obos.order_riwayat(
  p_rute text,
  p_id_pelanggan text DEFAULT NULL,
  p_batas integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_toko text;
  v_n integer;
  v_baris jsonb;
BEGIN
  v_rute := btrim(COALESCE(p_rute, ''));
  v_toko := nullif(btrim(COALESCE(p_id_pelanggan, '')), '');
  v_n := GREATEST(LEAST(COALESCE(p_batas, 50), 200), 1);
  IF v_rute = '' THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(
    jsonb_agg(q.obj ORDER BY q.waktu_order DESC),
    '[]'::jsonb
  )
  INTO v_baris
  FROM (
    SELECT
      t.waktu_order,
      jsonb_build_object(
        'id_transaksi', t.id_transaksi,
        'id_pelanggan', t.id_pelanggan,
        'nama_pelanggan', t.nama_pelanggan,
        'status', t.status,
        'pending', t.pending,
        'waktu_order', t.waktu_order,
        'waktu_packed', t.waktu_packed,
        'jual_order', o.jual_order,
        'jual_packed', o.jual_packed,
        'jual_actual', o.jual_actual
      ) AS obj
    FROM obos.transaksi t
    JOIN obos.v_omset_nota o ON o.id_transaksi = t.id_transaksi
    WHERE t.rute = v_rute
      AND (v_toko IS NULL OR t.id_pelanggan = v_toko)
    ORDER BY t.waktu_order DESC
    LIMIT v_n
  ) q;

  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION obos.pelanggan_rute(p_rute text)
RETURNS TABLE (
  id_pelanggan text,
  nama_pelanggan text,
  rute text,
  visit text,
  urutan integer,
  latitude double precision,
  longitude double precision
)
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT
    p.id_pelanggan,
    p.nama_pelanggan,
    p.rute,
    p.visit,
    p.urutan,
    p.latitude,
    p.longitude
  FROM obos.pelanggan p
  WHERE p.rute = btrim(COALESCE(p_rute, ''))
    AND COALESCE(p.aktif, true)
  ORDER BY p.urutan NULLS LAST, lower(p.nama_pelanggan);
$$;

DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'obos'
      AND p.proname IN (
        'isi_item_order', 'simpan_order', 'ubah_order', 'batal_order',
        'order_lihat', 'order_riwayat', 'pelanggan_rute'
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION obos.%I(%s) FROM PUBLIC, anon, authenticated',
      f.proname, f.args
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION obos.%I(%s) TO postgres, service_role',
      f.proname, f.args
    );
  END LOOP;
END;
$$;
