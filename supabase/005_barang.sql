-- Master barang. Jalankan SETELAH 003_pelanggan.sql. Skema public.

CREATE TABLE IF NOT EXISTS public.barang (
  id_barang text PRIMARY KEY,
  id_grup text,
  nama_barang text NOT NULL,
  kategori text,
  stok numeric(14, 4) NOT NULL DEFAULT 0,
  harga_beli integer NOT NULL DEFAULT 0,
  harga_jual integer NOT NULL DEFAULT 0,
  min_strat_1 integer NOT NULL DEFAULT 0,
  jual_strat_1 integer NOT NULL DEFAULT 0,
  min_strat_2 integer NOT NULL DEFAULT 0,
  jual_strat_2 integer NOT NULL DEFAULT 0,
  min_strat_3 integer NOT NULL DEFAULT 0,
  jual_strat_3 integer NOT NULL DEFAULT 0,
  min_strat_4 integer NOT NULL DEFAULT 0,
  jual_strat_4 integer NOT NULL DEFAULT 0,
  min_strat_5 integer NOT NULL DEFAULT 0,
  jual_strat_5 integer NOT NULL DEFAULT 0,
  CONSTRAINT barang_id_chk CHECK (btrim(id_barang) <> ''),
  CONSTRAINT barang_nama_chk CHECK (btrim(nama_barang) <> ''),
  CONSTRAINT barang_stok_chk CHECK (stok >= 0),
  CONSTRAINT barang_harga_chk CHECK (harga_beli >= 0 AND harga_jual >= 0)
);

CREATE INDEX IF NOT EXISTS barang_grup_idx ON public.barang (id_grup);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.barang
  TO postgres, service_role;
REVOKE ALL ON TABLE public.barang FROM anon;
