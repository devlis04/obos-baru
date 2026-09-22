-- Kolom Rute sales dialog rinci kosong: admin tidak boleh SELECT transaksi (RLS sales).
-- Jalankan SETELAH 086. Pendek. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_rute_sales_peta(
  p_nota text[],
  p_toko text[]
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_nota jsonb;
  v_toko jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT coalesce(jsonb_object_agg(t.id_transaksi, t.rute), '{}'::jsonb)
  INTO v_nota
  FROM public.transaksi t
  WHERE p_nota IS NOT NULL
    AND t.id_transaksi = ANY (p_nota)
    AND nullif(btrim(t.rute), '') IS NOT NULL;

  SELECT coalesce(jsonb_object_agg(p.id_pelanggan, p.rute), '{}'::jsonb)
  INTO v_toko
  FROM public.pelanggan p
  WHERE p_toko IS NOT NULL
    AND p.id_pelanggan = ANY (p_toko)
    AND nullif(btrim(p.rute), '') IS NOT NULL;

  RETURN jsonb_build_object(
    'nota', coalesce(v_nota, '{}'::jsonb),
    'toko', coalesce(v_toko, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_rute_sales_peta(text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_rute_sales_peta(text[], text[])
  TO authenticated, postgres, service_role;
