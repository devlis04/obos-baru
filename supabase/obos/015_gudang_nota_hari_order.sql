-- Gudang daftar nota = hari order Jakarta (seperti sales / public 098).
-- Batal sales (belum packing) disaring di kartu gudang saat ulang 003.
-- Jangan 001. Jalankan SETELAH 014. Boleh diulang. Lalu 016, lalu ulang 003.

CREATE OR REPLACE FUNCTION obos.nota_ikut_gudang(
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
    AND obos.hari_jakarta(p_waktu_order) = p_tgl;
$$;
