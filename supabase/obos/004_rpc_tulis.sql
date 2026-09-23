-- RPC tulis: buka/tutup buku, pack, pending, setor.
-- Jalankan SETELAH 003. Uji SQL Editor (postgres). Tidak cek sesi HP.
-- public/app tidak diubah. Boleh diulang.

CREATE OR REPLACE FUNCTION obos.tanggal_order_buku(p_id_buku bigint DEFAULT NULL)
RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_today date;
  v_tgl date;
  v_buku date;
BEGIN
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  IF p_id_buku IS NOT NULL THEN
    SELECT MIN(obos.hari_jakarta(t.waktu_order))
    INTO v_tgl
    FROM obos.transaksi t
    WHERE t.id_setoran_buku = p_id_buku
      AND t.waktu_order IS NOT NULL
      AND NOT obos.pending_di_foto(p_id_buku, t.id_transaksi);
    IF v_tgl IS NOT NULL THEN
      RETURN v_tgl;
    END IF;
    SELECT b.tanggal INTO v_buku
    FROM obos.setoran_buku b
    WHERE b.id = p_id_buku;
    IF v_buku IS NOT NULL THEN
      RETURN v_buku;
    END IF;
  END IF;
  SELECT MIN(obos.hari_jakarta(t.waktu_order))
  INTO v_tgl
  FROM obos.transaksi t
  WHERE t.id_setoran_buku IS NULL
    AND t.waktu_order IS NOT NULL
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL);
  RETURN COALESCE(v_tgl, v_today);
END;
$$;

CREATE OR REPLACE FUNCTION obos.foto_catat(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
BEGIN
  IF p_id IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO obos.setoran_buku_pending_foto (id_setoran_buku, id_transaksi)
  SELECT p_id, t.id_transaksi
  FROM obos.transaksi t
  WHERE t.id_setoran_buku = p_id
    AND t.status = 'dikirim'
    AND COALESCE(t.pending, false)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION obos.foto_pindah(p_baru bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
BEGIN
  IF p_baru IS NULL THEN
    RETURN;
  END IF;
  UPDATE obos.transaksi t
  SET
    id_setoran_buku = p_baru,
    pending = false
  FROM obos.setoran_buku_pending_foto f
  JOIN obos.setoran_buku b ON b.id = f.id_setoran_buku
  WHERE b.ditutup
    AND f.id_transaksi = t.id_transaksi
    AND t.status = 'dikirim'
    AND COALESCE(t.pending, false)
    AND t.id_setoran_buku IS DISTINCT FROM p_baru;
END;
$$;

CREATE OR REPLACE FUNCTION obos.buka_buku()
RETURNS bigint
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_lama date;
  v_today date;
BEGIN
  PERFORM pg_advisory_xact_lock(88221940);
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_id := obos.buku_terbuka();
  IF v_id IS NOT NULL THEN
    v_tgl := obos.tanggal_order_buku(v_id);
    SELECT b.tanggal INTO v_lama FROM obos.setoran_buku b WHERE b.id = v_id;
    IF EXISTS (SELECT 1 FROM obos.setoran_buku x WHERE x.ditutup) THEN
      v_tgl := GREATEST(COALESCE(v_tgl, v_today), v_today);
    END IF;
    IF v_tgl IS NOT NULL AND v_lama IS DISTINCT FROM v_tgl THEN
      UPDATE obos.setoran_buku SET tanggal = v_tgl WHERE id = v_id;
      UPDATE obos.stok_opname SET tanggal = v_tgl WHERE id_setoran_buku = v_id;
    END IF;
    PERFORM obos.foto_pindah(v_id);
    RETURN v_id;
  END IF;

  v_tgl := obos.tanggal_order_buku(NULL);
  INSERT INTO obos.setoran_buku (tanggal, ditutup)
  VALUES (v_tgl, false)
  RETURNING id INTO v_id;

  INSERT INTO obos.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
  )
  SELECT
    v_id, v_tgl, b.id_barang, b.nama_barang,
    GREATEST(COALESCE(b.stok, 0), 0), 0
  FROM obos.barang b
  WHERE btrim(b.id_barang) <> ''
    AND COALESCE(b.aktif, true);

  PERFORM obos.foto_pindah(v_id);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION obos.tutup_buku()
RETURNS bigint
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_sku text;
  v_n integer;
  v_fisik integer;
BEGIN
  PERFORM pg_advisory_xact_lock(88221940);
  v_id := obos.buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM obos.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);
  IF v_n > 0 THEN
    RAISE EXCEPTION
      'Masih ada % nota dikirim. Pengirim selesaikan dulu, lalu tutup buku.',
      v_n;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM obos.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'pengirim')
    AND a.id_setoran_buku = v_id;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada absensi yang belum pulang. Scan pulang dulu, lalu tutup buku.';
  END IF;

  SELECT count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer
  INTO v_fisik
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id;
  IF COALESCE(v_fisik, 0) <= 0 THEN
    RAISE EXCEPTION 'Opname fisik belum diisi. Gudang isi fisik dulu, lalu tutup buku.';
  END IF;

  SELECT so.id_barang INTO v_sku
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) < 0
    AND so.putusan IS DISTINCT FROM 'kasbon'
    AND so.putusan IS DISTINCT FROM 'beban'
  ORDER BY lower(so.nama_barang)
  LIMIT 1;
  IF v_sku IS NOT NULL THEN
    RAISE EXCEPTION
      'Masih ada selisih kurang belum diputuskan (SKU %). Kasbon atau potong margin dulu.',
      v_sku;
  END IF;

  UPDATE obos.stok_opname so
  SET
    putusan = 'margin_plus',
    nilai_putusan = round(so.selisih * GREATEST(COALESCE(b.harga_beli, 0), 0))::integer,
    harga_beli_putusan = GREATEST(COALESCE(b.harga_beli, 0), 0)::integer,
    qty_selisih_putusan = so.selisih,
    kasbon_email = NULL,
    kasbon_nama = NULL,
    waktu_putusan = clock_timestamp()
  FROM obos.barang b
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) > 0;

  UPDATE obos.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  PERFORM obos.foto_catat(v_id);

  UPDATE obos.setoran_buku
  SET ditutup = true, waktu_tutup = clock_timestamp()
  WHERE id = v_id AND NOT ditutup;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION obos.tolak_pack_sisa_foto()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = obos
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM obos.setoran_buku_pending_foto f
    JOIN obos.setoran_buku b ON b.id = f.id_setoran_buku
    WHERE f.id_transaksi = NEW.id_transaksi
      AND b.ditutup
  ) THEN
    RAISE EXCEPTION 'Sisa kiriman buku kemarin tidak di-packing ulang.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trx_item_tolak_pack_sisa_foto ON obos.transaksi_items;
