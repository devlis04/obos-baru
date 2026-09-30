-- Kolom selisih opname di margin per buku.
-- Default = (lebih stok → tambah) − (putusan beban → kurang).
-- Kasbon opname tidak masuk. Admin boleh override per buku.
-- Jalankan SETELAH 113. Boleh diulang.

ALTER TABLE public.setoran_buku
  ADD COLUMN IF NOT EXISTS selisih_opname bigint;

COMMENT ON COLUMN public.setoran_buku.selisih_opname IS
  'Nilai tampil selisih opname di halaman Margin. NULL = pakai hitungan opname.';

DROP FUNCTION IF EXISTS public.admin_margin_buku();

CREATE FUNCTION public.admin_margin_buku()
RETURNS TABLE (
  id bigint,
  tanggal date,
  ditutup boolean,
  nota integer,
  omset bigint,
  modal bigint,
  margin bigint,
  margin_retur bigint,
  ongkir bigint,
  bop bigint,
  kasbon bigint,
  selisih_opname bigint,
  selisih_opname_hitung bigint,
  selisih_opname_manual boolean
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
  WITH uang AS (
    SELECT
      t.id_setoran_buku AS id_buku,
      count(DISTINCT t.id_transaksi)::integer AS nota,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS omset,
      coalesce(sum(i.subtotal_beli_actual), 0)::bigint AS modal
    FROM public.transaksi t
    JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
    WHERE t.status = 'terkirim'
      AND t.id_setoran_buku IS NOT NULL
    GROUP BY t.id_setoran_buku
  ),
  retur AS (
    SELECT
      r.id_setoran_buku AS id_buku,
      coalesce(
        sum(
          (r.qty::bigint * r.harga_jual::bigint)
          - (r.qty::bigint * coalesce(beli.harga_beli, 0)::bigint)
        ),
        0
      )::bigint AS margin_retur
    FROM public.retur_toko r
    LEFT JOIN LATERAL (
      SELECT i.harga_beli
      FROM public.transaksi t
      JOIN public.transaksi_items i ON i.id_transaksi = t.id_transaksi
      WHERE t.id_setoran_buku = r.id_setoran_buku
        AND i.id_barang = r.kode_barang
      ORDER BY
        CASE WHEN t.id_pelanggan = r.id_pelanggan THEN 0 ELSE 1 END,
        i.id DESC
      LIMIT 1
    ) beli ON true
    GROUP BY r.id_setoran_buku
  ),
  biaya AS (
    SELECT
      o.id_setoran_buku AS id_buku,
      coalesce(sum(o.jumlah::bigint), 0)::bigint AS ongkir
    FROM public.ongkir o
    GROUP BY o.id_setoran_buku
  ),
  setor AS (
    SELECT
      s.id_setoran_buku AS id_buku,
      coalesce(sum(s.jumlah_bop::bigint), 0)::bigint AS bop,
      coalesce(
        sum(s.kasbon_supir::bigint + s.kasbon_kenek::bigint),
        0
      )::bigint AS kasbon
    FROM public.setoran_pengirim s
    GROUP BY s.id_setoran_buku
  ),
  opname AS (
    SELECT
      so.id_setoran_buku AS id_buku,
      (
        coalesce(sum(
          CASE
            WHEN so.putusan = 'margin_plus' THEN so.nilai_putusan
            WHEN so.putusan IS NULL
              AND so.stok_fisik IS NOT NULL
              AND coalesce(so.selisih, 0) > 0
            THEN round(so.selisih * coalesce(br.harga_beli, 0))::integer
            ELSE 0
          END
        ), 0)
        - coalesce(sum(
          CASE WHEN so.putusan = 'beban' THEN so.nilai_putusan ELSE 0 END
        ), 0)
      )::bigint AS hitung
    FROM public.stok_opname so
    LEFT JOIN public.barang br ON br.id_barang = so.id_barang
    GROUP BY so.id_setoran_buku
  )
  SELECT
    b.id,
    b.tanggal,
    b.ditutup,
    coalesce(u.nota, 0),
    coalesce(u.omset, 0),
    coalesce(u.modal, 0),
    (coalesce(u.omset, 0) - coalesce(u.modal, 0))::bigint,
    coalesce(rt.margin_retur, 0),
    coalesce(bi.ongkir, 0),
    coalesce(st.bop, 0),
    coalesce(st.kasbon, 0),
    coalesce(b.selisih_opname, coalesce(op.hitung, 0))::bigint,
    coalesce(op.hitung, 0)::bigint,
    (b.selisih_opname IS NOT NULL)
  FROM public.setoran_buku b
  LEFT JOIN uang u ON u.id_buku = b.id
  LEFT JOIN retur rt ON rt.id_buku = b.id
  LEFT JOIN biaya bi ON bi.id_buku = b.id
  LEFT JOIN setor st ON st.id_buku = b.id
  LEFT JOIN opname op ON op.id_buku = b.id
  ORDER BY b.tanggal, b.id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_margin_buku() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_margin_buku() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_margin_buku()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_margin_buku() IS
  'Margin kotor actual per cap buku. Selisih opname terpisah; NULL kolom = hitungan.';

DROP FUNCTION IF EXISTS public.admin_margin_set_selisih_opname(bigint, bigint, boolean);

CREATE FUNCTION public.admin_margin_set_selisih_opname(
  p_id bigint,
  p_nilai bigint,
  p_manual boolean
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

  UPDATE public.setoran_buku
  SET selisih_opname = CASE WHEN p_manual THEN p_nilai ELSE NULL END
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Buku tidak ditemukan.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_margin_set_selisih_opname(bigint, bigint, boolean)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_margin_set_selisih_opname(bigint, bigint, boolean)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_margin_set_selisih_opname(bigint, bigint, boolean)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
