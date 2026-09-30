-- Margin kotor actual per cap buku. Tidak disimpan di tabel:
-- sumbernya nota terkirim + v_transaksi_item (strata × qty_actual).
-- Margin retur = (qty×jual) − (qty×beli item di buku yang sama).
-- Retur, ongkir, BOP, kasbon pengirim tampil terpisah, bukan pengurang rasio.
-- Jalankan SETELAH 111. Boleh diulang.

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
  kasbon bigint
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
    coalesce(st.kasbon, 0)
  FROM public.setoran_buku b
  LEFT JOIN uang u ON u.id_buku = b.id
  LEFT JOIN retur rt ON rt.id_buku = b.id
  LEFT JOIN biaya bi ON bi.id_buku = b.id
  LEFT JOIN setor st ON st.id_buku = b.id
  ORDER BY b.tanggal, b.id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_margin_buku() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_margin_buku() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_margin_buku()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_margin_buku() IS
  'Margin kotor actual per cap buku. Margin retur, ongkir, BOP, kasbon terpisah.';

DROP FUNCTION IF EXISTS public.admin_margin_rute();

CREATE FUNCTION public.admin_margin_rute()
RETURNS TABLE (
  id bigint,
  tanggal date,
  rute text,
  nama text,
  nota integer,
  omset bigint,
  modal bigint,
  margin bigint
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
      btrim(t.rute) AS rute,
      count(DISTINCT t.id_transaksi)::integer AS nota,
      coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS omset,
      coalesce(sum(i.subtotal_beli_actual), 0)::bigint AS modal
    FROM public.transaksi t
    JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
    WHERE t.status = 'terkirim'
      AND t.id_setoran_buku IS NOT NULL
      AND btrim(t.rute) <> ''
    GROUP BY t.id_setoran_buku, btrim(t.rute)
  ),
  sales AS (
    SELECT DISTINCT ON (btrim(u.rute))
      btrim(u.rute) AS rute,
      coalesce(nullif(btrim(u.nama), ''), '') AS nama
    FROM public.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
    ORDER BY btrim(u.rute), u.email
  )
  SELECT
    b.id,
    b.tanggal,
    u.rute,
    coalesce(s.nama, '')::text,
    u.nota,
    u.omset,
    u.modal,
    (u.omset - u.modal)::bigint
  FROM uang u
  JOIN public.setoran_buku b ON b.id = u.id_buku
  LEFT JOIN sales s ON s.rute = u.rute
  ORDER BY b.tanggal, b.id, u.rute;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_margin_rute() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_margin_rute() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_margin_rute()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_margin_rute() IS
  'Margin kotor actual per cap buku per rute sales. Filter minggu di app.';

NOTIFY pgrst, 'reload schema';