CREATE TRIGGER trx_item_tolak_pack_sisa_foto
  BEFORE INSERT OR UPDATE OF qty_packed ON obos.transaksi_items
  FOR EACH ROW
  EXECUTE PROCEDURE obos.tolak_pack_sisa_foto();

CREATE OR REPLACE FUNCTION obos.pack_nota(p_id_transaksi text, p_baris jsonb)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_status text;
  v_actual timestamptz;
  v_cap bigint;
  v_tutup boolean;
  v_buku bigint;
  v_tgl date;
  v_item jsonb;
  v_sku text;
  v_qty integer;
  v_sisa numeric;
  v_maks numeric;
  v_lama integer;
  v_delta integer;
  v_jual integer;
  v_beli integer;
  v_nama text;
  v_grup text;
  v_min1 integer; v_jual1 integer;
  v_min2 integer; v_jual2 integer;
  v_min3 integer; v_jual3 integer;
  v_min4 integer; v_jual4 integer;
  v_min5 integer; v_jual5 integer;
  v_ada boolean;
  v_ada_isi boolean;
BEGIN
  IF btrim(COALESCE(p_id_transaksi, '')) = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar packing wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);

  SELECT t.status, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_actual, v_cap
  FROM obos.transaksi t
  WHERE t.id_transaksi = p_id_transaksi
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada.';
  END IF;
  IF v_status = 'batal' THEN
    RAISE EXCEPTION 'Nota batal tidak bisa di packing.';
  END IF;
  IF v_actual IS NOT NULL OR v_status = 'terkirim' THEN
    RAISE EXCEPTION 'Nota sudah terkunci. Packing tidak bisa diubah.';
  END IF;

  IF v_cap IS NOT NULL THEN
    SELECT b.ditutup, b.tanggal INTO v_tutup, v_tgl
    FROM obos.setoran_buku b
    WHERE b.id = v_cap;
    IF COALESCE(v_tutup, true) THEN
      RAISE EXCEPTION 'Nota sudah di buku tertutup. Packing tidak bisa diubah.';
    END IF;
    v_buku := v_cap;
  ELSE
    v_buku := obos.buka_buku();
    SELECT b.tanggal INTO v_tgl FROM obos.setoran_buku b WHERE b.id = v_buku;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_sku := btrim(COALESCE(v_item ->> 'id_barang', ''));
    IF v_sku = '' THEN
      CONTINUE;
    END IF;
    v_qty := COALESCE((v_item ->> 'qty_packed')::integer, 0);
    IF v_qty < 0 THEN
      RAISE EXCEPTION 'Qty packing tidak boleh negatif (SKU %).', v_sku;
    END IF;

    SELECT
      b.id_barang, b.nama_barang, COALESCE(b.harga_jual, 0),
      GREATEST(COALESCE(b.harga_beli, 0), 0), b.id_grup,
      b.min_strat_1, b.jual_strat_1, b.min_strat_2, b.jual_strat_2,
      b.min_strat_3, b.jual_strat_3, b.min_strat_4, b.jual_strat_4,
      b.min_strat_5, b.jual_strat_5
    INTO
      v_sku, v_nama, v_jual, v_beli, v_grup,
      v_min1, v_jual1, v_min2, v_jual2,
      v_min3, v_jual3, v_min4, v_jual4,
      v_min5, v_jual5
    FROM obos.barang b
    WHERE lower(b.id_barang) = lower(v_sku)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SKU % tidak ada di barang.', v_sku;
    END IF;

    SELECT true, i.qty_packed INTO v_ada, v_lama
    FROM obos.transaksi_items i
    WHERE i.id_transaksi = p_id_transaksi AND i.id_barang = v_sku
    FOR UPDATE;
    IF NOT FOUND THEN
      v_ada := false;
      v_lama := 0;
      IF v_qty <= 0 THEN
        CONTINUE;
      END IF;
    END IF;

    INSERT INTO obos.stok_opname (
      id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
    )
    SELECT v_buku, v_tgl, v_sku, v_nama, GREATEST(COALESCE(b.stok, 0), 0), 0
    FROM obos.barang b
    WHERE b.id_barang = v_sku
      AND NOT EXISTS (
        SELECT 1 FROM obos.stok_opname so
        WHERE so.id_setoran_buku = v_buku AND so.id_barang = v_sku
      );

    SELECT so.stok_hitung INTO v_sisa
    FROM obos.stok_opname so
    WHERE so.id_setoran_buku = v_buku AND so.id_barang = v_sku
    FOR UPDATE;
    v_sisa := COALESCE(v_sisa, 0);
    v_maks := v_sisa + COALESCE(v_lama, 0);
    IF v_maks < COALESCE(v_lama, 0) THEN
      v_maks := COALESCE(v_lama, 0);
    END IF;
    IF v_qty > v_maks THEN
      RAISE EXCEPTION 'Sisa stok tidak cukup (SKU %).', v_sku;
    END IF;

    IF NOT v_ada THEN
      INSERT INTO obos.transaksi_items (
        id_transaksi, id_barang, id_grup, nama_barang, harga_beli, harga_jual,
        qty_order, qty_packed,
        min_strat_1, jual_strat_1, min_strat_2, jual_strat_2,
        min_strat_3, jual_strat_3, min_strat_4, jual_strat_4,
        min_strat_5, jual_strat_5
      ) VALUES (
        p_id_transaksi, v_sku, v_grup, v_nama, v_beli, v_jual, 0, v_qty,
        COALESCE(v_min1, 0), COALESCE(v_jual1, 0),
        COALESCE(v_min2, 0), COALESCE(v_jual2, 0),
        COALESCE(v_min3, 0), COALESCE(v_jual3, 0),
        COALESCE(v_min4, 0), COALESCE(v_jual4, 0),
        COALESCE(v_min5, 0), COALESCE(v_jual5, 0)
      );
    END IF;

    v_delta := v_qty - COALESCE(v_lama, 0);
    IF v_delta <> 0 THEN
      UPDATE obos.stok_opname
      SET
        qty_packed = qty_packed + v_delta,
        stok_fisik = CASE
          WHEN stok_fisik IS NULL THEN NULL
          ELSE GREATEST(0, stok_fisik - v_delta)
        END
      WHERE id_setoran_buku = v_buku AND id_barang = v_sku;
    END IF;

    IF v_ada THEN
      UPDATE obos.transaksi_items
      SET qty_packed = v_qty
      WHERE id_transaksi = p_id_transaksi AND id_barang = v_sku;
    END IF;
  END LOOP;

  UPDATE obos.transaksi_items i
  SET qty_packed = 0
  WHERE i.id_transaksi = p_id_transaksi
    AND i.qty_packed IS NULL;

  SELECT EXISTS (
    SELECT 1 FROM obos.transaksi_items i
    WHERE i.id_transaksi = p_id_transaksi AND COALESCE(i.qty_packed, 0) > 0
  ) INTO v_ada_isi;

  IF v_ada_isi THEN
    UPDATE obos.transaksi
    SET
      waktu_packed = COALESCE(waktu_packed, clock_timestamp()),
      status = CASE WHEN status = 'diproses' THEN 'dikirim' ELSE status END,
      id_setoran_buku = COALESCE(id_setoran_buku, v_buku)
    WHERE id_transaksi = p_id_transaksi;
  ELSE
    UPDATE obos.transaksi
    SET
      status = 'batal',
      pending = false,
      waktu_packed = COALESCE(waktu_packed, clock_timestamp()),
      id_setoran_buku = COALESCE(id_setoran_buku, v_buku)
    WHERE id_transaksi = p_id_transaksi;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION obos.pending_nota(p_id_transaksi text)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id text;
  v_status text;
  v_pending boolean;
  v_actual timestamptz;
  v_buku bigint;
  v_buku_nota bigint;
