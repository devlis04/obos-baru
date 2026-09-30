-- Snapshot rute sales di retur: rute toko saat retur dicatat, tidak ikut
-- pindah rute kemudian. Margin per rute sales memakai kolom ini.
-- Jalankan SETELAH 112. Boleh diulang.

ALTER TABLE public.retur_toko
  ADD COLUMN IF NOT EXISTS rute_sales text NOT NULL DEFAULT '';

COMMENT ON COLUMN public.retur_toko.rute_sales IS
  'Rute salesman toko saat retur dicatat. Tidak diubah jika toko pindah rute.';

UPDATE public.retur_toko r
SET rute_sales = x.rute
FROM (
  SELECT DISTINCT ON (t.id_setoran_buku, t.id_pelanggan)
    t.id_setoran_buku,
    t.id_pelanggan,
    btrim(t.rute) AS rute
  FROM public.transaksi t
  WHERE t.id_setoran_buku IS NOT NULL
    AND btrim(t.rute) <> ''
  ORDER BY
    t.id_setoran_buku,
    t.id_pelanggan,
    t.waktu_actual DESC NULLS LAST,
    t.waktu_order DESC
) x
WHERE r.id_setoran_buku = x.id_setoran_buku
  AND r.id_pelanggan = x.id_pelanggan
  AND btrim(r.rute_sales) = '';

UPDATE public.retur_toko r
SET rute_sales = btrim(p.rute)
FROM public.pelanggan p
WHERE p.id_pelanggan = r.id_pelanggan
  AND btrim(r.rute_sales) = ''
  AND btrim(COALESCE(p.rute, '')) <> '';

CREATE OR REPLACE FUNCTION public.retur_toko_cap_buku()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_sales text;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.id_setoran_buku IS NOT NULL THEN
    NEW.id_setoran_buku := OLD.id_setoran_buku;
    NEW.rute_pengirim := public.pengirim_grup_rute(OLD.rute_pengirim);
    SELECT b.tanggal INTO v_tgl
    FROM public.setoran_buku b
    WHERE b.id = OLD.id_setoran_buku;
    IF v_tgl IS NOT NULL THEN
      NEW.tanggal := v_tgl;
    END IF;
    IF btrim(COALESCE(OLD.rute_sales, '')) <> '' THEN
      NEW.rute_sales := btrim(OLD.rute_sales);
    END IF;
    RETURN NEW;
  END IF;

  SELECT b.id, b.tanggal INTO v_id, v_tgl
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  LIMIT 1;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku setoran terbuka. Retur tidak dicatat ke tanggal berikutnya.';
  END IF;
  NEW.id_setoran_buku := v_id;
  NEW.tanggal := v_tgl;
  NEW.rute_pengirim := public.pengirim_grup_rute(NEW.rute_pengirim);

  IF btrim(COALESCE(NEW.rute_sales, '')) = '' THEN
    SELECT nullif(btrim(p.rute), '')
    INTO v_sales
    FROM public.pelanggan p
    WHERE p.id_pelanggan = NEW.id_pelanggan;
    NEW.rute_sales := coalesce(v_sales, '');
  ELSE
    NEW.rute_sales := btrim(NEW.rute_sales);
  END IF;
  RETURN NEW;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_margin_rute();

CREATE FUNCTION public.admin_margin_rute()
RETURNS TABLE (
  id bigint,
  tanggal date,
  rute text,
  nama text,
  rute_pengirim text,
  nota integer,
  omset bigint,
  modal bigint,
  margin bigint,
  margin_retur bigint,
  bop bigint
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
  retur AS (
    SELECT
      r.id_setoran_buku AS id_buku,
      btrim(r.rute_sales) AS rute,
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
    WHERE btrim(COALESCE(r.rute_sales, '')) <> ''
    GROUP BY r.id_setoran_buku, btrim(r.rute_sales)
  ),
  gabung AS (
    SELECT
      coalesce(u.id_buku, rt.id_buku) AS id_buku,
      coalesce(u.rute, rt.rute) AS rute,
      coalesce(u.nota, 0) AS nota,
      coalesce(u.omset, 0) AS omset,
      coalesce(u.modal, 0) AS modal,
      (coalesce(u.omset, 0) - coalesce(u.modal, 0))::bigint AS margin,
      coalesce(rt.margin_retur, 0) AS margin_retur
    FROM uang u
    FULL JOIN retur rt
      ON rt.id_buku = u.id_buku
     AND rt.rute = u.rute
  ),
  sales AS (
    SELECT DISTINCT ON (btrim(u.rute))
      btrim(u.rute) AS rute,
      coalesce(nullif(btrim(u.nama), ''), '') AS nama
    FROM public.users u
    WHERE u.peran = 'sales'
      AND nullif(btrim(u.rute), '') IS NOT NULL
    ORDER BY btrim(u.rute), u.email
  ),
  peta AS (
    SELECT DISTINCT ON (btrim(rp.rute_sales))
      btrim(rp.rute_sales) AS rute_sales,
      btrim(rp.rute_pengirim) AS rute_pengirim
    FROM public.rute_peta rp
    WHERE btrim(rp.rute_sales) <> ''
      AND btrim(rp.rute_pengirim) <> ''
    ORDER BY btrim(rp.rute_sales), btrim(rp.rute_pengirim)
  ),
  setor AS (
    SELECT
      s.id_setoran_buku AS id_buku,
      btrim(s.rute_pengirim) AS rute_pengirim,
      coalesce(sum(s.jumlah_bop::bigint), 0) AS bop
    FROM public.setoran_pengirim s
    GROUP BY s.id_setoran_buku, btrim(s.rute_pengirim)
  )
  SELECT
    b.id,
    b.tanggal,
    g.rute,
    coalesce(s.nama, '')::text,
    coalesce(p.rute_pengirim, '')::text,
    g.nota,
    g.omset,
    g.modal,
    g.margin,
    g.margin_retur,
    coalesce(st.bop, 0)::bigint
  FROM gabung g
  JOIN public.setoran_buku b ON b.id = g.id_buku
  LEFT JOIN sales s ON s.rute = g.rute
  LEFT JOIN peta p ON p.rute_sales = g.rute
  LEFT JOIN setor st
    ON st.id_buku = g.id_buku
   AND st.rute_pengirim = p.rute_pengirim
  ORDER BY b.tanggal, b.id, g.rute;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_margin_rute() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_margin_rute() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_margin_rute()
  TO authenticated, postgres, service_role;

COMMENT ON FUNCTION public.admin_margin_rute() IS
  'Per rute sales: margin actual, margin retur snapshot, BOP pengirim utuh (pembagian di app).';

NOTIFY pgrst, 'reload schema';
