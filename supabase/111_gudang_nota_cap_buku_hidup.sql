-- Senin (hari kerja berikutnya) memakai buku Sabtu yang masih terbuka.
-- Daftar packing/kartu harus ikut cap buku, bukan hanya tanggal order,
-- supaya sisa kiriman tidak hilang dan packing tidak mengira stok masih utuh.
-- Extra tetap dari hari order. Jalankan SETELAH 110. Boleh diulang.

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
    p_tgl IS NOT NULL
    AND p_waktu_order IS NOT NULL
    AND (
      (p_waktu_order AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
      OR (
        coalesce(p_hidup, false)
        AND p_id_buku IS NOT NULL
        AND p_id_setoran_buku = p_id_buku
      )
    );
$$;

REVOKE ALL ON FUNCTION public.gudang_nota_ikut_buku(bigint, date, boolean, bigint, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gudang_nota_ikut_buku(bigint, date, boolean, bigint, timestamptz)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