BEGIN
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Nota tidak bisa diubah.';
  END IF;
  v_id := btrim(COALESCE(p_id_transaksi, ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'id_transaksi wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);

  SELECT t.status, t.pending, t.waktu_actual, t.id_setoran_buku
  INTO v_status, v_pending, v_actual, v_buku_nota
  FROM obos.transaksi t
  WHERE t.id_transaksi = v_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada.';
  END IF;
  IF v_buku_nota IS DISTINCT FROM v_buku THEN
    RAISE EXCEPTION 'Nota bukan dari buku yang sedang terbuka.';
  END IF;
  IF v_status <> 'dikirim' OR v_actual IS NOT NULL THEN
    RAISE EXCEPTION 'Hanya nota sedang dikirim yang bisa di-pending.';
  END IF;
  IF v_pending THEN
    RAISE EXCEPTION 'Nota sudah pending.';
  END IF;

  UPDATE obos.transaksi SET pending = true WHERE id_transaksi = v_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION obos.setoran_simpan(
  p_rute_pengirim text,
  p_jumlah_transfer integer,
  p_jumlah_tunai integer,
  p_jumlah_bop integer,
  p_kasbon_supir integer DEFAULT 0,
  p_kasbon_kenek integer DEFAULT 0,
  p_dicatat_oleh text DEFAULT '',
  p_dicatat_rute text DEFAULT ''
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_buku bigint;
  v_tr integer;
  v_tu integer;
  v_bop integer;
  v_ks integer;
  v_kk integer;
  v_belum integer;
BEGIN
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Setoran tidak bisa diubah.';
  END IF;
  v_rute := obos.grup_rute(p_rute_pengirim);
  IF v_rute IS NULL OR v_rute = '' THEN
    RAISE EXCEPTION 'Rute pengirim tidak ada.';
  END IF;

  SELECT count(*)::integer INTO v_belum
  FROM obos.transaksi t
  JOIN obos.rute_peta rp ON rp.rute_sales = t.rute
  WHERE rp.rute_pengirim = v_rute
    AND t.waktu_packed IS NOT NULL
    AND t.status = 'dikirim'
    AND NOT t.pending
    AND COALESCE(t.id_setoran_buku, v_buku) = v_buku;
  IF COALESCE(v_belum, 0) > 0 THEN
    RAISE EXCEPTION
      'Kunci semua nota dulu sebelum setor. Masih ada % nota belum dikunci.',
      v_belum;
  END IF;

  v_tr := GREATEST(COALESCE(p_jumlah_transfer, 0), 0);
  v_tu := GREATEST(COALESCE(p_jumlah_tunai, 0), 0);
  v_bop := GREATEST(COALESCE(p_jumlah_bop, 0), 0);
  v_ks := GREATEST(COALESCE(p_kasbon_supir, 0), 0);
  v_kk := GREATEST(COALESCE(p_kasbon_kenek, 0), 0);
  IF v_bop > 170000 THEN
    RAISE EXCEPTION 'BOP maksimal Rp 170.000.';
  END IF;

  INSERT INTO obos.setoran_pengirim (
    rute_pengirim, id_setoran_buku,
    jumlah_transfer, jumlah_tunai, jumlah_bop,
    kasbon_supir, kasbon_kenek, waktu_setor, dicatat_oleh, dicatat_rute
  )
  VALUES (
    v_rute, v_buku, v_tr, v_tu, v_bop, v_ks, v_kk,
    clock_timestamp(),
    coalesce(nullif(btrim(p_dicatat_oleh), ''), ''),
    coalesce(nullif(btrim(p_dicatat_rute), ''), v_rute)
  )
  ON CONFLICT (rute_pengirim, id_setoran_buku) DO UPDATE SET
    jumlah_transfer = EXCLUDED.jumlah_transfer,
    jumlah_tunai = EXCLUDED.jumlah_tunai,
    jumlah_bop = EXCLUDED.jumlah_bop,
    kasbon_supir = EXCLUDED.kasbon_supir,
    kasbon_kenek = EXCLUDED.kasbon_kenek,
    waktu_setor = clock_timestamp(),
    dicatat_oleh = EXCLUDED.dicatat_oleh,
    dicatat_rute = EXCLUDED.dicatat_rute;

  RETURN true;
END;
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
        'tanggal_order_buku', 'foto_catat', 'foto_pindah',
        'buka_buku', 'tutup_buku', 'tolak_pack_sisa_foto',
        'pack_nota', 'pending_nota', 'setoran_simpan'
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
