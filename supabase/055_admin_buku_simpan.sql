-- Kalender pilih buku + Simpan snapshot kartu setoran.
-- Jalankan SETELAH 054. Boleh diulang.

-- Nota ikut buku: id buku, atau (buku masih terbuka) nota packed tanpa id.
CREATE OR REPLACE FUNCTION public.admin_transaksi_ikut_buku(
  p_id_buku bigint,
  p_tgl date,
  p_tutup boolean,
  p_id_setoran_buku bigint,
  p_status text,
  p_waktu_actual timestamptz
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_id_buku IS NOT NULL
    AND (
      p_id_setoran_buku = p_id_buku
      OR (
        p_id_setoran_buku IS NULL
        AND NOT coalesce(p_tutup, false)
        AND (
          p_status = 'dikirim'
          OR (
            p_status IN ('terkirim', 'batal')
            AND p_waktu_actual IS NOT NULL
            AND (p_waktu_actual AT TIME ZONE 'Asia/Jakarta')::date = p_tgl
          )
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_buku_lihat(
  p_id bigint DEFAULT NULL,
  OUT id bigint,
  OUT tanggal date,
  OUT ditutup boolean
)
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
BEGIN
  IF p_id IS NOT NULL THEN
    SELECT b.id, b.tanggal, b.ditutup
    INTO v_id, v_tgl, v_tutup
    FROM public.setoran_buku b
    WHERE b.id = p_id;
  ELSE
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
  END IF;

  id := v_id;
  tanggal := v_tgl;
  ditutup := v_tutup;
END;
$$;

CREATE TABLE IF NOT EXISTS public.setoran_kartu_simpan (
  id_setoran_buku bigint PRIMARY KEY REFERENCES public.setoran_buku (id),
  isi jsonb NOT NULL,
  waktu_simpan timestamptz NOT NULL DEFAULT clock_timestamp(),
  dicatat_oleh text
);

ALTER TABLE public.setoran_kartu_simpan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setoran_kartu_simpan FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS setoran_kartu_simpan_select ON public.setoran_kartu_simpan;
CREATE POLICY setoran_kartu_simpan_select
  ON public.setoran_kartu_simpan
  FOR SELECT
  TO authenticated
  USING (public.admin_sedang_login());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.setoran_kartu_simpan
  TO postgres, service_role;
GRANT SELECT ON TABLE public.setoran_kartu_simpan TO authenticated;
REVOKE ALL ON TABLE public.setoran_kartu_simpan FROM anon;

CREATE OR REPLACE FUNCTION public.admin_setoran_buku_daftar()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_baris jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', b.id,
        'tanggal', b.tanggal,
        'ditutup', b.ditutup,
        'ada_snapshot', EXISTS (
          SELECT 1
          FROM public.setoran_kartu_simpan s
          WHERE s.id_setoran_buku = b.id
        )
      )
      ORDER BY b.id DESC
    ),
    '[]'::jsonb
  )
  INTO v_baris
  FROM public.setoran_buku b;

  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_setoran_kartu_hidup(p_id bigint)
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
  SELECT b.id, b.tanggal, b.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.setoran_buku b
  WHERE b.id = p_id;

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
        AND public.admin_transaksi_ikut_buku(
          v_id, v_tgl, v_tutup, t.id_setoran_buku, t.status, t.waktu_actual
        )
      GROUP BY rp.rute_pengirim
    ) o ON o.rute_pengirim = p.rute_pengirim
    LEFT JOIN public.setoran_pengirim s
      ON s.rute_pengirim = p.rute_pengirim
     AND s.id_setoran_buku = v_id
    LEFT JOIN (
      SELECT
        public.pengirim_grup_rute(u.rute) AS rute_pengirim,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'D' THEN u.nama END) AS nama_supir,
        max(CASE WHEN right(upper(btrim(u.rute)), 1) = 'H' THEN u.nama END) AS nama_kenek
      FROM public.users u
      WHERE u.peran = 'pengirim'
      GROUP BY public.pengirim_grup_rute(u.rute)
    ) nm ON nm.rute_pengirim = p.rute_pengirim
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
    'dari_snapshot', false,
    'rute', coalesce(v_baris, '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_setoran_kartu();
CREATE OR REPLACE FUNCTION public.admin_setoran_kartu(
  p_id_setoran_buku bigint DEFAULT NULL
)
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
  v_hidup jsonb;
  v_snap jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT x.id, x.tanggal, x.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

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

  IF coalesce(v_tutup, false) THEN
    SELECT s.isi INTO v_snap
    FROM public.setoran_kartu_simpan s
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

  v_hidup := public.admin_setoran_kartu_hidup(v_id);
  SELECT s.isi INTO v_snap
  FROM public.setoran_kartu_simpan s
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

CREATE OR REPLACE FUNCTION public.admin_setoran_simpan(
  p_id_setoran_buku bigint,
  p_cek jsonb DEFAULT NULL,
  p_tunai jsonb DEFAULT NULL,
  p_kasbon jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_isi jsonb;
  v_email text;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_id_setoran_buku IS NULL THEN
    RAISE EXCEPTION 'Buku setoran kosong.';
  END IF;

  SELECT b.id INTO v_id
  FROM public.setoran_buku b
  WHERE b.id = p_id_setoran_buku;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Buku setoran tidak ada.';
  END IF;

  v_email := nullif(btrim(COALESCE(auth.jwt() ->> 'email', '')), '');
  v_isi := public.admin_setoran_kartu_hidup(v_id)
    || jsonb_build_object(
      'cek', coalesce(p_cek, '{}'::jsonb),
      'tunai_admin', coalesce(p_tunai, '{}'::jsonb),
      'kasbon', coalesce(p_kasbon, '{}'::jsonb),
      'dari_snapshot', true
    );

  INSERT INTO public.setoran_kartu_simpan (
    id_setoran_buku, isi, waktu_simpan, dicatat_oleh
  ) VALUES (
    v_id, v_isi, clock_timestamp(), v_email
  )
  ON CONFLICT (id_setoran_buku) DO UPDATE
  SET
    isi = EXCLUDED.isi,
    waktu_simpan = EXCLUDED.waktu_simpan,
    dicatat_oleh = EXCLUDED.dicatat_oleh;

  RETURN v_isi;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_opname_ringkas();
CREATE OR REPLACE FUNCTION public.admin_opname_ringkas(
  p_id_setoran_buku bigint DEFAULT NULL
)
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
  v_total integer := 0;
  v_fisik integer := 0;
  v_selisih integer := 0;
  v_nilai bigint := 0;
  v_minus_belum integer := 0;
  v_kasbon bigint := 0;
  v_beban bigint := 0;
  v_plus bigint := 0;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT x.id, x.tanggal, x.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'ada_buku', false,
      'id_setoran_buku', NULL,
      'tanggal', NULL,
      'ditutup', false,
      'sku_total', 0,
      'sku_fisik', 0,
      'sku_selisih', 0,
      'nilai_selisih', 0,
      'sku_minus_belum', 0,
      'nilai_kasbon', 0,
      'nilai_beban', 0,
      'nilai_margin_plus', 0
    );
  END IF;

  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE so.stok_fisik IS NOT NULL)::integer,
    count(*) FILTER (
      WHERE so.stok_fisik IS NOT NULL AND COALESCE(so.selisih, 0) <> 0
    )::integer,
    coalesce(sum(
      CASE
        WHEN so.stok_fisik IS NULL THEN 0
        ELSE round(COALESCE(so.selisih, 0) * COALESCE(b.harga_beli, 0))
      END
    ), 0)::bigint,
    count(*) FILTER (
      WHERE so.stok_fisik IS NOT NULL
        AND COALESCE(so.selisih, 0) < 0
        AND so.putusan IS DISTINCT FROM 'kasbon'
        AND so.putusan IS DISTINCT FROM 'beban'
    )::integer,
    coalesce(sum(so.nilai_putusan) FILTER (WHERE so.putusan = 'kasbon'), 0)::bigint,
    coalesce(sum(so.nilai_putusan) FILTER (WHERE so.putusan = 'beban'), 0)::bigint,
    coalesce(sum(
      CASE
        WHEN so.stok_fisik IS NOT NULL AND COALESCE(so.selisih, 0) > 0
          THEN round(so.selisih * COALESCE(b.harga_beli, 0))
        ELSE 0
      END
    ), 0)::bigint
  INTO v_total, v_fisik, v_selisih, v_nilai, v_minus_belum, v_kasbon, v_beban, v_plus
  FROM public.stok_opname so
  LEFT JOIN public.barang b ON b.id_barang = so.id_barang
  WHERE so.id_setoran_buku = v_id;

  RETURN jsonb_build_object(
    'ada_buku', true,
    'id_setoran_buku', v_id,
    'tanggal', v_tgl,
    'ditutup', COALESCE(v_tutup, false),
    'sku_total', v_total,
    'sku_fisik', v_fisik,
    'sku_selisih', v_selisih,
    'nilai_selisih', v_nilai,
    'sku_minus_belum', v_minus_belum,
    'nilai_kasbon', v_kasbon,
    'nilai_beban', v_beban,
    'nilai_margin_plus', v_plus
  );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_absensi_buku();
