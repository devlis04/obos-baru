-- Selama buku terbuka, pengirim boleh buka-kunci nota terkunci dan
-- ubah setoran di baris yang sama. Buku ditutup = beku.
-- Jalankan SETELAH 043. Boleh diulang.

CREATE OR REPLACE FUNCTION public.stok_catat_batal(
  p_id_barang text,
  p_qty numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_qty numeric(14, 4);
  v_packed numeric(14, 4);
  v_batal numeric(14, 4);
  v_baru numeric(14, 4);
  v_geser numeric(14, 4);
BEGIN
  v_qty := round(COALESCE(p_qty, 0), 4);
  IF v_qty = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang
    SET stok = GREATEST(0, COALESCE(stok, 0) + v_qty)
    WHERE id_barang = p_id_barang;
    RETURN;
  END IF;

  SELECT so.qty_packed, so.qty_batal
  INTO v_packed, v_batal
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_buku
    AND so.id_barang = p_id_barang
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_baru := GREATEST(0, LEAST(COALESCE(v_packed, 0), COALESCE(v_batal, 0) + v_qty));
  v_geser := v_baru - COALESCE(v_batal, 0);
  IF v_geser = 0 THEN
    RETURN;
  END IF;

  UPDATE public.stok_opname
  SET
    qty_batal = v_baru,
    stok_fisik = CASE
      WHEN stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, stok_fisik + v_geser)
    END
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.stok_kembali_packing(
  p_id_barang text,
  p_qty numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  PERFORM public.stok_catat_batal(p_id_barang, GREATEST(COALESCE(p_qty, 0), 0));
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

  SELECT t.status, t.waktu_packed, t.id_setoran_buku
  INTO v_status, v_packed, v_buku_nota
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
  IF v_buku_nota IS NOT NULL AND v_buku_nota IS DISTINCT FROM v_buku THEN
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
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
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

  SELECT t.status INTO v_status
  FROM public.transaksi t
  WHERE t.id_transaksi = v_id
    AND t.rute = ANY (v_sales)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Nota tidak ada di rute Anda.';
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

CREATE OR REPLACE FUNCTION public.pengirim_retur_dikunci(p_tanggal date)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_open bigint;
  v_buku bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() OR p_tanggal IS NULL THEN
    RETURN true;
  END IF;
  v_open := public.setoran_buku_terbuka();
  v_buku := public.pengirim_buku_hari(p_tanggal);
  IF v_open IS NULL OR v_buku IS NULL OR v_buku IS DISTINCT FROM v_open THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_retur_toko_simpan(
  p_tanggal date,
  p_id_pelanggan text,
  p_baris jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_id text;
  v_hari date;
  v_buku bigint;
  r jsonb;
  v_kode text;
  v_nama text;
  v_qty integer;
  v_harga integer;
  rec record;
BEGIN
  IF NOT public.pengirim_sedang_login() OR p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  IF p_tanggal <> v_hari THEN
    RAISE EXCEPTION 'Retur hanya bisa dicatat untuk hari ini.';
  END IF;
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  v_id := nullif(btrim(COALESCE(p_id_pelanggan, '')), '');
  IF v_rute IS NULL OR v_id IS NULL THEN
    RETURN false;
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku setoran terbuka. Retur tidak dicatat ke tanggal berikutnya.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_rute), hashtext(v_buku::text));

  IF NOT EXISTS (
    SELECT 1 FROM public.kunjungan_pengirim k
    WHERE k.tanggal = p_tanggal
      AND k.id_pelanggan = v_id
      AND k.waktu_masuk IS NOT NULL
      AND public.pengirim_grup_rute(k.rute_pengirim) = v_rute
  ) THEN
    RAISE EXCEPTION 'Check-in toko dulu sebelum mencatat retur.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RETURN false;
  END IF;

  CREATE TEMP TABLE tmp_retur_baru (
    kode text PRIMARY KEY,
    nama text,
    qty integer,
    harga integer
  ) ON COMMIT DROP;

  FOR r IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_kode := nullif(btrim(COALESCE(r ->> 'kode_barang', '')), '');
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
        CASE WHEN v_nama = '' THEN COALESCE(NULLIF(btrim(b.nama_barang), ''), v_kode) ELSE v_nama END,
        CASE WHEN v_harga <= 0 THEN COALESCE(b.harga_jual, 0) ELSE v_harga END
      INTO v_nama, v_harga
      FROM public.barang b
      WHERE b.id_barang = v_kode;
      v_nama := COALESCE(v_nama, v_kode);
      v_harga := COALESCE(v_harga, 0);
    END IF;
    INSERT INTO tmp_retur_baru (kode, nama, qty, harga)
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
      FROM public.retur_toko
      WHERE id_setoran_buku = v_buku
        AND rute_pengirim = v_rute
        AND id_pelanggan = v_id
    ) l
    FULL JOIN tmp_retur_baru n ON n.kode = l.kode_barang
  LOOP
    IF rec.baru > rec.lama THEN
      PERFORM public.stok_catat_retur(rec.kode, rec.baru - rec.lama);
    ELSIF rec.lama > rec.baru THEN
      PERFORM public.stok_catat_retur(rec.kode, rec.baru - rec.lama);
    END IF;
  END LOOP;

  DELETE FROM public.retur_toko
  WHERE id_setoran_buku = v_buku
    AND rute_pengirim = v_rute
    AND id_pelanggan = v_id;

  INSERT INTO public.retur_toko (
    rute_pengirim, id_pelanggan, kode_barang, nama_barang, qty, harga_jual
  )
  SELECT v_rute, v_id, kode, nama, qty, harga
  FROM tmp_retur_baru;

  RETURN true;
