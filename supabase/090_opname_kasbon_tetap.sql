-- Kasbon opname: hapus trigger yang mengosongkan putusan,
-- izinkan admin UPDATE stok_opname / INSERT kasbon,
-- RPC mengembalikan baris tersimpan. Boleh diulang.

DROP TRIGGER IF EXISTS stok_opname_bersih_putusan_trg ON public.stok_opname;

DROP POLICY IF EXISTS stok_opname_update_admin ON public.stok_opname;
CREATE POLICY stok_opname_update_admin
  ON public.stok_opname
  FOR UPDATE
  TO authenticated
  USING (public.admin_sedang_login())
  WITH CHECK (public.admin_sedang_login());

DROP POLICY IF EXISTS kasbon_tulis_admin ON public.kasbon;
CREATE POLICY kasbon_tulis_admin
  ON public.kasbon
  FOR ALL
  TO authenticated
  USING (public.admin_sedang_login())
  WITH CHECK (public.admin_sedang_login());

DROP FUNCTION IF EXISTS public.admin_opname_putusan(bigint, text, text, text);

CREATE OR REPLACE FUNCTION public.admin_opname_putusan(
  p_id_setoran_buku bigint,
  p_id_barang text,
  p_jenis text,
  p_email text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
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
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh memutuskan selisih.';
  END IF;
  IF p_id_setoran_buku IS NULL OR btrim(COALESCE(p_id_barang, '')) = '' THEN
    RAISE EXCEPTION 'Buku atau SKU kosong.';
  END IF;

  v_jenis := lower(btrim(COALESCE(p_jenis, '')));
  IF v_jenis NOT IN ('kasbon', 'beban') THEN
    RAISE EXCEPTION 'Jenis putusan wajib kasbon atau beban.';
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

  SELECT
    so.id_barang,
    so.selisih,
    GREATEST(
      COALESCE(b.harga_beli, 0),
      COALESCE((
        SELECT max(i.harga_beli)
        FROM public.transaksi_items i
        WHERE lower(i.id_barang) = lower(so.id_barang)
      ), 0)
    )::integer
  INTO v_sku, v_selisih, v_harga
  FROM public.stok_opname so
  LEFT JOIN public.barang b ON lower(b.id_barang) = lower(so.id_barang)
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
    FROM public.users u
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

  UPDATE public.stok_opname
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

  DELETE FROM public.kasbon
  WHERE id_setoran_buku = p_id_setoran_buku
    AND lower(id_barang) = lower(v_sku);

  IF v_jenis = 'kasbon' THEN
    INSERT INTO public.kasbon (
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

REVOKE ALL ON FUNCTION public.admin_opname_putusan(bigint, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_opname_putusan(bigint, text, text, text)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