CREATE OR REPLACE FUNCTION public.admin_absensi_buku(
  p_id_setoran_buku bigint DEFAULT NULL
)
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
  v_baris jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT x.id, x.tanggal
  INTO v_id, v_tgl
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  IF v_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'nama_kunci', u.email,
        'nama', u.nama,
        'urutan', CASE WHEN u.peran = 'pengirim' THEN 0 ELSE 1 END,
        'peran', u.peran,
        'di_dalam', EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        ),
        'pulang', EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NOT NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.absensi a
          WHERE lower(btrim(a.email)) = lower(btrim(u.email))
            AND a.waktu_masuk IS NOT NULL
            AND a.waktu_keluar IS NULL
            AND (
              a.id_setoran_buku = v_id
              OR (a.id_setoran_buku IS NULL AND a.tanggal = v_tgl)
            )
        )
      )
      ORDER BY
        CASE WHEN u.peran = 'pengirim' THEN 0 ELSE 1 END,
        u.rute,
        u.nama
    ),
    '[]'::jsonb
  )
  INTO v_baris
  FROM public.users u
  WHERE u.peran IN ('pengirim', 'gudang');

  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_mutasi_lihat();
CREATE OR REPLACE FUNCTION public.admin_mutasi_lihat(
  p_id_setoran_buku bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id bigint;
  v_baris jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  SELECT x.id INTO v_id
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  IF v_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(q.baris ORDER BY q.jumlah DESC, q.id), '[]'::jsonb)
  INTO v_baris
  FROM (
    SELECT
      m.id,
      m.jumlah,
      jsonb_build_object(
        'id', m.id,
        'tanggal_mutasi', m.tanggal_mutasi,
        'jumlah', m.jumlah,
        'berita', coalesce(m.berita, ''),
        'rekening_alias', coalesce(m.rekening_alias, ''),
        'rute_pengirim', coalesce(m.rute_pengirim, ''),
        'status_cocok', m.status_cocok
      ) AS baris
    FROM public.mutasi_bank m
    WHERE m.id_setoran_buku = v_id
      AND coalesce(m.berita, '') !~* '(^|[^[:alnum:]])(db|debet|debit)([^[:alnum:]]|$)'
  ) q;
  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_barang_masuk_ringkas();
