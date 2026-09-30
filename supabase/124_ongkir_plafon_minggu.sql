-- Plafon ongkir aktual Senin–Sabtu = gaji_setelan.ongkir_semua.
-- Dicek saat admin simpan ongkir barang masuk. Baris lama tidak diubah.
-- Angka lama supplier+buku boleh disimpan ulang meski minggu sudah penuh.
-- Tidak menyentuh gudang/pengirim/salesman.
-- Jalankan SETELAH 116 dan 022. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_ongkir_plafon_minggu()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT GREATEST(COALESCE(
    (SELECT g.ongkir_semua FROM public.gaji_setelan g WHERE g.id = 1),
    2000000
  ), 0);
$$;

CREATE OR REPLACE FUNCTION public.admin_ongkir_jumlah_minggu(p_senin date, p_sabtu date)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT coalesce(sum(o.jumlah::bigint), 0)
  FROM public.ongkir o
  LEFT JOIN public.setoran_buku b ON b.id = o.id_setoran_buku
  WHERE p_senin IS NOT NULL
    AND p_sabtu IS NOT NULL
    AND (
      (o.id_setoran_buku IS NOT NULL AND b.tanggal >= p_senin AND b.tanggal <= p_sabtu)
      OR (o.id_setoran_buku IS NULL AND o.tanggal >= p_senin AND o.tanggal <= p_sabtu)
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_ongkir_simpan(p_id_supplier integer, p_jumlah integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_jml integer;
  v_lama integer;
  v_senin date;
  v_sabtu date;
  v_plafon bigint;
  v_minggu bigint;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menyimpan ongkir.';
  END IF;
  IF COALESCE(p_id_supplier, 0) < 1 THEN
    RAISE EXCEPTION 'Pilih supplier.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.supplier s WHERE s.id = p_id_supplier AND s.aktif) THEN
    RAISE EXCEPTION 'Supplier tidak aktif.';
  END IF;
  v_jml := GREATEST(COALESCE(p_jumlah, 0), 0);
  SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();

  IF v_jml > 0 AND v_tgl IS NOT NULL THEN
    v_senin := v_tgl - ((EXTRACT(ISODOW FROM v_tgl)::integer) - 1);
    v_sabtu := v_senin + 5;
    v_plafon := public.admin_ongkir_plafon_minggu();
    SELECT o.jumlah INTO v_lama
    FROM public.ongkir o
    WHERE o.id_supplier = p_id_supplier
      AND (
        (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
        OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl)
      );
    v_minggu := public.admin_ongkir_jumlah_minggu(v_senin, v_sabtu)
      - COALESCE(v_lama, 0)::bigint
      + v_jml::bigint;
    IF v_minggu > v_plafon AND v_jml IS DISTINCT FROM v_lama THEN
      RAISE EXCEPTION
        'Ongkir minggu ini maksimal %. Jumlah minggu jadi %.',
        v_plafon,
        v_minggu;
    END IF;
  END IF;

  IF v_jml = 0 THEN
    DELETE FROM public.ongkir o
    WHERE o.id_supplier = p_id_supplier
      AND (
        (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
        OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl)
      );
    RETURN;
  END IF;
  IF v_buku IS NOT NULL THEN
    INSERT INTO public.ongkir (tanggal, id_supplier, jumlah, id_setoran_buku)
    VALUES (v_tgl, p_id_supplier, v_jml, v_buku)
    ON CONFLICT (id_setoran_buku, id_supplier) WHERE id_setoran_buku IS NOT NULL
    DO UPDATE SET jumlah = EXCLUDED.jumlah;
  ELSE
    INSERT INTO public.ongkir (tanggal, id_supplier, jumlah, id_setoran_buku)
    VALUES (v_tgl, p_id_supplier, v_jml, NULL)
    ON CONFLICT (tanggal, id_supplier) WHERE id_setoran_buku IS NULL
    DO UPDATE SET jumlah = EXCLUDED.jumlah;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_ongkir_plafon_minggu() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_ongkir_plafon_minggu() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_ongkir_plafon_minggu()
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_ongkir_jumlah_minggu(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_ongkir_jumlah_minggu(date, date) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_ongkir_jumlah_minggu(date, date)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_ongkir_simpan(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_ongkir_simpan(integer, integer)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
