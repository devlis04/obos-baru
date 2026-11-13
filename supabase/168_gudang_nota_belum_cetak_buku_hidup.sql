-- Nota belum cetak (packed kosong, bukan batal) ikut layar buku hidup,
-- meski tanggal ketik sudah lewat (extra terlewat 10 Nov tampil 12 Nov).
-- Packing pertama ke buku terbuka boleh meski ketik < tanggal buku.
-- Order hari ini tetap tidak boleh nempel buku kemarin yang belum tutup (147).
-- Jalankan di SQL Editor. Boleh diulang.

CREATE OR REPLACE FUNCTION public.gudang_nota_ikut_buku(
  p_lihat date,
  p_id_buku_label bigint,
  p_layar_buku_hidup boolean,
  p_id_buku_hidup bigint,
  p_id_setoran_buku bigint,
  p_waktu_order timestamptz,
  p_waktu_packed timestamptz,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_lihat IS NOT NULL
    AND p_waktu_order IS NOT NULL
    AND (
      (
        p_waktu_packed IS NULL
        AND coalesce(p_status, '') IS DISTINCT FROM 'batal'
        AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_lihat
      )
      OR (
        coalesce(p_layar_buku_hidup, false)
        AND p_waktu_packed IS NULL
        AND coalesce(p_status, '') IS DISTINCT FROM 'batal'
        AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date < p_lihat
      )
      OR (
        coalesce(p_layar_buku_hidup, false)
        AND p_id_buku_hidup IS NOT NULL
        AND p_id_setoran_buku = p_id_buku_hidup
        AND p_waktu_packed IS NOT NULL
        AND p_waktu_actual IS NULL
        AND coalesce(p_status, '') = 'dikirim'
      )
      OR (
        coalesce(p_layar_buku_hidup, false)
        AND p_id_buku_hidup IS NOT NULL
        AND p_id_setoran_buku IS NOT NULL
        AND p_id_setoran_buku <> p_id_buku_hidup
        AND p_waktu_packed IS NOT NULL
        AND p_waktu_actual IS NULL
        AND coalesce(p_status, '') = 'dikirim'
      )
      OR (
        p_id_buku_label IS NOT NULL
        AND p_id_setoran_buku = p_id_buku_label
        AND p_waktu_packed IS NOT NULL
        AND (
          p_waktu_actual IS NOT NULL
          OR coalesce(p_status, '') IN ('terkirim', 'batal')
        )
      )
    );
$$;

COMMENT ON FUNCTION public.gudang_nota_ikut_buku(date, bigint, boolean, bigint, bigint, timestamptz, timestamptz, text, timestamptz) IS
  'Layar T: belum cetak hari T, plus belum cetak kemarin di buku hidup; dikirim di label hidup; arsip actual di hari label.';

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
  IF v_order IS NOT DISTINCT FROM v_tgl THEN
    RETURN NEW;
  END IF;

  -- Siklus Sabtu→Senin: nota Minggu boleh packing di buku Sabtu yang belum tutup.
  IF NOT COALESCE(v_tutup, false)
     AND EXTRACT(ISODOW FROM v_order)::int = 7
     AND EXTRACT(ISODOW FROM v_tgl)::int = 6
     AND v_order = v_tgl + 1 THEN
    RETURN NEW;
  END IF;

  -- Extra/nota terlewat: packing pertama ke buku hidup, ketik sudah lewat.
  IF NOT COALESCE(v_tutup, false)
     AND v_order < v_tgl
     AND (
       TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND OLD.id_setoran_buku IS NULL)
     ) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION
    'Nota ketik % belum bisa packing di buku %. Tutup buku itu dulu.',
    to_char(v_order, 'DD/MM'),
    to_char(v_tgl, 'DD/MM');
END;
$$;

NOTIFY pgrst, 'reload schema';
