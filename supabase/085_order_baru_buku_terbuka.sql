-- Sisa pending 21/09 di buku 22/09 membuat MIN(waktu_order)=21/09.
-- Trigger lalu menolak order/packing 22/09: "Buku terbuka untuk orderan 21-09".
-- Tanggal buku terbuka = hari order BARU, bukan sisa foto buku tutup.
-- Jalankan SETELAH 083/084. Pendek. Boleh diulang.

CREATE OR REPLACE FUNCTION public.setoran_tanggal_order_sales(p_id_buku bigint DEFAULT NULL)
RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_today date;
  v_tgl date;
  v_buku date;
BEGIN
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;

  IF p_id_buku IS NOT NULL THEN
    SELECT MIN((t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date)
    INTO v_tgl
    FROM public.transaksi t
    WHERE t.id_setoran_buku = p_id_buku
      AND t.waktu_order IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.setoran_buku_pending_foto f
        JOIN public.setoran_buku b ON b.id = f.id_setoran_buku
        WHERE f.id_transaksi = t.id_transaksi
          AND b.ditutup
      );
    IF v_tgl IS NOT NULL THEN
      RETURN v_tgl;
    END IF;

    SELECT b.tanggal INTO v_buku
    FROM public.setoran_buku b
    WHERE b.id = p_id_buku;
    IF v_buku IS NOT NULL THEN
      RETURN v_buku;
    END IF;
  END IF;

  SELECT MIN((t.waktu_order AT TIME ZONE 'Asia/Jakarta')::date)
  INTO v_tgl
  FROM public.transaksi t
  WHERE t.id_setoran_buku IS NULL
    AND t.waktu_order IS NOT NULL
    AND NOT (t.status = 'batal' AND t.waktu_packed IS NULL);
  IF v_tgl IS NOT NULL THEN
    RETURN v_tgl;
  END IF;

  RETURN v_today;
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
  WHERE btrim(b.id_barang) <> '';

  PERFORM public.setoran_pending_foto_pindah(v_id);
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

SELECT public.setoran_buka_jika_perlu();

REVOKE ALL ON FUNCTION public.setoran_tanggal_order_sales(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_tanggal_order_sales(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buka_jika_perlu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buka_jika_perlu()
  TO authenticated, postgres, service_role;
