-- Snapshot kartu setoran: chip Simpan + beku saat tutup buku.
-- Jalankan SETELAH 009. Buku tutup baca foto pending, bukan flag nota yang pindah.
-- public/app tidak diubah. Boleh diulang.

CREATE OR REPLACE FUNCTION obos.kartu_setoran_hidup(p_id_buku bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_baris jsonb;
BEGIN
  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = p_id_buku;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'dari_snapshot', false,
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
        'kasbon_supir', coalesce(s.kasbon_supir, 0),
        'kasbon_kenek', coalesce(s.kasbon_kenek, 0),
        'nama_supir', coalesce(nm.nama_supir, ''),
        'nama_kenek', coalesce(nm.nama_kenek, ''),
        'retur', coalesce(r.nilai, 0),
        'sudah_setor', s.id IS NOT NULL
      ) AS baris
    FROM (SELECT DISTINCT rute_pengirim FROM obos.rute_peta) p
    LEFT JOIN (
      SELECT
        rp.rute_pengirim,
        coalesce(sum(o.jual_packed), 0)::bigint AS kiriman,
        coalesce(sum(
          CASE
            WHEN obos.pending_kartu(v_tutup, v_id, o.id_transaksi, o.pending)
              THEN 0
            ELSE o.jual_batal
          END
        ), 0)::bigint AS batal,
        coalesce(sum(
          CASE
            WHEN obos.pending_kartu(v_tutup, v_id, o.id_transaksi, o.pending)
              THEN o.jual_packed
            ELSE 0
          END
        ), 0)::bigint AS pending,
        coalesce(sum(
          CASE
            WHEN obos.pending_kartu(v_tutup, v_id, o.id_transaksi, o.pending)
              THEN 0
            ELSE o.jual_actual_kartu
          END
        ), 0)::bigint AS actual,
        count(*) FILTER (
          WHERE o.status = 'dikirim' AND NOT o.pending
        )::integer AS wajib_kunci
      FROM obos.v_omset_nota o
      JOIN obos.rute_peta rp ON rp.rute_sales = o.rute
      WHERE o.waktu_packed IS NOT NULL
        AND obos.nota_ikut_admin(
          v_id, v_tgl, v_tutup, o.id_setoran_buku, o.status, o.waktu_actual
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN obos.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        obos.grup_rute(u.rute) AS rute_pengirim,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'D' THEN u.nama END) AS nama_supir,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'H' THEN u.nama END) AS nama_kenek
      FROM obos.users u
      WHERE u.peran = 'pengirim'
      GROUP BY obos.grup_rute(u.rute)
    ) nm ON nm.rute_pengirim = p.rute_pengirim
    LEFT JOIN (
      SELECT
        i.rute_pengirim,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM obos.retur_toko i
      WHERE i.id_setoran_buku = v_id
      GROUP BY i.rute_pengirim
    ) r ON r.rute_pengirim = p.rute_pengirim
  ) q;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', COALESCE(v_tutup, false),
    'dari_snapshot', false,
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.kartu_setoran_bekukan(
  p_id_buku bigint,
  p_cek jsonb DEFAULT NULL,
  p_tunai jsonb DEFAULT NULL,
  p_kasbon jsonb DEFAULT NULL,
  p_dicatat_oleh text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_lama jsonb;
  v_isi jsonb;
  v_tutup boolean;
BEGIN
  IF p_id_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran kosong.';
  END IF;
  SELECT b.id, b.ditutup INTO v_id, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = p_id_buku;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Buku setoran tidak ada.';
  END IF;

  SELECT s.isi INTO v_lama
  FROM obos.setoran_kartu_simpan s
  WHERE s.id_setoran_buku = v_id;

  v_isi := obos.kartu_setoran_hidup(v_id)
    || jsonb_build_object(
      'cek', coalesce(p_cek, v_lama -> 'cek', '{}'::jsonb),
      'tunai_admin', coalesce(p_tunai, v_lama -> 'tunai_admin', '{}'::jsonb),
      'kasbon', coalesce(p_kasbon, v_lama -> 'kasbon', '{}'::jsonb),
      'dari_snapshot', true,
      'ditutup', COALESCE(v_tutup, false)
    );

  INSERT INTO obos.setoran_kartu_simpan (
    id_setoran_buku, isi, waktu_simpan, dicatat_oleh
  ) VALUES (
    v_id, v_isi, clock_timestamp(),
    nullif(btrim(COALESCE(p_dicatat_oleh, '')), '')
  )
  ON CONFLICT (id_setoran_buku) DO UPDATE SET
    isi = EXCLUDED.isi,
    waktu_simpan = EXCLUDED.waktu_simpan,
    dicatat_oleh = COALESCE(EXCLUDED.dicatat_oleh, obos.setoran_kartu_simpan.dicatat_oleh);

  RETURN v_isi;
END;
$$;

CREATE OR REPLACE FUNCTION obos.kartu_setoran_simpan(
  p_id_buku bigint,
  p_cek jsonb DEFAULT NULL,
  p_tunai jsonb DEFAULT NULL,
  p_kasbon jsonb DEFAULT NULL,
  p_dicatat_oleh text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = obos
AS $$
BEGIN
  RETURN obos.kartu_setoran_bekukan(
    p_id_buku, p_cek, p_tunai, p_kasbon, p_dicatat_oleh
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.kartu_setoran(p_id_buku bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_tgl date;
  v_tutup boolean;
  v_hidup jsonb;
  v_snap jsonb;
BEGIN
  IF p_id_buku IS NULL THEN
    v_id := obos.buku_terbuka();
  ELSE
    v_id := p_id_buku;
  END IF;

  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'dari_snapshot', false,
      'rute', '[]'::jsonb
    );
  END IF;

  IF COALESCE(v_tutup, false) THEN
    SELECT s.isi INTO v_snap
    FROM obos.setoran_kartu_simpan s
    WHERE s.id_setoran_buku = v_id;
    IF v_snap IS NOT NULL THEN
      RETURN v_snap || jsonb_build_object(
        'dari_snapshot', true,
        'ada_buku', true,
        'id_setoran_buku', v_id,
        'tanggal', v_tgl,
        'ditutup', true
      );
    END IF;
  END IF;

  v_hidup := obos.kartu_setoran_hidup(v_id);
  SELECT s.isi INTO v_snap
  FROM obos.setoran_kartu_simpan s
  WHERE s.id_setoran_buku = v_id;
  IF v_snap IS NULL THEN
    RETURN coalesce(v_hidup, '{}'::jsonb);
  END IF;
  RETURN coalesce(v_hidup, '{}'::jsonb) || jsonb_build_object(
    'cek', coalesce(v_snap -> 'cek', '{}'::jsonb),
    'tunai_admin', coalesce(v_snap -> 'tunai_admin', '{}'::jsonb),
    'kasbon', coalesce(v_snap -> 'kasbon', '{}'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION obos.buku_daftar()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_baris jsonb;
BEGIN
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', b.id,
        'tanggal', b.tanggal,
        'ditutup', b.ditutup,
        'ada_snapshot', EXISTS (
          SELECT 1 FROM obos.setoran_kartu_simpan s
          WHERE s.id_setoran_buku = b.id
        )
      )
      ORDER BY b.id DESC
    ),
    '[]'::jsonb
  )
  INTO v_baris
  FROM obos.setoran_buku b;
  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION obos.tutup_buku()
RETURNS bigint
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_sku text;
  v_n integer;
  v_fisik integer;
BEGIN
  PERFORM pg_advisory_xact_lock(88221940);
  v_id := obos.buku_terbuka();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM obos.transaksi t
  WHERE t.id_setoran_buku = v_id
    AND t.status = 'dikirim'
    AND NOT COALESCE(t.pending, false);
  IF v_n > 0 THEN
    RAISE EXCEPTION
      'Masih ada % nota dikirim. Pengirim selesaikan dulu, lalu tutup buku.',
      v_n;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM obos.absensi a
  WHERE a.waktu_keluar IS NULL
    AND a.peran IN ('gudang', 'pengirim')
    AND a.id_setoran_buku = v_id;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada absensi yang belum pulang. Scan pulang dulu, lalu tutup buku.';
  END IF;

  SELECT count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer
  INTO v_fisik
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id;
  IF COALESCE(v_fisik, 0) <= 0 THEN
    RAISE EXCEPTION 'Opname fisik belum diisi. Gudang isi fisik dulu, lalu tutup buku.';
  END IF;

  SELECT so.id_barang INTO v_sku
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) < 0
    AND so.putusan IS DISTINCT FROM 'kasbon'
    AND so.putusan IS DISTINCT FROM 'beban'
  ORDER BY lower(so.nama_barang)
  LIMIT 1;
  IF v_sku IS NOT NULL THEN
    RAISE EXCEPTION
      'Masih ada selisih kurang belum diputuskan (SKU %). Kasbon atau potong margin dulu.',
      v_sku;
  END IF;

  UPDATE obos.stok_opname so
  SET
    putusan = 'margin_plus',
    nilai_putusan = round(so.selisih * GREATEST(COALESCE(b.harga_beli, 0), 0))::integer,
    harga_beli_putusan = GREATEST(COALESCE(b.harga_beli, 0), 0)::integer,
    qty_selisih_putusan = so.selisih,
    kasbon_email = NULL,
    kasbon_nama = NULL,
    waktu_putusan = clock_timestamp()
  FROM obos.barang b
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang
    AND so.stok_fisik IS NOT NULL
    AND COALESCE(so.selisih, 0) > 0;

  UPDATE obos.barang b
  SET stok = GREATEST(0, COALESCE(so.stok_fisik, so.stok_hitung, 0))
  FROM obos.stok_opname so
  WHERE so.id_setoran_buku = v_id
    AND so.id_barang = b.id_barang;

  PERFORM obos.foto_catat(v_id);

  UPDATE obos.setoran_buku
  SET ditutup = true, waktu_tutup = clock_timestamp()
  WHERE id = v_id AND NOT ditutup;

  PERFORM obos.kartu_setoran_bekukan(v_id);
  RETURN v_id;
END;
$$;

DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'obos'
      AND p.proname IN (
        'kartu_setoran_hidup', 'kartu_setoran_bekukan',
        'kartu_setoran_simpan', 'kartu_setoran',
        'buku_daftar', 'tutup_buku'
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION obos.%I(%s) FROM PUBLIC, anon, authenticated',
      f.proname, f.args
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION obos.%I(%s) TO postgres, service_role',
      f.proname, f.args
    );
  END LOOP;
END;
$$;