END;
$$;

DROP FUNCTION IF EXISTS public.pengirim_setoran_lihat();

CREATE OR REPLACE FUNCTION public.pengirim_setoran_lihat()
RETURNS TABLE (
  jumlah_transfer integer,
  jumlah_tunai integer,
  jumlah_bop integer,
  kasbon_supir integer,
  kasbon_kenek integer,
  sudah_ada boolean,
  bisa_ubah boolean,
  dicatat_oleh text,
  dicatat_rute text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_buku bigint;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RETURN;
  END IF;
  v_rute := public.pengirim_grup_rute(public.pengirim_rute_saya());
  v_buku := public.setoran_buku_terbuka();
  IF v_rute IS NULL THEN
    RETURN;
  END IF;
  IF v_buku IS NULL THEN
    RETURN QUERY SELECT 0, 0, 0, 0, 0, false, false, ''::text, ''::text;
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    COALESCE(s.jumlah_transfer, 0),
    COALESCE(s.jumlah_tunai, 0),
    COALESCE(s.jumlah_bop, 0),
    COALESCE(s.kasbon_supir, 0),
    COALESCE(s.kasbon_kenek, 0),
    (s.id IS NOT NULL),
    true,
    COALESCE(s.dicatat_oleh, ''),
    COALESCE(s.dicatat_rute, '')
  FROM (SELECT 1) z
  LEFT JOIN public.setoran_pengirim s
    ON s.rute_pengirim = v_rute
   AND s.id_setoran_buku = v_buku;
END;
$$;

CREATE OR REPLACE FUNCTION public.pengirim_setoran_simpan(
  p_jumlah_transfer integer,
  p_jumlah_tunai integer,
  p_jumlah_bop integer,
  p_kasbon_supir integer,
  p_kasbon_kenek integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_rute text;
  v_akun text;
  v_nama text;
  v_buku bigint;
  v_tr integer;
  v_tu integer;
  v_bop integer;
  v_ks integer;
  v_kk integer;
BEGIN
  IF NOT public.pengirim_sedang_login() THEN
    RAISE EXCEPTION 'Sesi login tidak aktif.';
  END IF;
  IF public.pengirim_id_absensi_saya() IS NULL THEN
    RAISE EXCEPTION 'Belum scan masuk.';
  END IF;
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran sudah ditutup. Setoran tidak bisa diubah.';
  END IF;
  v_akun := public.pengirim_rute_saya();
  v_rute := public.pengirim_grup_rute(v_akun);
  IF v_rute IS NULL OR btrim(COALESCE(v_akun, '')) = '' THEN
    RAISE EXCEPTION 'Rute pengirim tidak ada.';
  END IF;

  v_tr := GREATEST(COALESCE(p_jumlah_transfer, 0), 0);
  v_tu := GREATEST(COALESCE(p_jumlah_tunai, 0), 0);
  v_bop := GREATEST(COALESCE(p_jumlah_bop, 0), 0);
  v_ks := GREATEST(COALESCE(p_kasbon_supir, 0), 0);
  v_kk := GREATEST(COALESCE(p_kasbon_kenek, 0), 0);
  IF v_bop > 170000 THEN
    RAISE EXCEPTION 'BOP maksimal Rp 170.000.';
  END IF;

  SELECT COALESCE(NULLIF(btrim(u.nama), ''), u.email)
  INTO v_nama
  FROM public.users u
  WHERE lower(btrim(u.email)) = public.email_jwt()
    AND u.peran = 'pengirim'
  LIMIT 1;

  INSERT INTO public.setoran_pengirim (
    rute_pengirim,
    id_setoran_buku,
    jumlah_transfer,
    jumlah_tunai,
    jumlah_bop,
    kasbon_supir,
    kasbon_kenek,
    waktu_setor,
    dicatat_oleh,
    dicatat_rute
  )
  VALUES (
    v_rute,
    v_buku,
    v_tr,
    v_tu,
    v_bop,
    v_ks,
    v_kk,
    clock_timestamp(),
    COALESCE(v_nama, ''),
    v_akun
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

REVOKE ALL ON FUNCTION public.stok_catat_batal(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stok_catat_batal(text, numeric)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.pengirim_buka_kunci_nota(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_buka_kunci_nota(text)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.pengirim_setoran_lihat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_setoran_lihat()
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.pengirim_setoran_simpan(integer, integer, integer, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_setoran_simpan(integer, integer, integer, integer, integer)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
