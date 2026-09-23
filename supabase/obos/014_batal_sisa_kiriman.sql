-- qty_batal boleh > qty_packed (sisa kiriman buku kemarin), sama seperti public 097.
-- Jangan 001 (DROP). Jalankan SETELAH 013. Boleh diulang. Lalu ulang 005.

ALTER TABLE obos.stok_opname
  DROP CONSTRAINT IF EXISTS stok_opname_angka_chk;
ALTER TABLE obos.stok_opname
  ADD CONSTRAINT stok_opname_angka_chk CHECK (
    stok_awal >= 0
    AND qty_masuk >= 0
    AND qty_packed >= 0
    AND qty_batal >= 0
    AND qty_retur >= 0
    AND (stok_fisik IS NULL OR stok_fisik >= 0)
  );