CREATE OR REPLACE FUNCTION public.admin_barang_masuk_ringkas(
  p_id_setoran_buku bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_buku bigint;
  v_tgl date;
  v_sku integer := 0;
  v_nilai bigint := 0;
  v_ongkir bigint := 0;
  v_supplier jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  IF p_id_setoran_buku IS NOT NULL THEN
    SELECT b.id, b.tanggal INTO v_buku, v_tgl
    FROM public.setoran_buku b
    WHERE b.id = p_id_setoran_buku;
  ELSE
    SELECT o_buku, o_tgl INTO v_buku, v_tgl FROM public.barang_masuk_lingkup();
  END IF;

  SELECT
    count(*)::integer,
    coalesce(sum(m.nilai), 0)::bigint
  INTO v_sku, v_nilai
  FROM public.barang_masuk m
  WHERE (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
     OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl);

  SELECT coalesce(sum(o.jumlah), 0)::bigint
  INTO v_ongkir
  FROM public.ongkir o
  WHERE (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
     OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl);

  SELECT coalesce(jsonb_agg(x.obj ORDER BY lower(x.nama)), '[]'::jsonb)
  INTO v_supplier
  FROM (
    SELECT
      jsonb_build_object(
        'id', s.id,
        'nama', s.nama,
        'sku', coalesce(m.sku, 0),
        'nilai', coalesce(m.nilai, 0),
        'ongkir', coalesce(o.jumlah, 0)
      ) AS obj,
      s.nama
    FROM (
      SELECT m.id_supplier
      FROM public.barang_masuk m
      WHERE (v_buku IS NOT NULL AND m.id_setoran_buku = v_buku)
         OR (v_buku IS NULL AND m.id_setoran_buku IS NULL AND m.tanggal = v_tgl)
      UNION
      SELECT o.id_supplier
      FROM public.ongkir o
      WHERE (v_buku IS NOT NULL AND o.id_setoran_buku = v_buku)
         OR (v_buku IS NULL AND o.id_setoran_buku IS NULL AND o.tanggal = v_tgl)
    ) ids
    JOIN public.supplier s ON s.id = ids.id_supplier
    LEFT JOIN LATERAL (
      SELECT
        count(*)::integer AS sku,
        coalesce(sum(mm.nilai), 0)::bigint AS nilai
      FROM public.barang_masuk mm
      WHERE mm.id_supplier = s.id
        AND (
          (v_buku IS NOT NULL AND mm.id_setoran_buku = v_buku)
          OR (v_buku IS NULL AND mm.id_setoran_buku IS NULL AND mm.tanggal = v_tgl)
        )
    ) m ON true
    LEFT JOIN LATERAL (
      SELECT oo.jumlah
      FROM public.ongkir oo
      WHERE oo.id_supplier = s.id
        AND (
          (v_buku IS NOT NULL AND oo.id_setoran_buku = v_buku)
          OR (v_buku IS NULL AND oo.id_setoran_buku IS NULL AND oo.tanggal = v_tgl)
        )
    ) o ON true
  ) x;

  RETURN jsonb_build_object(
    'ada_buku', v_buku IS NOT NULL,
    'id_setoran_buku', v_buku,
    'tanggal', v_tgl,
    'sku', v_sku,
    'nilai', v_nilai,
    'ongkir', v_ongkir,
    'supplier', v_supplier
  );
END;
$$;


DROP FUNCTION IF EXISTS public.admin_setoran_rinci(text, text);
CREATE OR REPLACE FUNCTION public.admin_setoran_rinci(
  p_jenis text,
  p_rute text DEFAULT NULL,
  p_id_setoran_buku bigint DEFAULT NULL
)
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
  v_jenis text;
  v_rute text;
  v_toko jsonb;
  v_total bigint;
  v_tutup boolean;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;

  v_jenis := lower(btrim(coalesce(p_jenis, '')));
  IF v_jenis NOT IN ('kiriman', 'batal', 'pending', 'actual', 'retur') THEN
    RAISE EXCEPTION 'Jenis rincian tidak dikenal.';
  END IF;

  v_rute := nullif(btrim(coalesce(p_rute, '')), '');
  IF v_rute IS NOT NULL AND lower(v_rute) IN ('jumlah', 'semua') THEN
    v_rute := NULL;
  END IF;

  SELECT x.id, x.tanggal, x.ditutup
  INTO v_id, v_tgl, v_tutup
  FROM public.admin_buku_lihat(p_id_setoran_buku) x;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object(
      'jenis', v_jenis,
      'rute', v_rute,
      'tanggal', NULL,
      'total', 0,
      'toko', '[]'::jsonb
    );
  END IF;

  IF v_jenis IN ('kiriman', 'batal', 'pending', 'actual') THEN
    WITH nota AS (
      SELECT
        t.id_transaksi,
        t.id_pelanggan,
        t.nama_pelanggan,
        t.status,
        t.pending,
        rp.rute_pengirim
      FROM public.transaksi t
      JOIN public.rute_peta rp ON rp.rute_sales = t.rute
      WHERE t.waktu_packed IS NOT NULL
        AND (v_rute IS NULL OR rp.rute_pengirim = v_rute)
        AND public.admin_transaksi_ikut_buku(
          v_id, v_tgl, v_tutup, t.id_setoran_buku, t.status, t.waktu_actual
        )
        AND (
          v_jenis = 'kiriman'
          OR (v_jenis = 'batal' AND t.status = 'batal')
          OR (v_jenis = 'pending' AND t.pending)
          OR (v_jenis = 'actual' AND t.status = 'terkirim')
        )
    ),
    omset AS (
      SELECT
        n.id_transaksi,
        n.id_pelanggan,
        n.nama_pelanggan,
        n.status,
        n.pending,
        n.rute_pengirim,
        coalesce(sum(i.subtotal_jual_packed), 0)::bigint AS jual_packed,
        coalesce(sum(i.subtotal_jual_actual), 0)::bigint AS jual_actual
      FROM nota n
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
      GROUP BY
        n.id_transaksi, n.id_pelanggan, n.nama_pelanggan,
        n.status, n.pending, n.rute_pengirim
    ),
    sku AS (
      SELECT
        n.id_pelanggan,
        n.rute_pengirim,
        i.id_barang,
        max(i.nama_barang) AS nama_barang,
        sum(coalesce(i.qty_packed, 0))::integer AS qty,
        sum(coalesce(i.subtotal_jual_packed, 0))::bigint AS nilai
      FROM nota n
      JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
      WHERE coalesce(i.qty_packed, 0) > 0
      GROUP BY n.id_pelanggan, n.rute_pengirim, i.id_barang
    ),
    sku_toko AS (
      SELECT
        s.id_pelanggan,
        s.rute_pengirim,
        jsonb_agg(
          jsonb_build_object(
            'id_barang', s.id_barang,
            'nama', s.nama_barang,
            'qty', s.qty,
            'nilai', s.nilai
          )
          ORDER BY s.id_barang
        ) AS sku
      FROM sku s
      GROUP BY s.id_pelanggan, s.rute_pengirim
    ),
    sku_nota AS (
      SELECT
        x.id_transaksi,
        jsonb_agg(x.sku ORDER BY x.sku->>'id_barang') AS sku
      FROM (
        SELECT
          n.id_transaksi,
          jsonb_build_object(
            'id_barang', i.id_barang,
            'nama', max(i.nama_barang),
            'qty', sum(coalesce(i.qty_packed, 0))::integer,
            'nilai', sum(coalesce(i.subtotal_jual_packed, 0))::bigint,
            'qty_packed', sum(coalesce(i.qty_packed, 0))::integer,
            'packed', sum(coalesce(i.subtotal_jual_packed, 0))::bigint,
            'qty_batal', sum(
              CASE
                WHEN o.status = 'batal' THEN coalesce(i.qty_packed, 0)
                WHEN o.status = 'terkirim'
                  THEN greatest(
                    coalesce(i.qty_packed, 0) - coalesce(i.qty_actual, 0),
                    0
                  )
                ELSE 0
              END
            )::integer,
            'batal', sum(
              CASE
                WHEN o.status = 'batal' THEN coalesce(i.subtotal_jual_packed, 0)
                WHEN o.status = 'terkirim'
                  THEN greatest(
                    coalesce(i.subtotal_jual_packed, 0)
                      - coalesce(i.subtotal_jual_actual, 0),
                    0
                  )
                ELSE 0
              END
            )::bigint,
            'qty_actual', sum(coalesce(i.qty_actual, 0))::integer,
            'actual', sum(coalesce(i.subtotal_jual_actual, 0))::bigint
          ) AS sku
        FROM nota n
        JOIN omset o ON o.id_transaksi = n.id_transaksi
        JOIN public.v_transaksi_item i ON i.id_transaksi = n.id_transaksi
        WHERE coalesce(i.qty_packed, 0) > 0
        GROUP BY n.id_transaksi, i.id_barang
      ) x
      GROUP BY x.id_transaksi
    ),
    retur AS (
      SELECT
        i.id_pelanggan,
        i.rute_pengirim,
        max(coalesce(nullif(btrim(p.nama_pelanggan), ''), i.id_pelanggan)) AS nama,
        coalesce(sum(i.qty * i.harga_jual), 0)::bigint AS nilai
      FROM public.retur_toko i
      LEFT JOIN public.pelanggan p ON p.id_pelanggan = i.id_pelanggan
      WHERE i.id_setoran_buku = v_id
        AND (v_rute IS NULL OR i.rute_pengirim = v_rute)
        AND i.qty > 0
      GROUP BY i.id_pelanggan, i.rute_pengirim
    ),
    kunci AS (
      SELECT id_pelanggan, rute_pengirim FROM omset
      UNION
      SELECT id_pelanggan, rute_pengirim FROM retur
      WHERE v_jenis = 'kiriman'
    ),
    toko AS (
      SELECT
        k.id_pelanggan,
        coalesce(
          nullif(max(o.nama_pelanggan), ''),
          nullif(max(r.nama), ''),
          k.id_pelanggan
        ) AS nama,
        k.rute_pengirim,
        count(DISTINCT o.id_transaksi)::integer AS n_nota,
        coalesce(sum(o.jual_packed), 0)::bigint AS jual_packed,
        coalesce(sum(
          CASE
            WHEN o.status = 'batal' THEN o.jual_packed
            WHEN o.status = 'terkirim'
              THEN greatest(o.jual_packed - o.jual_actual, 0)
            ELSE 0
          END
        ), 0)::bigint AS jual_batal,
        coalesce(sum(
          CASE WHEN o.pending THEN o.jual_packed ELSE 0 END
        ), 0)::bigint AS jual_pending,
        coalesce(max(r.nilai), 0)::bigint AS jual_retur,
        coalesce(sum(o.jual_actual), 0)::bigint AS jual_actual,
        CASE
          WHEN bool_or(o.status = 'dikirim') THEN 'dikirim'
          WHEN bool_or(o.pending) THEN 'pending'
          WHEN bool_or(o.status = 'terkirim') THEN 'terkirim'
          WHEN bool_or(o.status = 'batal') THEN 'batal'
          ELSE '-'
        END AS status,
        coalesce(s.sku, '[]'::jsonb) AS sku,
        coalesce(nb.nota_list, '[]'::jsonb) AS nota_list
      FROM kunci k
      LEFT JOIN omset o
        ON o.id_pelanggan = k.id_pelanggan
       AND o.rute_pengirim = k.rute_pengirim
      LEFT JOIN retur r
        ON r.id_pelanggan = k.id_pelanggan
       AND r.rute_pengirim = k.rute_pengirim
      LEFT JOIN sku_toko s
        ON s.id_pelanggan = k.id_pelanggan
       AND s.rute_pengirim = k.rute_pengirim
      LEFT JOIN (
        SELECT
          o2.id_pelanggan,
          o2.rute_pengirim,
          jsonb_agg(
            jsonb_build_object(
              'id', o2.id_transaksi,
              'rute', o2.rute_pengirim,
              'packed', o2.jual_packed,
              'batal', CASE
                WHEN o2.status = 'batal' THEN o2.jual_packed
                WHEN o2.status = 'terkirim'
                  THEN greatest(o2.jual_packed - o2.jual_actual, 0)
                ELSE 0
              END,
              'pending', CASE WHEN o2.pending THEN o2.jual_packed ELSE 0 END,
              'actual', o2.jual_actual,
              'retur', 0,
              'status', CASE
                WHEN o2.pending THEN 'pending'
                ELSE o2.status
              END,
              'sku', coalesce(sn.sku, '[]'::jsonb)
            )
            ORDER BY o2.id_transaksi
          ) AS nota_list
        FROM omset o2
        LEFT JOIN sku_nota sn ON sn.id_transaksi = o2.id_transaksi
        GROUP BY o2.id_pelanggan, o2.rute_pengirim
      ) nb
        ON nb.id_pelanggan = k.id_pelanggan
       AND nb.rute_pengirim = k.rute_pengirim
      GROUP BY k.id_pelanggan, k.rute_pengirim, s.sku, nb.nota_list
    )
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id_pelanggan', t.id_pelanggan,
            'nama', t.nama,
            'rute_pengirim', t.rute_pengirim,
            'nilai', CASE v_jenis
              WHEN 'batal' THEN t.jual_batal
              WHEN 'pending' THEN t.jual_pending
              WHEN 'actual' THEN t.jual_actual
              ELSE t.jual_packed
            END,
            'nota', t.n_nota,
            'packed', t.jual_packed,
            'batal', t.jual_batal,
            'pending', t.jual_pending,
            'actual', t.jual_actual,
            'retur', t.jual_retur,
            'status', t.status,
            'sku', t.sku,
            'nota_list', t.nota_list
          )
          ORDER BY t.nama, t.id_pelanggan
        ),
        '[]'::jsonb
      ),
      CASE v_jenis
        WHEN 'batal' THEN coalesce(sum(t.jual_batal), 0)::bigint
        WHEN 'pending' THEN coalesce(sum(t.jual_pending), 0)::bigint
        WHEN 'actual' THEN coalesce(sum(t.jual_actual), 0)::bigint
        ELSE coalesce(sum(t.jual_packed), 0)::bigint
      END
    INTO v_toko, v_total
    FROM toko t;
  ELSIF v_jenis = 'retur' THEN
    WITH baris AS (
      SELECT
        i.id_pelanggan,
        coalesce(nullif(btrim(p.nama_pelanggan), ''), i.id_pelanggan) AS nama,
        i.rute_pengirim,
        i.kode_barang AS id_barang,
        coalesce(nullif(btrim(i.nama_barang), ''), i.kode_barang) AS nama_barang,
        i.qty::integer AS qty,
        (i.qty * i.harga_jual)::bigint AS nilai
      FROM public.retur_toko i
      LEFT JOIN public.pelanggan p ON p.id_pelanggan = i.id_pelanggan
      WHERE i.id_setoran_buku = v_id
        AND (v_rute IS NULL OR i.rute_pengirim = v_rute)
        AND i.qty > 0
    ),
    toko AS (
      SELECT
        b.id_pelanggan,
        max(b.nama) AS nama,
        b.rute_pengirim,
        coalesce(sum(b.nilai), 0)::bigint AS nilai,
        jsonb_agg(
          jsonb_build_object(
            'id_barang', b.id_barang,
            'nama', b.nama_barang,
            'qty', b.qty,
            'nilai', b.nilai,
            'qty_packed', 0,
            'packed', 0,
            'qty_batal', 0,
            'batal', 0,
            'qty_actual', 0,
            'actual', 0,
            'qty_retur', b.qty,
            'retur', b.nilai
          )
          ORDER BY b.id_barang
        ) AS sku
      FROM baris b
      GROUP BY b.id_pelanggan, b.rute_pengirim
    )
    SELECT
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id_pelanggan', t.id_pelanggan,
            'nama', t.nama,
            'rute_pengirim', t.rute_pengirim,
            'nilai', t.nilai,
            'nota', 1,
            'packed', 0,
            'batal', 0,
            'pending', 0,
            'actual', 0,
            'retur', t.nilai,
            'status', 'retur',
            'sku', t.sku,
            'nota_list', jsonb_build_array(
              jsonb_build_object(
                'id', 'Retur',
                'rute', t.rute_pengirim,
                'packed', 0,
                'batal', 0,
                'pending', 0,
                'actual', 0,
                'retur', t.nilai,
                'status', 'retur',
                'sku', t.sku
              )
            )
          )
          ORDER BY t.nama, t.id_pelanggan
        ),
        '[]'::jsonb
      ),
      coalesce(sum(t.nilai), 0)::bigint
    INTO v_toko, v_total
    FROM toko t;
  END IF;

  RETURN jsonb_build_object(
    'jenis', v_jenis,
    'rute', v_rute,
    'tanggal', v_tgl,
    'total', coalesce(v_total, 0),
    'toko', coalesce(v_toko, '[]'::jsonb)
  );
END;
$$;


REVOKE ALL ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_transaksi_ikut_buku(bigint, date, boolean, bigint, text, timestamptz)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_rinci(text, text, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_rinci(text, text, bigint)
  TO authenticated, postgres, service_role;

REVOKE ALL ON FUNCTION public.admin_buku_lihat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_buku_lihat(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_buku_daftar() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_buku_daftar()
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_kartu_hidup(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu_hidup(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_kartu(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_kartu(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_setoran_simpan(bigint, jsonb, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_setoran_simpan(bigint, jsonb, jsonb, jsonb)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_opname_ringkas(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_opname_ringkas(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_absensi_buku(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_absensi_buku(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_mutasi_lihat(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_lihat(bigint)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_barang_masuk_ringkas(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_barang_masuk_ringkas(bigint)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
