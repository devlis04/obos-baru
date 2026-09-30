-- Patokan gaji (bukan kas). Satu baris. Admin baca/tulis lewat RPC.
-- Jalankan SETELAH 115. Boleh diulang.

CREATE TABLE IF NOT EXISTS public.gaji_setelan (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  bop_mobil bigint NOT NULL DEFAULT 1020000 CHECK (bop_mobil >= 0),
  ongkir_semua bigint NOT NULL DEFAULT 2000000 CHECK (ongkir_semua >= 0),
  sales_net bigint NOT NULL DEFAULT 800000 CHECK (sales_net >= 0),
  sales_visit bigint NOT NULL DEFAULT 200000 CHECK (sales_visit >= 0),
  sales_ec bigint NOT NULL DEFAULT 200000 CHECK (sales_ec >= 0),
  pengirim bigint NOT NULL DEFAULT 800000 CHECK (pengirim >= 0),
  gudang bigint NOT NULL DEFAULT 500000 CHECK (gudang >= 0),
  gudang_slot integer NOT NULL DEFAULT 4 CHECK (gudang_slot >= 1),
  admin bigint NOT NULL DEFAULT 800000 CHECK (admin >= 0)
);

COMMENT ON TABLE public.gaji_setelan IS
  'Patokan penuh gaji + anggaran BOP/ongkir target. Bukan hasil nota.';

INSERT INTO public.gaji_setelan (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.gaji_setelan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gaji_setelan FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.gaji_setelan FROM PUBLIC;
REVOKE ALL ON TABLE public.gaji_setelan FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.gaji_setelan
  TO postgres, service_role;

DROP FUNCTION IF EXISTS public.admin_gaji_setelan();
CREATE FUNCTION public.admin_gaji_setelan()
RETURNS public.gaji_setelan
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  RETURN (SELECT g FROM public.gaji_setelan g WHERE g.id = 1);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint
);
CREATE FUNCTION public.admin_gaji_setelan_simpan(
  p_bop_mobil bigint,
  p_ongkir_semua bigint,
  p_sales_net bigint,
  p_sales_visit bigint,
  p_sales_ec bigint,
  p_pengirim bigint,
  p_gudang bigint,
  p_gudang_slot integer,
  p_admin bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  INSERT INTO public.gaji_setelan (
    id, bop_mobil, ongkir_semua, sales_net, sales_visit, sales_ec,
    pengirim, gudang, gudang_slot, admin
  )
  VALUES (
    1, GREATEST(p_bop_mobil, 0), GREATEST(p_ongkir_semua, 0),
    GREATEST(p_sales_net, 0), GREATEST(p_sales_visit, 0),
    GREATEST(p_sales_ec, 0), GREATEST(p_pengirim, 0),
    GREATEST(p_gudang, 0), GREATEST(p_gudang_slot, 1), GREATEST(p_admin, 0)
  )
  ON CONFLICT (id) DO UPDATE SET
    bop_mobil = EXCLUDED.bop_mobil,
    ongkir_semua = EXCLUDED.ongkir_semua,
    sales_net = EXCLUDED.sales_net,
    sales_visit = EXCLUDED.sales_visit,
    sales_ec = EXCLUDED.sales_ec,
    pengirim = EXCLUDED.pengirim,
    gudang = EXCLUDED.gudang,
    gudang_slot = EXCLUDED.gudang_slot,
    admin = EXCLUDED.admin;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_gaji_absen(date, date);
CREATE FUNCTION public.admin_gaji_absen(p_senin date, p_sabtu date)
RETURNS TABLE (
  email text,
  nama text,
  peran text,
  rute text,
  hari integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  RETURN QUERY
  WITH orang AS (
    SELECT
      lower(btrim(u.email)) AS email,
      coalesce(nullif(btrim(u.nama), ''), btrim(u.email)) AS nama,
      btrim(u.peran) AS peran,
      btrim(coalesce(u.rute, '')) AS rute
    FROM public.users u
    WHERE u.peran IN ('pengirim', 'gudang', 'admin')
  ),
  hitung AS (
    SELECT
      lower(btrim(a.email)) AS email,
      count(DISTINCT a.id_setoran_buku)::integer AS hari
    FROM public.absensi a
    JOIN public.setoran_buku b ON b.id = a.id_setoran_buku
    WHERE a.waktu_masuk IS NOT NULL
      AND b.tanggal >= p_senin
      AND b.tanggal <= p_sabtu
    GROUP BY lower(btrim(a.email))
  )
  SELECT
    o.email,
    o.nama,
    o.peran,
    o.rute,
    coalesce(h.hari, 0)
  FROM orang o
  LEFT JOIN hitung h ON h.email = o.email
  ORDER BY o.peran, o.rute, o.nama;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gaji_setelan() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_setelan()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint
) TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_absen(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_absen(date, date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
