-- Pengirim beda dengan packing gudang:
--   masih dikirim (belum actual) tetap tampil di hari berikutnya selama buku hidup.
--   terkirim/batal kemarin tidak ikut tanggal besok.
-- Sisa kiriman buku lalu (cap beda, dikirim, belum actual) tetap di buku baru.
-- Jalankan SETELAH 084 (dan 120). Boleh diulang.

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
      AND p_id_setoran_buku = p_id_buku
      AND p_status = 'dikirim'
      AND p_waktu_actual IS NULL
    )
    OR (
      p_id_buku IS NOT NULL
      AND p_id_setoran_buku = p_id_buku
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    )
    OR (
      p_tgl IS NOT NULL
      AND p_waktu_order IS NOT NULL
      AND (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      AND p_id_setoran_buku IS NULL
      AND p_status = 'dikirim'
      AND (p_id_buku IS NULL OR coalesce(p_hidup, false))
    )
    OR (
      p_id_buku IS NULL
      AND p_id_setoran_buku IS NULL
      AND p_status IN ('terkirim', 'batal')
      AND p_waktu_actual IS NOT NULL
      AND p_tanggal_lihat IS NOT NULL
      AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tanggal_lihat
    )
    OR (
      coalesce(p_hidup, false)
      AND p_id_buku IS NOT NULL
      AND p_id_setoran_buku IS NOT NULL
      AND p_id_setoran_buku <> p_id_buku
      AND p_status = 'dikirim'
      AND p_waktu_actual IS NULL
    );
$$;

REVOKE ALL ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pengirim_nota_ikut_buku(bigint, date, boolean, bigint, text, timestamptz, timestamptz, date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
