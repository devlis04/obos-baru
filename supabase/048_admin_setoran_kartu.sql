-- Kartu setoran admin: omset hidup + uang pengirim + retur.
-- Tanpa snapshot / tabel cek lama. Jalankan SETELAH 047. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_setoran_kartu()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_baris jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_id := public.setoran_buku_terbuka();
  IF v_id IS NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    ORDER BY b.id DESC
    LIMIT 1;
  ELSE
    SELECT b.tanggal, b.ditutup
    INTO v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = v_id;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'rute', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(q.baris ORDER BY q.rute_pengirim), '[]'::jsonb)
  INTO v_baris
  FROM (
    SELECT
      p.rute_pengirim,
      jsonb_build_object(
        'rute_pengirim', p.rute_pengirim,
        'kiriman', coalesce(o.kiriman, 0),
        'batal', coalesce(o.batal, 0),
        'pending', coalesce(o.pending, 0),
        'actual', coalesce(o.actual, 0),
        'wajib_kunci', coalesce(o.wajib_kunci, 0),
        'transfer', coalesce(s.jumlah_transfer, 0),
        'tunai', coalesce(s.jumlah_tunai, 0),
        'bop', coalesce(s.jumlah_bop, 0),
        'kasbon', coalesce(s.kasbon_supir, 0) + coalesce(s.kasbon_kenek, 0),
        'retur', coalesce(r.nilai, 0),
        'sudah_setor', s.id IS NOT NULL
      ) AS baris
    FROM (
      SELECT DISTINCT rute_pengirim
      FROM public.rute_peta
    ) p
    LEFT JOIN (
      SELECT
        rp.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS kiriman,
        coalesce(sum(
          CASE WHEN t.status = 'batal' THEN i.subtotal_jual_packed ELSE 0 END
        ), 0)::bigint AS batal,
        coalesce(sum(
          CASE WHEN t.pending THEN i.subtotal_jual_packed ELSE 0 END
        ), 0)::bigint AS pending,
        coalesce(sum(
          CASE WHEN t.status = 'batal' THEN 0 ELSE i.subtotal_jual_actual END
        ), 0)::bigint AS actual,
        count(DISTINCT t.id_transaksi) FILTER (
          WHERE t.status = 'dikirim' AND NOT t.pending
        )::integer AS wajib_kunci
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      JOIN public.v_transaksi_item i ON i.id_transaksi = t.id_transaksi
      WHERE t.waktu_packed IS NOT NULL
        AND (
          t.id_setoran_buku = v_id
          OR (
            t.id_setoran_buku IS NULL
            AND (
              t.status = 'dikirim'
              OR (
                t.status IN ('terkirim', 'batal')
                AND t.waktu_actual IS NOT NULL
                AND (t.waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = v_tgl
              )
            )
          )
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN public.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        i.rute_pengirim,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM public.retur_toko i
      WHERE i.id_setoran_buku = v_id
      GROUP BY i.rute_pengirim
    ) r ON r.rute_pengirim = p.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', coalesce(v_tutup, false),
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_setoran_kartu() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu()
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
