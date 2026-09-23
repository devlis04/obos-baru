-- Mutasi: berita BCA nama bulan + SBGP 02, jangan timpa yang sudah cocok.
-- Jalankan SETELAH 092. Boleh diulang.

CREATE OR REPLACE FUNCTION public.admin_mutasi_rapi_berita(p_berita text)
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

CREATE OR REPLACE FUNCTION public.admin_mutasi_bulan_angka(p_nama text)
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

CREATE OR REPLACE FUNCTION public.admin_mutasi_tanggal_setelah_rute(p_sisa text)
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
  v_bln := public.admin_mutasi_bulan_angka(a[2]);
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

CREATE OR REPLACE FUNCTION public.admin_mutasi_rute_dari_berita(
  p_berita text,
  p_tanggal date
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_teks text;
  v_n text;
  v_sisa text;
  v_tgl date;
  v_wajib date;
BEGIN
  IF p_tanggal IS NULL THEN
    RETURN NULL;
  END IF;
  v_wajib := public.admin_mutasi_tanggal_berita_wajib(p_tanggal);
  v_teks := public.admin_mutasi_rapi_berita(p_berita);
  v_n := (regexp_match(v_teks, 'SBGP\s*0*([1-4])(?!\d)'))[1];
  IF v_n IS NULL THEN
    RETURN NULL;
  END IF;
  v_sisa := regexp_replace(v_teks, '^.*?SBGP\s*0*[1-4](?!\d)', '');
  v_tgl := public.admin_mutasi_tanggal_setelah_rute(v_sisa);
  IF v_tgl IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_tgl IS NOT DISTINCT FROM v_wajib THEN
    RETURN 'SBGP0' || v_n;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_mutasi_cocokkan()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer := 0;
  r record;
  v_rute text;
  v_ada integer;
  v_id bigint;
  v_tgl date;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RETURN 0;
  END IF;
  v_id := public._mutasi_buku_kartu();
  IF v_id IS NULL THEN
    RETURN 0;
  END IF;
  SELECT b.tanggal INTO v_tgl FROM public.setoran_buku b WHERE b.id = v_id;

  FOR r IN
    SELECT m.id, m.berita, m.jumlah, m.status_cocok
    FROM public.mutasi_bank m
    WHERE m.id_setoran_buku = v_id
      AND m.status_cocok = 'tidak_cocok'
      AND COALESCE(m.berita, '') !~* '(^|[^[:alnum:]])(db|debet|debit)([^[:alnum:]]|$)'
  LOOP
    v_rute := public.admin_mutasi_rute_dari_berita(r.berita, v_tgl);
    IF v_rute IS NULL THEN
      SELECT COUNT(*)::integer
      INTO v_ada
      FROM public.setoran_pengirim s
      WHERE s.id_setoran_buku = v_id
        AND s.jumlah_transfer = r.jumlah
        AND NOT EXISTS (
          SELECT 1
          FROM public.mutasi_bank x
          WHERE x.id_setoran_buku = v_id
            AND x.id <> r.id
            AND x.rute_pengirim = s.rute_pengirim
            AND x.status_cocok IN ('cocok', 'manual')
        );
      IF v_ada = 1 THEN
        SELECT s.rute_pengirim
        INTO v_rute
        FROM public.setoran_pengirim s
        WHERE s.id_setoran_buku = v_id
          AND s.jumlah_transfer = r.jumlah
          AND NOT EXISTS (
            SELECT 1
            FROM public.mutasi_bank x
            WHERE x.id_setoran_buku = v_id
              AND x.id <> r.id
              AND x.rute_pengirim = s.rute_pengirim
              AND x.status_cocok IN ('cocok', 'manual')
          );
      ELSE
        v_rute := NULL;
      END IF;
    END IF;

    UPDATE public.mutasi_bank
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

REVOKE ALL ON FUNCTION public.admin_mutasi_rapi_berita(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_rapi_berita(text)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_mutasi_bulan_angka(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_bulan_angka(text)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_mutasi_tanggal_setelah_rute(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_tanggal_setelah_rute(text)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_mutasi_rute_dari_berita(text, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_mutasi_rute_dari_berita(text, date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_rute_dari_berita(text, date)
  TO postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_mutasi_cocokkan() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_mutasi_cocokkan() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_mutasi_cocokkan()
  TO postgres, service_role;

NOTIFY pgrst, 'reload schema';
