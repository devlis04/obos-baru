-- Stok master boleh pecahan (contoh CSV: 52.25, 0.6667). Qty nota tetap integer.
-- Jalankan SETELAH 005_barang.sql. Aman di-Run ulang.

ALTER TABLE public.barang
  ALTER COLUMN stok TYPE numeric(14, 4)
  USING COALESCE(stok, 0)::numeric(14, 4);

ALTER TABLE public.barang
  ALTER COLUMN stok SET DEFAULT 0,
  ALTER COLUMN stok SET NOT NULL;
