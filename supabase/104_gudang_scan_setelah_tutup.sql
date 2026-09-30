-- Setelah tutup buku, gudang harus bisa scan masuk dan packing di siklus baru.
-- 1. Kunci malam jangan mengunci buku baru yang belum packing (lewat tengah malam).
-- 2. Nota belum packing di buku tutup dilepas cap-nya.
-- 3. Order/packing hari ini boleh masuk buku terbuka meski tanggal buku berurutan beda.
-- Jalankan SETELAH 102. SQL Editor → Run. Boleh diulang.

CREATE OR REPLACE FUNCTION public.setoran_buku_kunci_malam_baru(p_id bigint)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_tgl date;
  v_tutup boolean;
  v_hari date;
BEGIN
  IF p_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id;
  IF NOT FOUND OR COALESCE(v_tutup, false) THEN
    RETURN false;
  END IF;
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  IF v_tgl >= v_hari THEN
    RETURN false;
  END IF;
  IF v_hari > v_tgl + 1 THEN
    RETURN true;
  END IF;
  IF public.setoran_buku_ada_dikirim(p_id) THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.transaksi t
    WHERE t.id_setoran_buku = p_id
      AND t.waktu_packed IS NOT NULL
  ) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.transaksi_tolak_beda_hari_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_tgl date;
  v_order date;
  v_tutup boolean;
  v_today date;
BEGIN
  IF NEW.id_setoran_buku IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.id_setoran_buku IS NOT DISTINCT FROM NEW.id_setoran_buku THEN
    RETURN NEW;
  END IF;
  IF current_setting('obos.boleh_pindah_pending', true) = 'on' THEN
    RETURN NEW;
  END IF;

  SELECT b.tanggal, b.ditutup INTO v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = NEW.id_setoran_buku;
  IF v_tgl IS NULL OR NEW.waktu_order IS NULL THEN
    RETURN NEW;
  END IF;

  v_order := (NEW.waktu_order AT TIME ZONE 'Asia/Jakarta')::date;
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;

  IF v_order IS NOT DISTINCT FROM v_tgl THEN
    RETURN NEW;
  END IF;

  IF NOT COALESCE(v_tutup, false) THEN
    IF v_order IS NOT DISTINCT FROM v_today THEN
      RETURN NEW;
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.setoran_buku_pending_foto f
      JOIN public.setoran_buku b ON b.id = f.id_setoran_buku
      WHERE f.id_transaksi = NEW.id_transaksi
        AND b.ditutup
    ) THEN
      RETURN NEW;
    END IF;
  END IF;

  RAISE EXCEPTION
    'Nota ini orderan %. Buku terbuka untuk orderan %. Tutup buku dulu.',
    to_char(v_order, 'FMDD-MM-YYYY'),
    to_char(v_tgl, 'FMDD-MM-YYYY');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_tutup_setoran_buku()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_sku text;
  v_n integer;
  v_fisik integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menutup buku.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);
  IF v_n > 0 THEN
    RAISE EXCEPTION
      'Masih ada % nota dikirim. Pengirim selesaikan dulu, lalu tutup buku.',
      v_n;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'pengirim')
    AND a.id_setoran_buku = v_id;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada absensi yang belum pulang. Scan pulang dulu, lalu tutup buku.';
  END IF;

  SELECT count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer
  INTO v_fisik
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id;
  IF COALESCE(v_fisik, 0) <= 0 THEN
    RAISE EXCEPTION 'Opname fisik belum diisi. Gudang isi fisik dulu, lalu tutup buku.';
  END IF;

  SELECT so.id_barang
  INTO v_sku
  FROM public.stok_opname so
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

  UPDATE public.stok_opname so
  SET
    putusan = 'margin_plus',
    nilai_putusan = round(so.selisih * GREATEST(COALESCE(b.harga_beli, 0), 0))::integer,
    harga_beli_putusan = GREATEST(COALESCE(b.harga_beli, 0), 0)::integer,
    qty_selisih_putusan = so.selisih,
    kasbon_email = NULL,
    kasbon_nama = NULL,
    waktu_putusan = clock_timestamp()
  FROM public.barang b
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) > 0;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  PERFORM public.setoran_pending_foto_catat(v_id);

  UPDATE public.setoran_buku
  SET
    ditutup = true,
    waktu_tutup = clock_timestamp()
  WHERE id = v_id
    AND NOT ditutup;

  UPDATE public.transaksi t
  SET id_setoran_buku = NULL
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'diproses'
    AND t.waktu_packed IS NULL;

  RETURN v_id;
END;
$$;

UPDATE public.transaksi t
SET id_setoran_buku = NULL
FROM public.setoran_buku b
WHERE t.id_setoran_buku = b.id
  AND b.ditutup
  AND t.status = 'diproses'
  AND t.waktu_packed IS NULL;

REVOKE ALL ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buku_kunci_malam_baru(bigint)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_tutup_setoran_buku()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
