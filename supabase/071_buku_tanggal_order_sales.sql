-- Tanggal buku terbuka = hari order sales (Jakarta), bukan jam scan masuk.
-- Satu buku = satu hari order. Jalankan SETELAH 070. Boleh diulang.

COMMENT ON COLUMN public.setoran_buku.tanggal IS
  'Hari order sales (Jakarta) yang dilayani buku ini. Bukan jam buku dibuka.';

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
      AND t.waktu_order IS NOT NULL;
    IF v_tgl IS NOT NULL THEN
      RETURN v_tgl;
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

  IF p_id_buku IS NOT NULL THEN
    SELECT b.tanggal INTO v_buku
    FROM public.setoran_buku b
    WHERE b.id = p_id_buku;
    IF v_buku IS NOT NULL THEN
      RETURN v_buku;
    END IF;
  END IF;

  RETURN v_today;
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
BEGIN
  v_id := public.setoran_buku_terbuka();
  IF v_id IS NOT NULL THEN
    v_tgl := public.setoran_tanggal_order_sales(v_id);
    SELECT b.tanggal INTO v_lama
    FROM public.setoran_buku b
    WHERE b.id = v_id;
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

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.gudang_nota_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_waktu_order timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_id_buku IS NOT NULL
    AND p_tgl IS NOT NULL
    AND p_waktu_order IS NOT NULL
    AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
    AND (
      p_id_setoran_buku = p_id_buku
      OR (
        coalesce(p_hidup, false)
        AND p_id_setoran_buku IS NULL
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.pengirim_nota_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_hidup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_order timestamptz,
  p_waktu_actual timestamptz,
  p_tanggal_lihat date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (
      p_id_buku IS NOT NULL
      AND p_tgl IS NOT NULL
      AND p_waktu_order IS NOT NULL
      AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      AND (
        p_id_setoran_buku = p_id_buku
        OR (
          coalesce(p_hidup, false)
          AND p_status = 'dikirim'
          AND p_id_setoran_buku IS NULL
        )
      )
    )
    OR (
      p_id_buku IS NULL
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    );
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

DROP TRIGGER IF EXISTS transaksi_tolak_beda_hari_order ON public.transaksi;
CREATE TRIGGER transaksi_tolak_beda_hari_order
  BEFORE INSERT OR UPDATE OF id_setoran_buku ON public.transaksi
  FOR EACH ROW
  EXECUTE PROCEDURE public.transaksi_tolak_beda_hari_order();

REVOKE ALL ON FUNCTION public.setoran_tanggal_order_sales(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_tanggal_order_sales(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.setoran_buka_jika_perlu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.setoran_buka_jika_perlu()
  TO authenticated, postgres, service_role;

DO $$
DECLARE
  v_id bigint;
BEGIN
  v_id := public.setoran_buku_terbuka();
  IF v_id IS NOT NULL THEN
    PERFORM public.setoran_buka_jika_perlu();
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
