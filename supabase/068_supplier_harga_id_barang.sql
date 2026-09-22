-- supplier_harga kolomnya id_barang, bukan kode_barang.
-- Jalankan SETELAH 059. Boleh diulang.

CREATE OR REPLACE FUNCTION public.barang_modal_dari_utama(p_id_barang text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_harga integer;
BEGIN
  v_id := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  SELECT h.harga_beli INTO v_harga
  FROM public.barang b
  JOIN public.supplier_harga h
    ON h.id_supplier = b.id_supplier_utama
   AND lower(h.id_barang) = lower(b.id_barang)
  WHERE lower(b.id_barang) = lower(v_id);
  IF COALESCE(v_harga, 0) > 0 THEN
    PERFORM public.barang_ikut_modal(v_id, v_harga);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_pemasok_lihat(p_id_barang text)
RETURNS TABLE (
  id_supplier integer,
  nama_supplier text,
  harga_beli integer,
  utama boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_utama integer;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RETURN;
  END IF;
  v_id := nullif(btrim(COALESCE(p_id_barang, '')), '');
  IF v_id IS NULL THEN
    RETURN;
  END IF;
  SELECT b.id_supplier_utama INTO v_utama
  FROM public.barang b
  WHERE lower(b.id_barang) = lower(v_id);

  RETURN QUERY
  SELECT
    h.id_supplier,
    COALESCE(NULLIF(btrim(s.nama), ''), 'Supplier'),
    h.harga_beli,
    (v_utama IS NOT NULL AND h.id_supplier = v_utama)
  FROM public.supplier_harga h
  JOIN public.supplier s ON s.id = h.id_supplier
  WHERE lower(h.id_barang) = lower(v_id)
    AND s.aktif
  ORDER BY (v_utama IS NOT NULL AND h.id_supplier = v_utama) DESC,
    lower(s.nama),
    h.id_supplier;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_simpan(p_barang jsonb)
RETURNS TABLE (
  id_barang text,
  id_grup text,
  nama_barang text,
  kategori text,
  stok numeric,
  sisa_buku numeric,
  harga_beli integer,
  harga_jual integer,
  min_strat_1 integer,
  jual_strat_1 integer,
  min_strat_2 integer,
  jual_strat_2 integer,
  min_strat_3 integer,
  jual_strat_3 integer,
  min_strat_4 integer,
  jual_strat_4 integer,
  min_strat_5 integer,
  jual_strat_5 integer,
  pengurang_strata integer,
  aktif boolean,
  id_supplier_utama integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_nama text;
  v_ada boolean;
  v_beli integer;
  v_jual integer;
  v_pengurang integer;
  v_min1 integer;
  v_min2 integer;
  v_min3 integer;
  v_min4 integer;
  v_min5 integer;
  v_jual1 integer;
  v_jual2 integer;
  v_jual3 integer;
  v_jual4 integer;
  v_jual5 integer;
  v_utama integer;
  v_modal integer;
  v_buku bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_barang IS NULL OR jsonb_typeof(p_barang) <> 'object' THEN
    RAISE EXCEPTION 'Data barang kosong.';
  END IF;

  v_id := btrim(COALESCE(p_barang->>'id_barang', ''));
  v_nama := btrim(COALESCE(p_barang->>'nama_barang', ''));
  IF v_id = '' THEN
    RAISE EXCEPTION 'Id barang wajib diisi.';
  END IF;
  IF v_nama = '' THEN
    RAISE EXCEPTION 'Nama barang wajib diisi.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.barang b WHERE lower(b.id_barang) = lower(v_id)
  ) INTO v_ada;
  IF NOT v_ada THEN
    RAISE EXCEPTION 'SKU baru hanya dari Barang masuk.';
  END IF;

  IF p_barang->'harga_beli' IS NULL OR p_barang->>'harga_beli' = '' THEN
    RAISE EXCEPTION 'Harga beli wajib diisi.';
  END IF;
  IF p_barang->'harga_jual' IS NULL OR p_barang->>'harga_jual' = '' THEN
    RAISE EXCEPTION 'Harga jual wajib diisi.';
  END IF;
  v_beli := COALESCE((p_barang->>'harga_beli')::integer, 0);
  v_jual := COALESCE((p_barang->>'harga_jual')::integer, 0);
  v_pengurang := GREATEST(0, COALESCE((p_barang->>'pengurang_strata')::integer, 0));

  SELECT b.id_supplier_utama, h.harga_beli
  INTO v_utama, v_modal
  FROM public.barang b
  LEFT JOIN public.supplier_harga h
    ON h.id_supplier = b.id_supplier_utama
   AND lower(h.id_barang) = lower(b.id_barang)
  WHERE lower(b.id_barang) = lower(v_id);

  IF v_utama IS NOT NULL AND COALESCE(v_modal, 0) > 0 THEN
    SELECT b.harga_beli INTO v_beli
    FROM public.barang b
    WHERE lower(b.id_barang) = lower(v_id);
    v_beli := COALESCE(v_beli, v_modal);
  END IF;

  IF v_beli < 0 OR v_jual < 0 THEN
    RAISE EXCEPTION 'Harga tidak boleh minus.';
  END IF;
  IF v_jual <= v_beli THEN
    RAISE EXCEPTION 'Harga jual harus lebih besar dari harga beli.';
  END IF;

  v_min1 := GREATEST(0, COALESCE((p_barang->>'min_strat_1')::integer, 0));
  v_min2 := GREATEST(0, COALESCE((p_barang->>'min_strat_2')::integer, 0));
  v_min3 := GREATEST(0, COALESCE((p_barang->>'min_strat_3')::integer, 0));
  v_min4 := GREATEST(0, COALESCE((p_barang->>'min_strat_4')::integer, 0));
  v_min5 := GREATEST(0, COALESCE((p_barang->>'min_strat_5')::integer, 0));

  IF (v_min1 > 0 OR v_min2 > 0 OR v_min3 > 0 OR v_min4 > 0 OR v_min5 > 0)
     AND v_pengurang <= 0 THEN
    RAISE EXCEPTION 'Nilai pengurang wajib diisi jika strata dipakai.';
  END IF;

  v_jual1 := CASE WHEN v_min1 > 0 THEN v_jual - (v_pengurang * 1) ELSE 0 END;
  v_jual2 := CASE WHEN v_min2 > 0 THEN v_jual - (v_pengurang * 2) ELSE 0 END;
  v_jual3 := CASE WHEN v_min3 > 0 THEN v_jual - (v_pengurang * 3) ELSE 0 END;
  v_jual4 := CASE WHEN v_min4 > 0 THEN v_jual - (v_pengurang * 4) ELSE 0 END;
  v_jual5 := CASE WHEN v_min5 > 0 THEN v_jual - (v_pengurang * 5) ELSE 0 END;

  IF (v_min1 > 0 AND v_jual1 <= v_beli)
     OR (v_min2 > 0 AND v_jual2 <= v_beli)
     OR (v_min3 > 0 AND v_jual3 <= v_beli)
     OR (v_min4 > 0 AND v_jual4 <= v_beli)
     OR (v_min5 > 0 AND v_jual5 <= v_beli) THEN
    RAISE EXCEPTION 'Harga jual strata harus lebih besar dari harga beli.';
  END IF;

  UPDATE public.barang b
  SET
    id_grup = nullif(btrim(COALESCE(p_barang->>'id_grup', '')), ''),
    nama_barang = v_nama,
    kategori = nullif(btrim(COALESCE(p_barang->>'kategori', '')), ''),
    harga_beli = v_beli,
    harga_jual = v_jual,
    pengurang_strata = v_pengurang,
    min_strat_1 = v_min1,
    jual_strat_1 = GREATEST(0, v_jual1),
    min_strat_2 = v_min2,
    jual_strat_2 = GREATEST(0, v_jual2),
    min_strat_3 = v_min3,
    jual_strat_3 = GREATEST(0, v_jual3),
    min_strat_4 = v_min4,
    jual_strat_4 = GREATEST(0, v_jual4),
    min_strat_5 = v_min5,
    jual_strat_5 = GREATEST(0, v_jual5),
    aktif = COALESCE((p_barang->>'aktif')::boolean, true)
  WHERE lower(b.id_barang) = lower(v_id);

  v_buku := public.setoran_buku_terbuka();
  RETURN QUERY
  SELECT
    b.id_barang,
    b.id_grup,
    b.nama_barang,
    b.kategori,
    b.stok,
    COALESCE(so.stok_hitung, b.stok),
    b.harga_beli,
    b.harga_jual,
    b.min_strat_1,
    b.jual_strat_1,
    b.min_strat_2,
    b.jual_strat_2,
    b.min_strat_3,
    b.jual_strat_3,
    b.min_strat_4,
    b.jual_strat_4,
    b.min_strat_5,
    b.jual_strat_5,
    b.pengurang_strata,
    b.aktif,
    b.id_supplier_utama
  FROM public.barang b
  LEFT JOIN public.stok_opname so
    ON so.id_setoran_buku = v_buku
   AND so.id_barang = b.id_barang
  WHERE lower(b.id_barang) = lower(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_barang_csv(p_baris jsonb)
RETURNS TABLE (
  baris integer,
  id_barang text,
  aksi text,
  ok boolean,
  pesan text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_e jsonb;
  v_i integer := 0;
  v_id text;
  v_nama text;
  v_satuan text;
  v_rincian text;
  v_full text;
  v_hapus boolean;
  v_ada boolean;
  v_pakai boolean;
  v_utama integer;
  v_aktif boolean;
  v_teks text;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Data CSV kosong.';
  END IF;
  IF jsonb_array_length(p_baris) > 3000 THEN
    RAISE EXCEPTION 'Maksimal 3000 baris per unggah.';
  END IF;

  FOR v_e IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_i := v_i + 1;
    baris := v_i;
    id_barang := btrim(COALESCE(v_e->>'id_barang', ''));
    aksi := '';
    ok := false;
    pesan := '';
    BEGIN
      v_id := id_barang;
      IF v_id = '' THEN
        RAISE EXCEPTION 'Id barang wajib diisi.';
      END IF;
      v_hapus := COALESCE((v_e->>'hapus')::boolean, false);
      SELECT EXISTS (
        SELECT 1 FROM public.barang b WHERE lower(b.id_barang) = lower(v_id)
      ) INTO v_ada;

      IF NOT v_ada THEN
        RAISE EXCEPTION 'SKU baru hanya dari Barang masuk.';
      END IF;

      IF v_hapus THEN
        SELECT EXISTS (
          SELECT 1 FROM public.transaksi_items i WHERE lower(i.id_barang) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.stok_opname so WHERE lower(so.id_barang) = lower(v_id)
        ) OR EXISTS (
          SELECT 1 FROM public.barang_masuk m WHERE lower(m.id_barang) = lower(v_id)
        ) INTO v_pakai;
        IF v_pakai THEN
          UPDATE public.barang b
          SET aktif = false
          WHERE lower(b.id_barang) = lower(v_id);
          aksi := 'nonaktif';
          ok := true;
          pesan := 'Sudah dipakai nota/buku. Tidak dihapus, dinonaktifkan.';
        ELSE
          DELETE FROM public.supplier_harga h
          WHERE lower(h.id_barang) = lower(v_id);
          DELETE FROM public.barang b WHERE lower(b.id_barang) = lower(v_id);
          aksi := 'hapus';
          ok := true;
          pesan := 'Dihapus.';
        END IF;
      ELSE
        v_nama := btrim(COALESCE(v_e->>'nama', v_e->>'nama_barang', ''));
        v_satuan := btrim(COALESCE(v_e->>'satuan', ''));
        v_rincian := btrim(COALESCE(v_e->>'rincian', ''));
        IF v_nama = '' THEN
          RAISE EXCEPTION 'Nama barang wajib diisi.';
        END IF;
        IF v_satuan = '' THEN
          RAISE EXCEPTION 'Satuan wajib diisi.';
        END IF;
        v_full := v_nama || ' /' || v_satuan;
        IF v_rincian <> '' THEN
          v_full := v_full || '/' || v_rincian;
        END IF;
        SELECT b.aktif INTO v_aktif
        FROM public.barang b
        WHERE lower(b.id_barang) = lower(v_id);
        IF v_e ? 'aktif' AND v_e->>'aktif' IS NOT NULL AND btrim(v_e->>'aktif') <> '' THEN
          v_aktif := (v_e->>'aktif')::boolean;
        END IF;
        PERFORM * FROM public.admin_barang_simpan(
          jsonb_build_object(
            'id_barang', v_id,
            'id_grup', COALESCE(v_e->>'id_grup', ''),
            'nama_barang', v_full,
            'kategori', COALESCE(v_e->>'kategori', ''),
            'harga_beli', COALESCE((v_e->>'harga_beli')::integer, 0),
            'harga_jual', COALESCE((v_e->>'harga_jual')::integer, 0),
            'pengurang_strata', COALESCE((v_e->>'pengurang_strata')::integer, 0),
            'min_strat_1', COALESCE((v_e->>'min_strat_1')::integer, 0),
            'min_strat_2', COALESCE((v_e->>'min_strat_2')::integer, 0),
            'min_strat_3', COALESCE((v_e->>'min_strat_3')::integer, 0),
            'min_strat_4', COALESCE((v_e->>'min_strat_4')::integer, 0),
            'min_strat_5', COALESCE((v_e->>'min_strat_5')::integer, 0),
            'aktif', COALESCE(v_aktif, true)
          )
        );
        v_teks := btrim(COALESCE(v_e->>'id_supplier_utama', ''));
        IF v_teks <> '' THEN
          v_utama := v_teks::integer;
          IF NOT public.admin_barang_utama_set(v_id, v_utama) THEN
            RAISE EXCEPTION 'Pemasok utama tidak valid.';
          END IF;
        END IF;
        aksi := 'ubah';
        ok := true;
        pesan := 'Diubah.';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      ok := false;
      IF aksi = '' THEN
        aksi := CASE WHEN COALESCE((v_e->>'hapus')::boolean, false) THEN 'hapus' ELSE 'simpan' END;
      END IF;
      pesan := SQLERRM;
    END;
    RETURN NEXT;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.barang_modal_dari_utama(text)
  TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_pemasok_lihat(text)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_simpan(jsonb)
  TO authenticated, postgres, service_role;
GRANT EXECUTE ON FUNCTION public.admin_barang_csv(jsonb)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
