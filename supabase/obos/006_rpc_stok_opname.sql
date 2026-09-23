-- RPC stok: retur, barang masuk, opname, kasbon/beban.
-- Jalankan SETELAH 005. Uji SQL Editor (postgres). Tidak cek sesi HP.
-- public/app tidak diubah. Boleh diulang.

CREATE UNIQUE INDEX IF NOT EXISTS kasbon_buku_sku_uidx
  ON obos.kasbon (id_setoran_buku, id_barang);
CREATE UNIQUE INDEX IF NOT EXISTS barang_masuk_tgl_uidx
  ON obos.barang_masuk (tanggal, id_supplier, id_barang)
  WHERE id_setoran_buku IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ongkir_buku_uidx
  ON obos.ongkir (id_setoran_buku, id_supplier)
  WHERE id_setoran_buku IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ongkir_tgl_uidx
  ON obos.ongkir (tanggal, id_supplier)
  WHERE id_setoran_buku IS NULL;

CREATE OR REPLACE FUNCTION obos.stok_opname_bersih_putusan()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = obos
AS $$
BEGIN
  IF NEW.putusan IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.selisih IS DISTINCT FROM OLD.selisih
     OR NEW.stok_fisik IS DISTINCT FROM OLD.stok_fisik THEN
    DELETE FROM obos.kasbon k
    WHERE k.id_setoran_buku = NEW.id_setoran_buku
      AND k.id_barang = NEW.id_barang;
    NEW.putusan := NULL;
    NEW.nilai_putusan := NULL;
    NEW.harga_beli_putusan := NULL;
    NEW.qty_selisih_putusan := NULL;
    NEW.kasbon_email := NULL;
    NEW.kasbon_nama := NULL;
    NEW.waktu_putusan := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS stok_opname_bersih_putusan_trg ON obos.stok_opname;
CREATE TRIGGER stok_opname_bersih_putusan_trg
  BEFORE UPDATE OF stok_fisik, qty_packed, stok_awal, qty_masuk, qty_batal, qty_retur
  ON obos.stok_opname
  FOR EACH ROW
  EXECUTE PROCEDURE obos.stok_opname_bersih_putusan();

CREATE OR REPLACE FUNCTION obos.stok_catat_retur(p_id_barang text, p_qty numeric)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_nama text;
  v_qty numeric(14, 4);
  v_lama numeric(14, 4);
  v_baru numeric(14, 4);
