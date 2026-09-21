-- Opname: stok_awal tetap snapshot. Masuk / packing / batal / retur kolom sendiri.
-- stok_hitung = awal + masuk - packed + batal + retur.
-- Barang masuk hanya qty_masuk (+ fisik jika sudah diisi).
-- Batal nota + sisa tebus → qty_batal (qty_packed tidak berkurang).
-- Retur toko → qty_retur.
-- Jalankan SETELAH 040. Boleh diulang.

ALTER TABLE public.stok_opname
  ADD COLUMN IF NOT EXISTS qty_masuk numeric(14, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS qty_batal numeric(14, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS qty_retur numeric(14, 4) NOT NULL DEFAULT 0;

ALTER TABLE public.stok_opname
  DROP COLUMN IF EXISTS stok_hitung,
  DROP COLUMN IF EXISTS selisih;

ALTER TABLE public.stok_opname
  ADD COLUMN stok_hitung numeric(14, 4) GENERATED ALWAYS AS (
    stok_awal + qty_masuk - qty_packed + qty_batal + qty_retur
  ) STORED,
  ADD COLUMN selisih numeric(14, 4) GENERATED ALWAYS AS (
    stok_fisik - (stok_awal + qty_masuk - qty_packed + qty_batal + qty_retur)
  ) STORED;

COMMENT ON COLUMN public.stok_opname.stok_awal IS
  'Snapshot saat buku dibuka. Tidak digeser barang masuk.';
COMMENT ON COLUMN public.stok_opname.qty_masuk IS
  'Barang masuk selama buku ini.';
COMMENT ON COLUMN public.stok_opname.qty_packed IS
  'Qty packing ke buku ini. Tidak dikurangi batal/retur/sisa tebus.';
COMMENT ON COLUMN public.stok_opname.qty_batal IS
  'Kembali dari jalan: batal nota + sisa tebus (packed − actual).';
COMMENT ON COLUMN public.stok_opname.qty_retur IS
  'Klaim retur toko selama buku ini.';
COMMENT ON COLUMN public.stok_opname.stok_hitung IS
  'stok_awal + qty_masuk − qty_packed + qty_batal + qty_retur.';
COMMENT ON COLUMN public.stok_opname.selisih IS
  'stok_fisik − stok_hitung. Kosong jika belum fisik.';

-- Rapikan jejak dari transaksi / retur yang sudah tercatat.
UPDATE public.stok_opname so
SET
  qty_packed = GREATEST(so.qty_packed, j.packed),
  qty_batal = LEAST(GREATEST(so.qty_packed, j.packed), j.batal)
FROM (
  SELECT
    t.id_setoran_buku,
    i.id_barang,
    coalesce(sum(COALESCE(i.qty_packed, 0)), 0)::numeric(14, 4) AS packed,
    coalesce(sum(
      CASE
        WHEN t.status = 'batal' THEN COALESCE(i.qty_packed, 0)
        WHEN t.status = 'terkirim' THEN GREATEST(
          COALESCE(i.qty_packed, 0) - COALESCE(i.qty_actual, 0),
          0
        )
        ELSE 0
      END
    ), 0)::numeric(14, 4) AS batal
  FROM public.transaksi t
  JOIN public.transaksi_items i ON i.id_transaksi = t.id_transaksi
  WHERE t.id_setoran_buku IS NOT NULL
    AND t.waktu_packed IS NOT NULL
  GROUP BY t.id_setoran_buku, i.id_barang
) j
WHERE so.id_setoran_buku = j.id_setoran_buku
  AND so.id_barang = j.id_barang;

UPDATE public.stok_opname so
SET qty_retur = GREATEST(so.qty_retur, r.qty)
FROM (
  SELECT
    rt.id_setoran_buku,
    rt.kode_barang AS id_barang,
    coalesce(sum(rt.qty), 0)::numeric(14, 4) AS qty
  FROM public.retur_toko rt
  GROUP BY rt.id_setoran_buku, rt.kode_barang
) r
WHERE so.id_setoran_buku = r.id_setoran_buku
  AND so.id_barang = r.id_barang;

ALTER TABLE public.stok_opname
  DROP CONSTRAINT IF EXISTS stok_opname_angka_chk;
ALTER TABLE public.stok_opname
  ADD CONSTRAINT stok_opname_angka_chk CHECK (
    stok_awal >= 0
    AND qty_masuk >= 0
    AND qty_packed >= 0
    AND qty_batal >= 0
    AND qty_retur >= 0
    AND qty_batal <= qty_packed
    AND (stok_fisik IS NULL OR stok_fisik >= 0)
  );

DROP TRIGGER IF EXISTS stok_opname_bersih_putusan_trg ON public.stok_opname;
CREATE TRIGGER stok_opname_bersih_putusan_trg
  BEFORE UPDATE OF stok_fisik, qty_packed, stok_awal, qty_masuk, qty_batal, qty_retur
  ON public.stok_opname
  FOR EACH ROW
  EXECUTE PROCEDURE public.stok_opname_bersih_putusan();

CREATE OR REPLACE FUNCTION public.barang_masuk_geser_stok(p_id_barang text, p_delta numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
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
  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang
    SET stok = GREATEST(0, COALESCE(stok, 0) + v_delta)
    WHERE id_barang = p_id_barang;
    RETURN;
  END IF;

  SELECT b.tanggal INTO v_tgl FROM public.setoran_buku b WHERE b.id = v_buku;
  SELECT b.nama_barang INTO v_nama FROM public.barang b WHERE b.id_barang = p_id_barang;
  IF v_nama IS NULL THEN
    RAISE EXCEPTION 'SKU % tidak ada di katalog.', p_id_barang;
  END IF;

  INSERT INTO public.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed, qty_masuk
  )
  VALUES (v_buku, v_tgl, p_id_barang, v_nama, 0, 0, GREATEST(0, v_delta))
  ON CONFLICT (id_setoran_buku, id_barang) DO UPDATE SET
    qty_masuk = GREATEST(0, public.stok_opname.qty_masuk + v_delta),
    stok_fisik = CASE
      WHEN public.stok_opname.stok_fisik IS NULL THEN NULL
      ELSE GREATEST(0, public.stok_opname.stok_fisik + v_delta)
    END;
END;
$$;

-- Batal nota / sisa tebus → qty_batal. qty_packed tetap.
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
DECLARE
  v_buku bigint;
  v_qty numeric(14, 4);
  v_packed numeric(14, 4);
  v_batal numeric(14, 4);
  v_sisa numeric(14, 4);
BEGIN
  v_qty := round(GREATEST(COALESCE(p_qty, 0), 0), 4);
  IF v_qty = 0 OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RETURN;
  END IF;

  v_buku := public.setoran_buku_terbuka();
  IF v_buku IS NULL THEN
    PERFORM set_config('obos.boleh_tulis_stok', 'on', true);
    UPDATE public.barang
    SET stok = COALESCE(stok, 0) + v_qty
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

  v_sisa := GREATEST(COALESCE(v_packed, 0) - COALESCE(v_batal, 0), 0);
  IF v_qty > v_sisa THEN
    v_qty := v_sisa;
  END IF;
  IF v_qty = 0 THEN
    RETURN;
  END IF;

  UPDATE public.stok_opname
  SET qty_batal = qty_batal + v_qty
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
END;
$$;

CREATE OR REPLACE FUNCTION public.stok_catat_retur(
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

  UPDATE public.stok_opname
  SET qty_retur = GREATEST(0, qty_retur + v_qty)
  WHERE id_setoran_buku = v_buku
    AND id_barang = p_id_barang;
END;
$$;

-- Batalkan klaim retur: kurangi qty_retur (bukan mengembalikan qty_packed).
CREATE OR REPLACE FUNCTION public.stok_balik_dari_packing(
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
  PERFORM public.stok_catat_retur(p_id_barang, -GREATEST(COALESCE(p_qty, 0), 0));
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
  IF EXISTS (
    SELECT 1 FROM public.setoran_pengirim s
    WHERE s.rute_pengirim = v_rute
      AND s.id_setoran_buku = v_buku
  ) THEN
    RAISE EXCEPTION 'Setoran sudah dicatat. Retur tidak bisa diubah.';
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
    IF rec.baru <> rec.lama THEN
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

REVOKE ALL ON FUNCTION public.stok_catat_retur(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stok_catat_retur(text, numeric)
  TO postgres, service_role;

NOTIFY pgrst, 'reload schema';
