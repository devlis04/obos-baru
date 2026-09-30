-- Pool omset + rasio target sales untuk hitung gaji.
-- 0 = pakai target per sales (target_sales).
-- Jalankan SETELAH 116. Boleh diulang.

ALTER TABLE public.gaji_setelan
  ADD COLUMN IF NOT EXISTS omset_semua bigint NOT NULL DEFAULT 0
    CHECK (omset_semua >= 0);
ALTER TABLE public.gaji_setelan
  ADD COLUMN IF NOT EXISTS rasio_sales numeric NOT NULL DEFAULT 0
    CHECK (rasio_sales >= 0);

COMMENT ON COLUMN public.gaji_setelan.omset_semua IS
  'Pool omset target semua rute. 0 = pakai target_sales per rute.';
COMMENT ON COLUMN public.gaji_setelan.rasio_sales IS
  'Rasio target (%) semua rute. 0 = pakai target_sales per rute.';

DROP FUNCTION IF EXISTS public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint
);
DROP FUNCTION IF EXISTS public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint,
  bigint, numeric
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
  p_admin bigint,
  p_omset_semua bigint,
  p_rasio_sales numeric
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
    pengirim, gudang, gudang_slot, admin, omset_semua, rasio_sales
  )
  VALUES (
    1, GREATEST(p_bop_mobil, 0), GREATEST(p_ongkir_semua, 0),
    GREATEST(p_sales_net, 0), GREATEST(p_sales_visit, 0),
    GREATEST(p_sales_ec, 0), GREATEST(p_pengirim, 0),
    GREATEST(p_gudang, 0), GREATEST(p_gudang_slot, 1), GREATEST(p_admin, 0),
    GREATEST(p_omset_semua, 0), GREATEST(p_rasio_sales, 0)
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
    admin = EXCLUDED.admin,
    omset_semua = EXCLUDED.omset_semua,
    rasio_sales = EXCLUDED.rasio_sales;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint,
  bigint, numeric
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_setelan_simpan(
  bigint, bigint, bigint, bigint, bigint, bigint, bigint, integer, bigint,
  bigint, numeric
) TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