BEGIN
  v_qty := round(COALESCE(p_qty, 0), 4);
  IF v_qty = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Retur tidak bisa diubah.';
  END IF;

  SELECT b.tanggal INTO v_tgl FROM obos.setoran_buku b WHERE b.id = v_buku;
  SELECT b.nama_barang INTO v_nama FROM obos.barang b WHERE b.id_barang = p_id_barang;
  IF v_nama IS NULL THEN
    v_nama := p_id_barang;
  END IF;

  INSERT INTO obos.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
  )
  SELECT v_buku, v_tgl, p_id_barang, v_nama, GREATEST(COALESCE(b.stok, 0), 0), 0
  FROM obos.barang b
  WHERE b.id_barang = p_id_barang
    AND NOT EXISTS (
      SELECT 1 FROM obos.stok_opname so
      WHERE so.id_setoran_buku = v_buku AND so.id_barang = p_id_barang
    );

  SELECT so.qty_retur INTO v_lama
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_buku AND so.id_barang = p_id_barang
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  v_baru := GREATEST(0, COALESCE(v_lama, 0) + v_qty);
  UPDATE obos.stok_opname
  SET
    qty_retur = v_baru,
    stok_fisik = CASE
      WHEN stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, stok_fisik + (v_baru - COALESCE(v_lama, 0)))
    END
  WHERE id_setoran_buku = v_buku AND id_barang = p_id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION obos.retur_toko_lihat(
  p_rute_pengirim text,
  p_id_pelanggan text
)
RETURNS TABLE (
  kode_barang text,
  nama_barang text,
  qty integer,
  harga_jual integer,
  nilai integer,
  dikunci boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_buku bigint;
  v_kunci boolean;
BEGIN
  v_rute := obos.grup_rute(p_rute_pengirim);
  v_id := nullif(btrim(COALESCE(p_id_pelanggan, '')), '');
  v_buku := obos.buku_terbuka();
  IF v_rute IS NULL OR v_id IS NULL OR v_buku IS NULL THEN
    RETURN;
  END IF;
  v_kunci := EXISTS (
    SELECT 1 FROM obos.setoran_pengirim s
    WHERE s.rute_pengirim = v_rute AND s.id_setoran_buku = v_buku
  );
  RETURN QUERY
  SELECT
    i.kode_barang,
    COALESCE(NULLIF(btrim(i.nama_barang), ''), i.kode_barang),
    i.qty,
    i.harga_jual,
    (i.qty * i.harga_jual)::integer,
    v_kunci
  FROM obos.retur_toko i
  WHERE i.id_setoran_buku = v_buku
    AND i.rute_pengirim = v_rute
    AND i.id_pelanggan = v_id
  ORDER BY 2;
END;
$$;

CREATE OR REPLACE FUNCTION obos.retur_rute_lihat(p_rute_pengirim text)
RETURNS TABLE (
  id_pelanggan text,
  nama_toko text,
  kode_barang text,
  nama_barang text,
  qty integer,
  nilai integer
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_buku bigint;
BEGIN
  v_rute := obos.grup_rute(p_rute_pengirim);
  v_buku := obos.buku_terbuka();
  IF v_rute IS NULL OR v_buku IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    i.id_pelanggan,
    COALESCE(NULLIF(btrim(p.nama_pelanggan), ''), i.id_pelanggan),
    i.kode_barang,
    COALESCE(NULLIF(btrim(i.nama_barang), ''), i.kode_barang),
    i.qty,
    (i.qty * i.harga_jual)::integer
  FROM obos.retur_toko i
  LEFT JOIN obos.pelanggan p ON p.id_pelanggan = i.id_pelanggan
  WHERE i.id_setoran_buku = v_buku
    AND i.rute_pengirim = v_rute
  ORDER BY 2, 4;
END;
$$;

CREATE OR REPLACE FUNCTION obos.retur_toko_simpan(
  p_rute_pengirim text,
  p_id_pelanggan text,
  p_baris jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_buku bigint;
  v_tgl date;
  r jsonb;
  v_kode text;
  v_nama text;
  v_qty integer;
  v_harga integer;
  rec record;
BEGIN
  v_rute := obos.grup_rute(p_rute_pengirim);
  v_id := nullif(btrim(COALESCE(p_id_pelanggan, '')), '');
  IF v_rute IS NULL OR v_rute = '' OR v_id IS NULL THEN
    RAISE EXCEPTION 'Rute pengirim atau toko kosong.';
  END IF;
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku setoran terbuka. Retur tidak dicatat ke tanggal berikutnya.';
  END IF;
  SELECT b.tanggal INTO v_tgl FROM obos.setoran_buku b WHERE b.id = v_buku;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar retur wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);
  DROP TABLE IF EXISTS obos_tmp_retur;

  IF EXISTS (
    SELECT 1 FROM obos.setoran_pengirim s
    WHERE s.rute_pengirim = v_rute AND s.id_setoran_buku = v_buku
  ) THEN
    RAISE EXCEPTION 'Setoran sudah dicatat. Retur tidak bisa diubah.';
  END IF;

  CREATE TEMP TABLE obos_tmp_retur (
    kode text PRIMARY KEY,
    nama text,
    qty integer,
    harga integer
  ) ON COMMIT DROP;

  FOR r IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_kode := nullif(btrim(COALESCE(r ->> 'kode_barang', r ->> 'id_barang', '')), '');
    v_nama := btrim(COALESCE(r ->> 'nama_barang', ''));
    BEGIN
      v_qty := GREATEST(COALESCE((r ->> 'qty')::integer, 0), 0);
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;
    BEGIN
      v_harga := GREATEST(COALESCE((r ->> 'harga_jual')::integer, 0), 0);
    EXCEPTION WHEN OTHERS THEN
      v_harga := 0;
    END;
    IF v_kode IS NULL OR v_qty <= 0 THEN
      CONTINUE;
    END IF;
    IF v_nama = '' OR v_harga <= 0 THEN
      SELECT
        CASE
          WHEN v_nama = '' THEN COALESCE(NULLIF(btrim(b.nama_barang), ''), v_kode)
          ELSE v_nama
        END,
        CASE WHEN v_harga <= 0 THEN COALESCE(b.harga_jual, 0) ELSE v_harga END
      INTO v_nama, v_harga
      FROM obos.barang b
      WHERE b.id_barang = v_kode;
      v_nama := COALESCE(v_nama, v_kode);
      v_harga := COALESCE(v_harga, 0);
    END IF;
    INSERT INTO obos_tmp_retur (kode, nama, qty, harga)
    VALUES (v_kode, v_nama, v_qty, v_harga)
    ON CONFLICT (kode) DO UPDATE SET
      qty = EXCLUDED.qty,
      nama = EXCLUDED.nama,
      harga = EXCLUDED.harga;
  END LOOP;

  FOR rec IN
    SELECT
      COALESCE(l.kode_barang, n.kode) AS kode,
      COALESCE(l.qty, 0) AS lama,
      COALESCE(n.qty, 0) AS baru
    FROM (
      SELECT kode_barang, qty
      FROM obos.retur_toko
      WHERE id_setoran_buku = v_buku
        AND rute_pengirim = v_rute
        AND id_pelanggan = v_id
    ) l
    FULL JOIN obos_tmp_retur n ON n.kode = l.kode_barang
  LOOP
    IF rec.baru <> rec.lama THEN
      PERFORM obos.stok_catat_retur(rec.kode, rec.baru - rec.lama);
    END IF;
  END LOOP;

  DELETE FROM obos.retur_toko
  WHERE id_setoran_buku = v_buku
    AND rute_pengirim = v_rute
    AND id_pelanggan = v_id;

  INSERT INTO obos.retur_toko (
    id_setoran_buku, tanggal, rute_pengirim, id_pelanggan,
    kode_barang, nama_barang, qty, harga_jual
  )
  SELECT v_buku, v_tgl, v_rute, v_id, kode, nama, qty, harga
  FROM obos_tmp_retur;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION obos.jual_dari_modal(p_beli integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path = obos
AS $$
DECLARE
  v integer;
BEGIN
  IF COALESCE(p_beli, 0) <= 0 THEN
    RETURN 0;
  END IF;
  v := (round(p_beli::numeric * 1.05 / 500) * 500)::integer;
  IF v <= p_beli THEN
    v := (p_beli / 500 + 1) * 500;
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_id_berikut()
RETURNS text
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id text;
  v_pre text;
  v_num text;
  v_next integer;
BEGIN
  PERFORM pg_advisory_xact_lock(88221941);
  SELECT b.id_barang INTO v_id
  FROM obos.barang b
  WHERE b.id_barang ~ '^[A-Za-z]+[0-9]+$'
  ORDER BY substring(b.id_barang from '([0-9]+)$')::integer DESC, b.id_barang DESC
  LIMIT 1;
  IF v_id IS NULL OR v_id !~ '^[A-Za-z]+[0-9]+$' THEN
    RETURN 'BR001';
  END IF;
  v_pre := substring(v_id from '^([A-Za-z]+)');
  v_num := substring(v_id from '([0-9]+)$');
  v_next := v_num::integer + 1;
  RETURN v_pre || lpad(v_next::text, GREATEST(length(v_num), length(v_next::text)), '0');
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_lingkup(OUT o_buku bigint, OUT o_tgl date)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
BEGIN
  o_buku := obos.buku_terbuka();
  IF o_buku IS NOT NULL THEN
    SELECT b.tanggal INTO o_tgl FROM obos.setoran_buku b WHERE b.id = o_buku;
  ELSE
    o_tgl := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_di_kartu(
  p_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_buku bigint,
  p_tgl_baris date
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT
    (p_buku IS NOT NULL AND p_id_buku = p_buku)
    OR (
      COALESCE(p_tutup, false) = false
      AND p_id_buku IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_geser_stok(p_id_barang text, p_delta numeric)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_nama text;
  v_delta numeric(14, 4);
BEGIN
  v_delta := round(COALESCE(p_delta, 0), 4);
  IF v_delta = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    UPDATE obos.barang
    SET stok = GREATEST(0, COALESCE(stok, 0) + v_delta)
    WHERE id_barang = p_id_barang;
    RETURN;
  END IF;

  SELECT b.tanggal INTO v_tgl FROM obos.setoran_buku b WHERE b.id = v_buku;
  SELECT b.nama_barang INTO v_nama FROM obos.barang b WHERE b.id_barang = p_id_barang;
  IF v_nama IS NULL THEN
    RAISE EXCEPTION 'SKU % tidak ada di katalog.', p_id_barang;
  END IF;

  INSERT INTO obos.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed, qty_masuk
  )
  VALUES (v_buku, v_tgl, p_id_barang, v_nama, 0, 0, GREATEST(0, v_delta))
  ON CONFLICT (id_setoran_buku, id_barang) DO UPDATE SET
    qty_masuk = GREATEST(0, obos.stok_opname.qty_masuk + v_delta),
    stok_fisik = CASE
      WHEN obos.stok_opname.stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, obos.stok_opname.stok_fisik + v_delta)
    END;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_terapkan_harga(
  p_id_supplier integer,
  p_id_barang text,
  p_harga numeric
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_kat integer;
  v_utama integer;
BEGIN
  v_kat := (round(GREATEST(COALESCE(p_harga, 0), 0) / 5) * 5)::integer;
  IF v_kat < 1 THEN
    RETURN 0;
  END IF;
  INSERT INTO obos.supplier_harga (id_supplier, id_barang, harga_beli)
  VALUES (p_id_supplier, p_id_barang, v_kat)
  ON CONFLICT (id_supplier, id_barang) DO UPDATE SET
    harga_beli = EXCLUDED.harga_beli;

  SELECT b.id_supplier_utama INTO v_utama
  FROM obos.barang b
  WHERE b.id_barang = p_id_barang;

  IF v_utama IS NULL THEN
    UPDATE obos.barang
    SET
      id_supplier_utama = p_id_supplier,
      harga_beli = GREATEST(harga_beli, v_kat),
      harga_jual = CASE
        WHEN GREATEST(harga_beli, v_kat) <> harga_beli OR harga_jual < 1
          THEN obos.jual_dari_modal(GREATEST(harga_beli, v_kat))
        ELSE harga_jual
      END
    WHERE id_barang = p_id_barang;
  ELSIF v_utama = p_id_supplier THEN
    UPDATE obos.barang
    SET
      harga_beli = GREATEST(harga_beli, v_kat),
      harga_jual = CASE
        WHEN GREATEST(harga_beli, v_kat) > harga_beli
          THEN obos.jual_dari_modal(GREATEST(harga_beli, v_kat))
        ELSE harga_jual
      END
    WHERE id_barang = p_id_barang;
  END IF;
  RETURN v_kat;
END;
$$;

CREATE OR REPLACE FUNCTION obos.supplier_daftar()
RETURNS TABLE (id integer, nama text)
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT s.id, s.nama
  FROM obos.supplier s
  WHERE s.aktif
  ORDER BY lower(s.nama);
$$;

CREATE OR REPLACE FUNCTION obos.supplier_tambah(p_nama text)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_nama text;
  v_id integer;
BEGIN
  v_nama := btrim(COALESCE(p_nama, ''));
  IF v_nama = '' THEN
    RAISE EXCEPTION 'Nama supplier wajib.';
  END IF;
  INSERT INTO obos.supplier (nama, aktif)
  VALUES (v_nama, true)
  ON CONFLICT (nama) DO UPDATE SET aktif = true
  RETURNING obos.supplier.id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_cari(p_q text)
RETURNS TABLE (id_barang text, nama_barang text, harga_beli integer)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_q text;
BEGIN
  v_q := lower(btrim(COALESCE(p_q, '')));
  IF length(v_q) < 1 THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT b.id_barang, b.nama_barang, b.harga_beli
  FROM obos.barang b
  WHERE COALESCE(b.aktif, true)
    AND (
      lower(b.id_barang) LIKE '%' || v_q || '%'
      OR lower(b.nama_barang) LIKE '%' || v_q || '%'
    )
  ORDER BY lower(b.nama_barang)
  LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_ringkas(p_id_buku bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_tutup boolean := false;
  v_sku integer := 0;
  v_nilai bigint := 0;
  v_ongkir bigint := 0;
  v_supplier jsonb := '[]'::jsonb;
BEGIN
  IF p_id_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup INTO v_buku, v_tgl, v_tutup
    FROM obos.setoran_buku b
    WHERE b.id = p_id_buku;
  ELSE
    SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();
    v_tutup := false;
  END IF;

  SELECT
    count(*)::integer,
    coalesce(sum(m.nilai), 0)::bigint
  INTO v_sku, v_nilai
  FROM obos.barang_masuk m
  WHERE obos.barang_masuk_di_kartu(
    v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal
  );

  SELECT coalesce(sum(o.jumlah), 0)::bigint
  INTO v_ongkir
  FROM obos.ongkir o
  WHERE obos.barang_masuk_di_kartu(
    v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal
  );

  SELECT coalesce(jsonb_agg(x.obj ORDER BY lower(x.nama)), '[]'::jsonb)
  INTO v_supplier
  FROM (
    SELECT
      jsonb_build_object(
        'id', s.id,
        'nama', s.nama,
        'sku', coalesce(m.sku, 0),
        'nilai', coalesce(m.nilai, 0),
        'ongkir', coalesce(o.jumlah, 0)
      ) AS obj,
      s.nama
    FROM (
      SELECT DISTINCT m.id_supplier
      FROM obos.barang_masuk m
      WHERE obos.barang_masuk_di_kartu(
        v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal
      )
      UNION
      SELECT DISTINCT o.id_supplier
      FROM obos.ongkir o
      WHERE obos.barang_masuk_di_kartu(
        v_buku, v_tgl, v_tutup, o.id_setoran_buku, o.tanggal
      )
    ) ids
    JOIN obos.supplier s ON s.id = ids.id_supplier
    LEFT JOIN LATERAL (
      SELECT
        count(*)::integer AS sku,
        coalesce(sum(mm.nilai), 0)::bigint AS nilai
      FROM obos.barang_masuk mm
      WHERE mm.id_supplier = s.id
        AND obos.barang_masuk_di_kartu(
          v_buku, v_tgl, v_tutup, mm.id_setoran_buku, mm.tanggal
        )
    ) m ON true
    LEFT JOIN LATERAL (
      SELECT coalesce(sum(oo.jumlah), 0)::bigint AS jumlah
      FROM obos.ongkir oo
      WHERE oo.id_supplier = s.id
        AND obos.barang_masuk_di_kartu(
          v_buku, v_tgl, v_tutup, oo.id_setoran_buku, oo.tanggal
        )
    ) o ON true
  ) x;

  RETURN jsonb_build_object(
    'ada_buku', v_buku IS NOT NULL,
    'id_setoran_buku', v_buku,
    'tanggal', v_tgl,
    'sku', v_sku,
    'nilai', v_nilai,
    'ongkir', v_ongkir,
    'supplier', v_supplier
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_lihat(
  p_id_supplier integer,
  p_id_buku bigint DEFAULT NULL
)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  qty numeric,
  nilai integer,
  harga_beli integer
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_tutup boolean := false;
BEGIN
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RETURN;
  END IF;
  IF p_id_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup INTO v_buku, v_tgl, v_tutup
    FROM obos.setoran_buku b
    WHERE b.id = p_id_buku;
  ELSE
    SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();
  END IF;
  RETURN QUERY
  SELECT
    m.id_barang,
    b.nama_barang,
    m.qty,
    m.nilai,
    CASE
      WHEN m.qty > 0 THEN round(m.nilai / m.qty)::integer
      ELSE COALESCE(h.harga_beli, 0)
    END
  FROM obos.barang_masuk m
  JOIN obos.barang b ON b.id_barang = m.id_barang
  LEFT JOIN obos.supplier_harga h
    ON h.id_supplier = m.id_supplier AND h.id_barang = m.id_barang
  WHERE m.id_supplier = p_id_supplier
    AND obos.barang_masuk_di_kartu(
      v_buku, v_tgl, v_tutup, m.id_setoran_buku, m.tanggal
    )
  ORDER BY lower(b.nama_barang);
END;
$$;

CREATE OR REPLACE FUNCTION obos.ongkir_lihat(p_id_supplier integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v integer;
BEGIN
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RETURN 0;
  END IF;
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();
  SELECT o.jumlah INTO v
  FROM obos.ongkir o
  WHERE o.id_supplier = p_id_supplier
    AND (
      (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
      OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl)
    );
  RETURN COALESCE(v, 0);
END;
$$;

CREATE OR REPLACE FUNCTION obos.ongkir_simpan(p_id_supplier integer, p_jumlah integer)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_jml integer;
BEGIN
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RAISE EXCEPTION 'Pilih supplier.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM obos.supplier s WHERE s.id = p_id_supplier AND s.aktif) THEN
    RAISE EXCEPTION 'Supplier tidak aktif.';
  END IF;
  v_jml := GREATEST(COALESCE(p_jumlah, 0), 0);
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();
  IF v_jml = 0 THEN
    DELETE FROM obos.ongkir o
    WHERE o.id_supplier = p_id_supplier
      AND (
        (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
        OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl)
      );
    RETURN;
  END IF;
  IF v_buku IS NOT NULL THEN
    INSERT INTO obos.ongkir (tanggal, id_supplier, jumlah, id_setoran_buku)
    VALUES (v_tgl, p_id_supplier, v_jml, v_buku)
    ON CONFLICT (id_setoran_buku, id_supplier) WHERE id_setoran_buku IS NOT NULL
    DO UPDATE SET jumlah = EXCLUDED.jumlah;
  ELSE
    INSERT INTO obos.ongkir (tanggal, id_supplier, jumlah, id_setoran_buku)
    VALUES (v_tgl, p_id_supplier, v_jml, NULL)
    ON CONFLICT (tanggal, id_supplier) WHERE id_setoran_buku IS NULL
    DO UPDATE SET jumlah = EXCLUDED.jumlah;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_simpan(
  p_id_supplier integer,
  p_baris jsonb,
  p_ongkir integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  r jsonb;
  v_buku bigint;
  v_tgl date;
  v_kode text;
  v_kode_in text;
  v_nama text;
  v_nama_dasar text;
  v_satuan text;
  v_rincian text;
  v_kategori text;
  v_qty numeric(14, 4);
  v_harga numeric;
  v_nilai integer;
  v_baru boolean;
  v_n integer := 0;
BEGIN
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RAISE EXCEPTION 'Pilih supplier.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM obos.supplier s WHERE s.id = p_id_supplier AND s.aktif) THEN
    RAISE EXCEPTION 'Supplier tidak aktif.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar barang wajib.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();

  FOR r IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_baru := COALESCE((r ->> 'baru')::boolean, false);
    v_kode := nullif(btrim(COALESCE(r ->> 'id_barang', r ->> 'kode_barang', '')), '');
    v_nama_dasar := btrim(COALESCE(r ->> 'nama', ''));
    v_satuan := btrim(COALESCE(r ->> 'satuan', ''));
    v_rincian := btrim(COALESCE(r ->> 'rincian', ''));
    v_kategori := btrim(COALESCE(r ->> 'kategori', ''));
    v_qty := round(
      GREATEST(COALESCE(replace(btrim(COALESCE(r ->> 'qty', '')), ',', '.')::numeric, 0), 0),
      4
    );
    v_harga := GREATEST(
      COALESCE(replace(btrim(COALESCE(r ->> 'harga_beli', '')), ',', '.')::numeric, 0),
      0
    );
    IF v_qty <= 0 OR v_harga <= 0 THEN
      CONTINUE;
    END IF;
    v_nilai := round(v_qty * v_harga)::integer;

    IF v_baru THEN
      IF v_nama_dasar = '' OR v_satuan = '' THEN
        RAISE EXCEPTION 'SKU baru wajib nama dan satuan.';
      END IF;
      v_nama := v_nama_dasar || ' /' || v_satuan;
      IF v_rincian <> '' THEN
        v_nama := v_nama || '/' || v_rincian;
      END IF;
      v_kode := obos.barang_id_berikut();
      INSERT INTO obos.barang (
        id_barang, nama_barang, kategori, stok, harga_beli, harga_jual, id_supplier_utama
      )
      VALUES (
        v_kode, v_nama, nullif(v_kategori, ''), 0, 0, 0, p_id_supplier
      );
    ELSE
      IF v_kode IS NULL THEN
        RAISE EXCEPTION 'Kode barang kosong.';
      END IF;
      v_kode_in := v_kode;
      SELECT b.id_barang INTO v_kode
      FROM obos.barang b
      WHERE lower(b.id_barang) = lower(v_kode_in);
      IF v_kode IS NULL THEN
        RAISE EXCEPTION 'Kode % tidak ada di katalog. SKU baru isi di form SKU baru.', v_kode_in;
      END IF;
    END IF;

    PERFORM obos.barang_masuk_geser_stok(v_kode, v_qty);
    PERFORM obos.barang_masuk_terapkan_harga(p_id_supplier, v_kode, v_harga);

    IF v_buku IS NOT NULL THEN
      INSERT INTO obos.barang_masuk (
        tanggal, id_supplier, id_barang, qty, nilai, id_setoran_buku
      )
      VALUES (v_tgl, p_id_supplier, v_kode, v_qty, v_nilai, v_buku)
      ON CONFLICT (id_setoran_buku, id_supplier, id_barang)
      WHERE id_setoran_buku IS NOT NULL
      DO UPDATE SET
        qty = obos.barang_masuk.qty + EXCLUDED.qty,
        nilai = obos.barang_masuk.nilai + EXCLUDED.nilai;
    ELSE
      INSERT INTO obos.barang_masuk (
        tanggal, id_supplier, id_barang, qty, nilai, id_setoran_buku
      )
      VALUES (v_tgl, p_id_supplier, v_kode, v_qty, v_nilai, NULL)
      ON CONFLICT (tanggal, id_supplier, id_barang)
      WHERE id_setoran_buku IS NULL
      DO UPDATE SET
        qty = obos.barang_masuk.qty + EXCLUDED.qty,
        nilai = obos.barang_masuk.nilai + EXCLUDED.nilai;
    END IF;
    v_n := v_n + 1;
  END LOOP;

  IF p_ongkir IS NOT NULL THEN
    PERFORM obos.ongkir_simpan(p_id_supplier, p_ongkir);
  END IF;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_ubah(
  p_id_supplier integer,
  p_id_barang text,
  p_qty numeric,
  p_harga_beli numeric
)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_kode text;
  v_qty numeric(14, 4);
  v_lama numeric(14, 4);
  v_harga numeric;
  v_nilai integer;
BEGIN
  v_kode := nullif(btrim(COALESCE(p_id_barang, '')), '');
  v_qty := round(GREATEST(COALESCE(p_qty, 0), 0), 4);
  v_harga := GREATEST(COALESCE(p_harga_beli, 0), 0);
  IF COALESCE(p_id_supplier, 0) < 1 OR v_kode IS NULL OR v_qty <= 0 OR v_harga <= 0 THEN
    RAISE EXCEPTION 'Qty dan harga beli wajib lebih dari nol.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();

  SELECT m.qty INTO v_lama
  FROM obos.barang_masuk m
  WHERE m.id_supplier = p_id_supplier
    AND m.id_barang = v_kode
    AND (
      (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
      OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl)
    )
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baris barang masuk tidak ada.';
  END IF;

  v_nilai := round(v_qty * v_harga)::integer;
  PERFORM obos.barang_masuk_geser_stok(v_kode, v_qty - v_lama);
  PERFORM obos.barang_masuk_terapkan_harga(p_id_supplier, v_kode, v_harga);

  UPDATE obos.barang_masuk m
  SET qty = v_qty, nilai = v_nilai
  WHERE m.id_supplier = p_id_supplier
    AND m.id_barang = v_kode
    AND (
      (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
      OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl)
    );
END;
$$;

CREATE OR REPLACE FUNCTION obos.barang_masuk_hapus(
  p_id_supplier integer,
  p_id_barang text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_kode text;
  v_lama numeric(14, 4);
BEGIN
  v_kode := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF COALESCE(p_id_supplier, 0) < 1 OR v_kode IS NULL THEN
    RAISE EXCEPTION 'SKU kosong.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM obos.barang_masuk_lingkup();

  SELECT m.qty INTO v_lama
  FROM obos.barang_masuk m
  WHERE m.id_supplier = p_id_supplier
    AND m.id_barang = v_kode
    AND (
      (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
      OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl)
    )
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baris barang masuk tidak ada.';
  END IF;

  PERFORM obos.barang_masuk_geser_stok(v_kode, -v_lama);
  DELETE FROM obos.barang_masuk m
  WHERE m.id_supplier = p_id_supplier
    AND m.id_barang = v_kode
    AND (
      (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
      OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl)
    );
END;
$$;

CREATE OR REPLACE FUNCTION obos.users_kasbon()
RETURNS TABLE (email text, nama text, peran text)
LANGUAGE sql
STABLE
SET search_path = obos
AS $$
  SELECT u.email, u.nama, u.peran
  FROM obos.users u
  ORDER BY lower(u.nama), u.email;
$$;

CREATE OR REPLACE FUNCTION obos.opname_fisik(
  p_id_barang text,
  p_qty numeric,
  p_dicek_oleh text DEFAULT ''
)
RETURNS void
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
  v_sku text;
  v_qty numeric(14, 4);
BEGIN
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Fisik tidak bisa diubah.';
  END IF;
  v_sku := btrim(COALESCE(p_id_barang, ''));
  IF v_sku = '' THEN
    RAISE EXCEPTION 'SKU wajib.';
  END IF;
  v_qty := round(GREATEST(COALESCE(p_qty, 0), 0), 4);

  PERFORM pg_advisory_xact_lock(88221940);

  IF EXISTS (
    SELECT 1
    FROM obos.barang b
    WHERE lower(b.id_barang) = lower(v_sku)
      AND NOT COALESCE(b.aktif, true)
  ) THEN
    RAISE EXCEPTION 'SKU nonaktif tidak diopname.';
  END IF;

  UPDATE obos.stok_opname
  SET
    stok_fisik = v_qty,
    dicek_stok_oleh = nullif(btrim(COALESCE(p_dicek_oleh, '')), '')
  WHERE id_setoran_buku = v_buku
    AND lower(id_barang) = lower(v_sku);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SKU tidak ada di buku ini.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION obos.opname_putusan(
  p_id_setoran_buku bigint,
  p_id_barang text,
  p_jenis text,
  p_email text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_tutup boolean;
  v_jenis text;
  v_sku text;
  v_selisih numeric;
  v_harga integer;
  v_nilai integer;
  v_email text;
  v_nama text;
  v_n integer;
  v_buka bigint;
BEGIN
  IF p_id_setoran_buku IS NULL OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RAISE EXCEPTION 'Buku atau SKU kosong.';
  END IF;
  v_jenis := lower(btrim(COALESCE(p_jenis, '')));
  IF v_jenis NOT IN ('kasbon', 'beban') THEN
    RAISE EXCEPTION 'Jenis putusan wajib kasbon atau beban.';
  END IF;

  SELECT b.ditutup INTO v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = p_id_setoran_buku;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Buku tidak ada.';
  END IF;
  IF COALESCE(v_tutup, false) THEN
    RAISE EXCEPTION 'Buku sudah ditutup.';
  END IF;
  v_buka := obos.buku_terbuka();
  IF v_buka IS DISTINCT FROM p_id_setoran_buku THEN
    RAISE EXCEPTION 'Hanya buku terbuka yang bisa diputuskan.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);

  SELECT
    so.id_barang,
    so.selisih,
    GREATEST(
      COALESCE(b.harga_beli, 0),
      COALESCE((
        SELECT max(i.harga_beli)
        FROM obos.transaksi_items i
        WHERE lower(i.id_barang) = lower(so.id_barang)
      ), 0)
    )::integer
  INTO v_sku, v_selisih, v_harga
  FROM obos.stok_opname so
  LEFT JOIN obos.barang b ON lower(b.id_barang) = lower(so.id_barang)
  WHERE so.id_setoran_buku = p_id_setoran_buku
    AND lower(so.id_barang) = lower(btrim(p_id_barang));
  IF v_sku IS NULL THEN
    RAISE EXCEPTION 'SKU tidak ada di buku ini.';
  END IF;
  IF v_selisih IS NULL OR v_selisih >= 0 THEN
    RAISE EXCEPTION 'Hanya selisih kurang yang dipilih kasbon atau beban.';
  END IF;

  v_nilai := round(abs(v_selisih) * v_harga)::integer;

  IF v_jenis = 'kasbon' THEN
    SELECT u.email, u.nama
    INTO v_email, v_nama
    FROM obos.users u
    WHERE lower(btrim(u.email)) = lower(btrim(COALESCE(p_email, '')));
    IF v_email IS NULL THEN
      RAISE EXCEPTION 'Pilih karyawan untuk kasbon.';
    END IF;
    IF v_nilai < 1 THEN
      RAISE EXCEPTION
        'Nilai kasbon SKU % nol. Isi harga beli barang dulu.',
        v_sku;
    END IF;
  ELSE
    v_email := NULL;
    v_nama := NULL;
  END IF;

  UPDATE obos.stok_opname
  SET
    putusan = v_jenis,
    nilai_putusan = v_nilai,
    harga_beli_putusan = v_harga,
    qty_selisih_putusan = v_selisih,
    kasbon_email = v_email,
    kasbon_nama = v_nama,
    waktu_putusan = clock_timestamp()
  WHERE id_setoran_buku = p_id_setoran_buku
    AND lower(id_barang) = lower(v_sku);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n < 1 THEN
    RAISE EXCEPTION 'Putusan SKU % tidak tertulis.', v_sku;
  END IF;

  DELETE FROM obos.kasbon
  WHERE id_setoran_buku = p_id_setoran_buku
    AND lower(id_barang) = lower(v_sku);

  IF v_jenis = 'kasbon' THEN
    INSERT INTO obos.kasbon (
      email, nama, nilai, id_setoran_buku, id_barang
    ) VALUES (
      v_email, v_nama, v_nilai, p_id_setoran_buku, v_sku
    );
  END IF;

  RETURN jsonb_build_object(
    'id_barang', v_sku,
    'putusan', v_jenis,
    'nilai', v_nilai,
    'kasbon_email', v_email,
    'kasbon_nama', v_nama
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.opname_gudang_isi()
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  stok_awal numeric,
  qty_packed numeric,
  stok_hitung numeric,
  stok_fisik numeric,
  selisih numeric,
  dicek_stok_oleh text,
  id_setoran_buku bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_buku bigint;
BEGIN
  v_buku := obos.buku_terbuka();
  IF v_buku IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    so.id_barang,
    so.nama_barang,
    so.stok_awal,
    so.qty_packed,
    so.stok_hitung,
    so.stok_fisik,
    so.selisih,
    so.dicek_stok_oleh,
    so.id_setoran_buku
  FROM obos.stok_opname so
  LEFT JOIN obos.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = v_buku
    AND COALESCE(b.aktif, true)
  ORDER BY lower(so.nama_barang), so.id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION obos.opname_ringkas(p_id_buku bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_total integer := 0;
  v_fisik integer := 0;
  v_selisih integer := 0;
  v_nilai bigint := 0;
  v_minus_belum integer := 0;
  v_kasbon bigint := 0;
  v_beban bigint := 0;
  v_plus bigint := 0;
BEGIN
  IF p_id_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup INTO v_id, v_tgl, v_tutup
    FROM obos.setoran_buku b
    WHERE b.id = p_id_buku;
  ELSE
    SELECT b.id, b.tanggal, b.ditutup INTO v_id, v_tgl, v_tutup
    FROM obos.setoran_buku b
    WHERE NOT b.ditutup
    ORDER BY b.id
    LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'sku_total', 0,
      'sku_fisik', 0,
      'sku_selisih', 0,
      'nilai_selisih', 0,
      'sku_minus_belum', 0,
      'nilai_kasbon', 0,
      'nilai_beban', 0,
      'nilai_margin_plus', 0
    );
  END IF;

  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer,
    count(*) FILTER (
      WHERE so.stok_fisik IS NOT NULL AND COALESCE(so.selisih, 0) <> 0
    )::integer,
    coalesce(sum(
      CASE
        WHEN so.stok_fisik IS NULL THEN 0
        ELSE round(COALESCE(so.selisih, 0) * COALESCE(b.harga_beli, 0))
      END
    ), 0)::bigint,
    count(*) FILTER (
      WHERE so.stok_fisik IS NOT NULL
        AND COALESCE(so.selisih, 0) < 0
        AND so.putusan IS DISTINCT FROM 'kasbon'
        AND so.putusan IS DISTINCT FROM 'beban'
    )::integer,
    coalesce(sum(so.nilai_putusan) FILTER (WHERE so.putusan = 'kasbon'), 0)::bigint,
    coalesce(sum(so.nilai_putusan) FILTER (WHERE so.putusan = 'beban'), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN so.stok_fisik IS NOT NULL AND COALESCE(so.selisih, 0) > 0
          THEN round(so.selisih * COALESCE(b.harga_beli, 0))
        ELSE 0
      END
    ), 0)::bigint
  INTO v_total, v_fisik, v_selisih, v_nilai, v_minus_belum, v_kasbon, v_beban, v_plus
  FROM obos.stok_opname so
  LEFT JOIN obos.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = v_id
    AND COALESCE(b.aktif, true);

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', COALESCE(v_tutup, false),
    'sku_total', v_total,
    'sku_fisik', v_fisik,
    'sku_selisih', v_selisih,
    'nilai_selisih', v_nilai,
    'sku_minus_belum', v_minus_belum,
    'nilai_kasbon', v_kasbon,
    'nilai_beban', v_beban,
    'nilai_margin_plus', v_plus
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.opname_lihat(p_id_setoran_buku bigint)
RETURNS TABLE (
  id_barang text,
  nama_barang text,
  stok_awal numeric,
  qty_packed numeric,
  stok_hitung numeric,
  stok_fisik numeric,
  selisih numeric,
  nilai_selisih integer,
  harga_beli integer,
  dicek_stok_oleh text,
  putusan text,
  kasbon_email text,
  kasbon_nama text,
  nilai_putusan integer,
  toko_packed jsonb
)
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
BEGIN
  IF p_id_setoran_buku IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    so.id_barang,
    so.nama_barang,
    so.stok_awal,
    so.qty_packed,
    so.stok_hitung,
    so.stok_fisik,
    so.selisih,
    round(COALESCE(so.selisih, 0) * COALESCE(b.harga_beli, 0))::integer,
    COALESCE(b.harga_beli, 0),
    so.dicek_stok_oleh,
    so.putusan,
    so.kasbon_email,
    so.kasbon_nama,
    so.nilai_putusan,
    COALESCE(p.toko, '[]'::jsonb)
  FROM obos.stok_opname so
  LEFT JOIN obos.barang b ON b.id_barang = so.id_barang
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id_pelanggan', x.id_pelanggan,
        'nama', x.nama_pelanggan,
        'qty', x.qty
      )
      ORDER BY lower(x.nama_pelanggan)
    ) AS toko
    FROM (
      SELECT
        t.id_pelanggan,
        max(t.nama_pelanggan) AS nama_pelanggan,
        sum(COALESCE(i.qty_packed, 0))::numeric AS qty
      FROM obos.transaksi t
      JOIN obos.transaksi_items i ON i.id_transaksi = t.id_transaksi
      WHERE t.id_setoran_buku = p_id_setoran_buku
        AND i.id_barang = so.id_barang
        AND COALESCE(i.qty_packed, 0) > 0
      GROUP BY t.id_pelanggan
    ) x
  ) p ON true
  WHERE so.id_setoran_buku = p_id_setoran_buku
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) <> 0
  ORDER BY
    CASE WHEN COALESCE(so.selisih, 0) < 0 THEN 0 ELSE 1 END,
    lower(so.nama_barang),
    so.id_barang;
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
        'stok_opname_bersih_putusan', 'stok_catat_retur',
        'retur_toko_lihat', 'retur_rute_lihat', 'retur_toko_simpan',
        'jual_dari_modal', 'barang_id_berikut', 'barang_masuk_lingkup',
        'barang_masuk_di_kartu', 'barang_masuk_geser_stok',
        'barang_masuk_terapkan_harga', 'supplier_daftar', 'supplier_tambah',
        'barang_cari', 'barang_masuk_ringkas', 'barang_masuk_lihat',
        'ongkir_lihat', 'ongkir_simpan',
        'barang_masuk_simpan', 'barang_masuk_ubah', 'barang_masuk_hapus',
        'users_kasbon', 'opname_fisik', 'opname_putusan',
        'opname_gudang_isi', 'opname_ringkas', 'opname_lihat'
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
