-- Konfirmasi fisik ≠ tutup buku.
-- Pulang terakhir: fisik NULL → barang.stok = stok_hitung.
-- Konfirmasi: fisik IS NOT NULL (termasuk 0) → barang.stok = stok_fisik, buku tetap terbuka.
-- Tutup buku: kunci buku; sisa SKU tanpa fisik memakai stok_hitung.
-- Jalankan SETELAH 016. Boleh diulang.

CREATE OR REPLACE FUNCTION public.serahkan_stok_jika_gudang_kosong()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.absensi a
    WHERE a.waktu_keluar IS NULL
      AND a.peran IN ('gudang', 'admin')
  ) THEN
    RETURN;
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_konfirmasi_opname(p_id_setoran_buku bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer := 0;
  v_tutup boolean;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh konfirmasi opname.';
  END IF;
  IF p_id_setoran_buku IS NULL THEN
    RAISE EXCEPTION 'Buku kosong.';
  END IF;

  SELECT b.ditutup INTO v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id_setoran_buku;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Buku tidak ada.';
  END IF;
  IF COALESCE(v_tutup, false) THEN
    RAISE EXCEPTION 'Buku sudah ditutup.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);
  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, so.stok_fisik)
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = p_id_setoran_buku
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n < 1 THEN
    RAISE EXCEPTION 'Belum ada stok fisik yang bisa dikonfirmasi.';
  END IF;
  RETURN v_n;
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
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menutup buku.';
  END IF;

  PERFORM pg_advisory_xact_lock(88221019);

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  PERFORM set_config('obos.boleh_tulis_stok', 'on', true);

  UPDATE public.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM public.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  UPDATE public.setoran_buku
  SET
    ditutup = true,
    waktu_tutup = clock_timestamp()
  WHERE id = v_id
    AND NOT ditutup;

  RETURN v_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
