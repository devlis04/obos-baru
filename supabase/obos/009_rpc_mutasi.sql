-- RPC mutasi bank: unggah, cocok rute, lihat, hapus.
-- Jalankan SETELAH 008. Uji SQL Editor (postgres). Tidak cek sesi HP.
-- Berita BCA nama bulan + SBGP 02. Jangan timpa yang sudah cocok.
-- public/app tidak diubah. Boleh diulang.

CREATE OR REPLACE FUNCTION obos.mutasi_buku(p_id_buku bigint DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF p_id_buku IS NOT NULL THEN
    SELECT b.id INTO v_id FROM obos.setoran_buku b WHERE b.id = p_id_buku;
    RETURN v_id;
  END IF;
  v_id := obos.buku_terbuka();
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;
  SELECT b.id INTO v_id FROM obos.setoran_buku b ORDER BY b.id DESC LIMIT 1;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_rapi_berita(p_berita text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(
    replace(replace(replace(replace(replace(replace(replace(replace(replace(
      upper(btrim(regexp_replace(coalesce(p_berita, ''), '\s+', ' ', 'g'))),
      'JANU ARI', 'JANUARI'),
      'FEBRU ARI', 'FEBRUARI'),
      'SEPTEM BER', 'SEPTEMBER'),
      'SEPTEMBE R', 'SEPTEMBER'),
      'SEPTEMB ER', 'SEPTEMBER'),
      'OKTO BER', 'OKTOBER'),
      'OKTOBE R', 'OKTOBER'),
      'NOVEM BER', 'NOVEMBER'),
      'DESEM BER', 'DESEMBER'),
    'AGUS TUS', 'AGUSTUS'
  );
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_bulan_angka(p_nama text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE upper(btrim(coalesce(p_nama, '')))
    WHEN 'JAN' THEN 1 WHEN 'JANUARI' THEN 1
    WHEN 'FEB' THEN 2 WHEN 'FEBRUARI' THEN 2
    WHEN 'MAR' THEN 3 WHEN 'MARET' THEN 3
    WHEN 'APR' THEN 4 WHEN 'APRIL' THEN 4
    WHEN 'MEI' THEN 5 WHEN 'MAY' THEN 5
    WHEN 'JUN' THEN 6 WHEN 'JUNI' THEN 6
    WHEN 'JUL' THEN 7 WHEN 'JULI' THEN 7
    WHEN 'AGU' THEN 8 WHEN 'AGS' THEN 8 WHEN 'AGT' THEN 8
    WHEN 'AUG' THEN 8 WHEN 'AGUSTUS' THEN 8
    WHEN 'SEP' THEN 9 WHEN 'SEPT' THEN 9 WHEN 'SEPTEMBER' THEN 9
    WHEN 'OKT' THEN 10 WHEN 'OCT' THEN 10 WHEN 'OKTOBER' THEN 10
    WHEN 'NOV' THEN 11 WHEN 'NOVEMBER' THEN 11
    WHEN 'DES' THEN 12 WHEN 'DEC' THEN 12 WHEN 'DESEMBER' THEN 12
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_tanggal_setelah_rute(p_sisa text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  t text;
  a text[];
  v_bln integer;
  v_th integer;
BEGIN
  t := btrim(coalesce(p_sisa, ''));
  t := regexp_replace(t, '^[\s,./\-]+', '');
  IF t = '' THEN
    RETURN NULL;
  END IF;

  a := regexp_match(t, '^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})');
  IF a IS NOT NULL THEN
    v_th := a[3]::integer;
    IF v_th < 100 THEN
      v_th := v_th + 2000;
    END IF;
    BEGIN
      RETURN make_date(v_th, a[2]::integer, a[1]::integer);
    EXCEPTION
      WHEN others THEN
        RETURN NULL;
    END;
  END IF;

  a := regexp_match(
    t,
    '^(\d{1,2})\s+(JANUARI|FEBRUARI|MARET|APRIL|MEI|JUNI|JULI|AGUSTUS|'
    'SEPTEMBER|OKTOBER|NOVEMBER|DESEMBER|JAN|FEB|MAR|APR|MAY|JUN|JUL|'
    'AGU|AGS|AGT|AUG|SEP|SEPT|OKT|OCT|NOV|DES|DEC)\s+(\d{2,4})'
  );
  IF a IS NULL THEN
    RETURN NULL;
  END IF;
  v_bln := obos.mutasi_bulan_angka(a[2]);
  IF v_bln IS NULL THEN
    RETURN NULL;
  END IF;
  v_th := a[3]::integer;
  IF v_th < 100 THEN
    v_th := v_th + 2000;
  END IF;
  BEGIN
    RETURN make_date(v_th, v_bln, a[1]::integer);
  EXCEPTION
    WHEN others THEN
      RETURN NULL;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_tanggal_berita_wajib(p_judul date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN EXTRACT(ISODOW FROM (p_judul + 1))::integer = 7 THEN p_judul + 2
    ELSE p_judul + 1
  END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_rute_dari_berita(p_berita text, p_tanggal date)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_teks text;
  v_n text;
  v_sisa text;
  v_tgl date;
  v_wajib date;
  v_rute text;
BEGIN
  IF p_tanggal IS NULL THEN
    RETURN NULL;
  END IF;
  v_wajib := obos.mutasi_tanggal_berita_wajib(p_tanggal);
  v_teks := obos.mutasi_rapi_berita(p_berita);
  v_n := (regexp_match(v_teks, 'SBGP\s*0*([1-4])(?!\d)'))[1];
  IF v_n IS NULL THEN
    RETURN NULL;
  END IF;
  v_sisa := regexp_replace(v_teks, '^.*?SBGP\s*0*[1-4](?!\d)', '');
  v_tgl := obos.mutasi_tanggal_setelah_rute(v_sisa);
  IF v_tgl IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_tgl IS DISTINCT FROM v_wajib THEN
    RETURN NULL;
  END IF;
  v_rute := 'SBGP0' || v_n;
  IF NOT EXISTS (
    SELECT 1 FROM obos.rute_peta rp WHERE rp.rute_pengirim = v_rute
  ) THEN
    RETURN NULL;
  END IF;
  RETURN v_rute;
END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_cocokkan(p_id_buku bigint DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_n integer := 0;
  r record;
  v_rute text;
  v_ada integer;
  v_id bigint;
  v_tgl date;
BEGIN
  v_id := obos.mutasi_buku(p_id_buku);
  IF v_id IS NULL THEN
    RETURN 0;
  END IF;
  SELECT b.tanggal INTO v_tgl FROM obos.setoran_buku b WHERE b.id = v_id;

  FOR r IN
    SELECT m.id, m.berita, m.jumlah
    FROM obos.mutasi_bank m
    WHERE m.id_setoran_buku = v_id
      AND m.status_cocok = 'tidak_cocok'
      AND COALESCE(m.berita, '') !~* '(^|[^[:alnum:]])(db|debet|debit)([^[:alnum:]]|$)'
  LOOP
    v_rute := obos.mutasi_rute_dari_berita(r.berita, v_tgl);
    IF v_rute IS NULL THEN
      SELECT COUNT(*)::integer INTO v_ada
      FROM obos.setoran_pengirim s
      WHERE s.id_setoran_buku = v_id
        AND s.jumlah_transfer = r.jumlah
        AND NOT EXISTS (
          SELECT 1 FROM obos.mutasi_bank x
          WHERE x.id_setoran_buku = v_id
            AND x.id <> r.id
            AND x.rute_pengirim = s.rute_pengirim
            AND x.status_cocok IN ('cocok', 'manual')
        );
      IF v_ada = 1 THEN
        SELECT s.rute_pengirim INTO v_rute
        FROM obos.setoran_pengirim s
        WHERE s.id_setoran_buku = v_id
          AND s.jumlah_transfer = r.jumlah
          AND NOT EXISTS (
            SELECT 1 FROM obos.mutasi_bank x
            WHERE x.id_setoran_buku = v_id
              AND x.id <> r.id
              AND x.rute_pengirim = s.rute_pengirim
              AND x.status_cocok IN ('cocok', 'manual')
          );
      ELSE
        v_rute := NULL;
      END IF;
    END IF;

    UPDATE obos.mutasi_bank
    SET
      rute_pengirim = v_rute,
      status_cocok = CASE WHEN v_rute IS NULL THEN 'tidak_cocok' ELSE 'cocok' END
    WHERE id = r.id
      AND (
        rute_pengirim IS DISTINCT FROM v_rute
        OR status_cocok IS DISTINCT FROM CASE
          WHEN v_rute IS NULL THEN 'tidak_cocok'
          ELSE 'cocok'
        END
      );
    IF FOUND THEN
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_unggah(
  p_nama_berkas text,
  p_baris jsonb,
  p_id_buku bigint DEFAULT NULL,
  p_dicatat_oleh text DEFAULT ''
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_n integer := 0;
  r jsonb;
  v_jumlah integer;
  v_berita text;
  v_rek text;
  v_tgl date;
  v_rute text;
  v_id bigint;
  v_tgl_buku date;
  v_tutup boolean;
BEGIN
  v_id := obos.mutasi_buku(p_id_buku);
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku setoran. Mutasi tidak dicatat.';
  END IF;
  SELECT b.tanggal, b.ditutup INTO v_tgl_buku, v_tutup
  FROM obos.setoran_buku b
  WHERE b.id = v_id;
  IF COALESCE(v_tutup, false) THEN
    RAISE EXCEPTION 'Buku sudah ditutup. Mutasi tidak diubah.';
  END IF;
  IF p_baris IS NULL OR jsonb_typeof(p_baris) <> 'array' THEN
    RAISE EXCEPTION 'Daftar mutasi wajib.';
  END IF;
  IF jsonb_array_length(p_baris) = 0 OR jsonb_array_length(p_baris) > 2000 THEN
    RETURN 0;
  END IF;

  PERFORM pg_advisory_xact_lock(88221940);

  FOR r IN SELECT value FROM jsonb_array_elements(p_baris)
  LOOP
    v_jumlah := GREATEST(COALESCE((r ->> 'jumlah')::integer, 0), 0);
    IF v_jumlah <= 0 THEN
      CONTINUE;
    END IF;
    v_berita := nullif(btrim(COALESCE(r ->> 'berita', '')), '');
    v_rek := nullif(btrim(COALESCE(r ->> 'rekening', r ->> 'rekening_alias', '')), '');
    v_tgl := NULL;
    BEGIN
      v_tgl := NULLIF(btrim(COALESCE(r ->> 'tanggal_mutasi', '')), '')::date;
    EXCEPTION
      WHEN others THEN
        v_tgl := NULL;
    END;
    v_rute := obos.grup_rute(COALESCE(r ->> 'rute_pengirim', ''));
    IF v_rute = '' THEN
      v_rute := NULL;
    END IF;
    IF v_rute IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM obos.rute_peta rp WHERE rp.rute_pengirim = v_rute
    ) THEN
      v_rute := NULL;
    END IF;

    INSERT INTO obos.mutasi_bank (
      id_setoran_buku, tanggal, tanggal_mutasi, rekening_alias,
      jumlah, berita, rute_pengirim, status_cocok, nama_berkas, dicatat_oleh
    )
    VALUES (
      v_id, v_tgl_buku, v_tgl, v_rek,
      v_jumlah, v_berita, v_rute,
      CASE WHEN v_rute IS NULL THEN 'tidak_cocok' ELSE 'cocok' END,
      nullif(btrim(COALESCE(p_nama_berkas, '')), ''),
      nullif(btrim(COALESCE(p_dicatat_oleh, '')), '')
    );
    v_n := v_n + 1;
  END LOOP;

  PERFORM obos.mutasi_cocokkan(v_id);
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_lihat(p_id_buku bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_id bigint;
  v_baris jsonb;
BEGIN
  v_id := obos.mutasi_buku(p_id_buku);
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
    FROM obos.mutasi_bank m
    WHERE m.id_setoran_buku = v_id
      AND coalesce(m.berita, '') !~* '(^|[^[:alnum:]])(db|debet|debit)([^[:alnum:]]|$)'
  ) q;
  RETURN coalesce(v_baris, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION obos.mutasi_hapus(p_id_buku bigint DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SET search_path = obos
AS $$
DECLARE
  v_n integer := 0;
  v_id bigint;
  v_tutup boolean;
BEGIN
  v_id := obos.mutasi_buku(p_id_buku);
  IF v_id IS NULL THEN
    RETURN 0;
  END IF;
  SELECT b.ditutup INTO v_tutup FROM obos.setoran_buku b WHERE b.id = v_id;
  IF COALESCE(v_tutup, false) THEN
    RAISE EXCEPTION 'Buku sudah ditutup. Mutasi tidak diubah.';
  END IF;
  DELETE FROM obos.mutasi_bank WHERE id_setoran_buku = v_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
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
        'mutasi_buku', 'mutasi_rapi_berita', 'mutasi_bulan_angka',
        'mutasi_tanggal_setelah_rute', 'mutasi_tanggal_berita_wajib',
        'mutasi_rute_dari_berita', 'mutasi_cocokkan',
        'mutasi_unggah', 'mutasi_lihat', 'mutasi_hapus'
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
