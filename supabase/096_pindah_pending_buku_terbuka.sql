-- Pending buku tutup (22/09) masih cap lama, tidak jadi kiriman buku terbuka (23/09).
-- 094 hanya foto; pindah hanya saat INSERT buku baru. Buku 23 sudah ada → 13 nota nyangkut.
-- Jalankan SETELAH 095. SQL Editor → Run. Boleh di-Run ulang.
-- Tidak menutup buku, tidak mengubah packing.

CREATE TABLE IF NOT EXISTS public.setoran_buku_pending_foto (
  id_setoran_buku bigint NOT NULL
    REFERENCES public.setoran_buku (id) ON DELETE CASCADE,
  id_transaksi text NOT NULL,
  PRIMARY KEY (id_setoran_buku, id_transaksi)
);

CREATE INDEX IF NOT EXISTS setoran_buku_pending_foto_nota_idx
  ON public.setoran_buku_pending_foto (id_transaksi);

REVOKE ALL ON TABLE public.setoran_buku_pending_foto FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.setoran_buku_pending_foto
  TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.setoran_pending_foto_catat(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  INSERT INTO public.setoran_buku_pending_foto (id_setoran_buku, id_transaksi)
  SELECT p_id, t.id_transaksi
  FROM public.transaksi t
  WHERE t.id_setoran_buku = p_id
    AND t.status = 'dikirim'
    AND COALESCE(t.pending, false)
  ON CONFLICT DO NOTHING;
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

  SELECT b.tanggal INTO v_tgl
  FROM public.setoran_buku b
  WHERE b.id = NEW.id_setoran_buku;
  IF v_tgl IS NULL OR NEW.waktu_order IS NULL THEN
    RETURN NEW;
  END IF;

  v_order := (NEW.waktu_order AT TIME ZONE 'Asia/Jakarta')::date;
  IF v_order IS DISTINCT FROM v_tgl THEN
    RAISE EXCEPTION
      'Nota ini orderan %. Buku terbuka untuk orderan %. Tutup buku dulu.',
      to_char(v_order, 'FMDD-MM-YYYY'),
      to_char(v_tgl, 'FMDD-MM-YYYY');
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_pending_foto_pindah(p_baru bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF p_baru IS NULL THEN
    RETURN;
  END IF;
  PERFORM set_config('obos.boleh_pindah_pending', 'on', true);
  UPDATE public.transaksi t
  SET
    id_setoran_buku = p_baru,
    pending = false
  FROM public.setoran_buku_pending_foto f
  JOIN public.setoran_buku b ON b.id = f.id_setoran_buku
  WHERE b.ditutup
    AND f.id_transaksi = t.id_transaksi
    AND t.status = 'dikirim'
    AND COALESCE(t.pending, false)
    AND t.id_setoran_buku IS DISTINCT FROM p_baru;
END;
$$;

CREATE OR REPLACE FUNCTION public.setoran_buka_jika_perlu()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_lama date;
  v_today date;
BEGIN
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_id := public.setoran_buku_terbuka();
  IF v_id IS NOT NULL THEN
    v_tgl := public.setoran_tanggal_order_sales(v_id);
    SELECT b.tanggal INTO v_lama
    FROM public.setoran_buku b
    WHERE b.id = v_id;
    IF EXISTS (SELECT 1 FROM public.setoran_buku x WHERE x.ditutup) THEN
      v_tgl := GREATEST(COALESCE(v_tgl, v_today), v_today);
    END IF;
    IF v_tgl IS NOT NULL AND v_lama IS DISTINCT FROM v_tgl THEN
      UPDATE public.setoran_buku
      SET tanggal = v_tgl
      WHERE id = v_id;
      UPDATE public.stok_opname
      SET tanggal = v_tgl
      WHERE id_setoran_buku = v_id;
    END IF;
    PERFORM public.setoran_pending_foto_pindah(v_id);
    RETURN v_id;
  END IF;

  v_tgl := public.setoran_tanggal_order_sales(NULL);

  INSERT INTO public.setoran_buku (tanggal, ditutup)
  VALUES (v_tgl, false)
  RETURNING id INTO v_id;

  INSERT INTO public.stok_opname (
    id_setoran_buku, tanggal, id_barang, nama_barang, stok_awal, qty_packed
  )
  SELECT
    v_id,
    v_tgl,
    b.id_barang,
    b.nama_barang,
    GREATEST(COALESCE(b.stok, 0), 0),
    0
  FROM public.barang b
  WHERE btrim(b.id_barang) <> ''
    AND COALESCE(b.aktif, true);

  PERFORM public.setoran_pending_foto_pindah(v_id);
  RETURN v_id;
END;
$$;

DO $$
DECLARE
  v_lama bigint;
  v_baru bigint;
BEGIN
  SELECT b.id INTO v_baru
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;

  FOR v_lama IN
    SELECT b.id
    FROM public.setoran_buku b
    WHERE b.ditutup
    ORDER BY b.id
  LOOP
    PERFORM public.setoran_pending_foto_catat(v_lama);
  END LOOP;

  IF v_baru IS NOT NULL THEN
    PERFORM public.setoran_pending_foto_pindah(v_baru);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.setoran_pending_foto_catat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_pending_foto_catat(bigint)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_pending_foto_pindah(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_pending_foto_pindah(bigint)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buka_jika_perlu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buka_jika_perlu()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
