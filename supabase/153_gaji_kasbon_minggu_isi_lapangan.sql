-- Kasbon minggu = jumlah per ID buku, bukan filter tanggal setor.
-- Buku: setelah Sabtu minggu lalu sampai Senin minggu depan (12-10 → 25–30).
-- D=kasbon_supir, H=kasbon_kenek. + public.kasbon di buku yang sama.
-- Isi ulang gaji_kasbon_minggu. Jalankan SETELAH 152. Boleh diulang.

DROP FUNCTION IF EXISTS public.gaji_kasbon_id_buku(date);

CREATE FUNCTION public.gaji_kasbon_id_buku(p_senin date)
RETURNS TABLE (id bigint)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_sebelum bigint := 0;
  v_sampai bigint := 0;
BEGIN
  IF p_senin IS NULL THEN
    RETURN;
  END IF;
  SELECT max(b.id) INTO v_sebelum
  FROM public.setoran_buku b
  WHERE b.tanggal <= (p_senin - 2);
  SELECT max(b.id) INTO v_sampai
  FROM public.setoran_buku b
  WHERE b.tanggal <= (p_senin + 7);
  RETURN QUERY
  SELECT b.id
  FROM public.setoran_buku b
  WHERE b.id > COALESCE(v_sebelum, 0)
    AND b.id <= COALESCE(v_sampai, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_kasbon_lapangan(p_email text, p_senin date)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_setor bigint := 0;
  v_opname bigint := 0;
BEGIN
  IF v_email = '' OR p_senin IS NULL THEN
    RETURN 0;
  END IF;

  SELECT coalesce(sum(
    CASE
      WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'D'
        THEN s.kasbon_supir
      WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'H'
        THEN s.kasbon_kenek
      ELSE 0
    END
  ), 0)::bigint
  INTO v_setor
  FROM public.users u
  JOIN public.setoran_pengirim s
    ON s.rute_pengirim = CASE
      WHEN length(btrim(coalesce(u.rute, ''))) > 1
        AND upper(right(btrim(u.rute), 1)) IN ('D', 'H')
        THEN left(btrim(u.rute), char_length(btrim(u.rute)) - 1)
      ELSE btrim(coalesce(u.rute, ''))
    END
  WHERE u.peran = 'pengirim'
    AND lower(btrim(u.email)) = v_email
    AND s.id_setoran_buku IN (
      SELECT b.id FROM public.gaji_kasbon_id_buku(p_senin) b
    );

  SELECT coalesce(sum(k.nilai), 0)::bigint INTO v_opname
  FROM public.kasbon k
  WHERE lower(btrim(k.email)) = v_email
    AND k.id_setoran_buku IN (
      SELECT b.id FROM public.gaji_kasbon_id_buku(p_senin) b
    );

  RETURN GREATEST(COALESCE(v_setor, 0) + COALESCE(v_opname, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_gaji_kasbon(p_senin date, p_sabtu date)
RETURNS TABLE (email text, nilai bigint)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_senin date;
BEGIN
  IF NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  v_senin := COALESCE(p_senin, p_sabtu);
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::integer) - 1);

  RETURN QUERY
  WITH buku AS (
    SELECT b.id FROM public.gaji_kasbon_id_buku(v_senin) b
  ),
  opname AS (
    SELECT
      lower(btrim(k.email)) AS email,
      sum(k.nilai)::bigint AS n
    FROM public.kasbon k
    JOIN buku b ON b.id = k.id_setoran_buku
    GROUP BY lower(btrim(k.email))
  ),
  kirim AS (
    SELECT
      lower(btrim(u.email)) AS email,
      sum(
        CASE
          WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'D'
            THEN s.kasbon_supir
          WHEN upper(right(btrim(coalesce(u.rute, '')), 1)) = 'H'
            THEN s.kasbon_kenek
          ELSE 0
        END
      )::bigint AS n
    FROM public.users u
    JOIN public.setoran_pengirim s
      ON s.rute_pengirim = CASE
        WHEN length(btrim(coalesce(u.rute, ''))) > 1
          AND upper(right(btrim(u.rute), 1)) IN ('D', 'H')
          THEN left(btrim(u.rute), char_length(btrim(u.rute)) - 1)
        ELSE btrim(coalesce(u.rute, ''))
      END
    JOIN buku bk ON bk.id = s.id_setoran_buku
    WHERE u.peran = 'pengirim'
    GROUP BY lower(btrim(u.email))
  )
  SELECT
    x.email,
    sum(x.n)::bigint
  FROM (
    SELECT k.email, k.n FROM kirim k
    UNION ALL
    SELECT o.email, o.n FROM opname o
  ) x
  GROUP BY x.email
  HAVING sum(x.n) <> 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_kasbon_orang(p_email text, p_senin date)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_lap bigint := 0;
  v_overlay bigint := 0;
BEGIN
  v_lap := public.gaji_kasbon_lapangan(v_email, p_senin);
  SELECT g.nilai INTO v_overlay
  FROM public.gaji_kasbon_minggu g
  WHERE g.senin = p_senin
    AND lower(btrim(g.email)) = v_email
    AND g.nilai > 0
  LIMIT 1;
  RETURN GREATEST(COALESCE(v_lap, 0), COALESCE(v_overlay, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_gaji_kasbon_minggu_isi(p_senin date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_senin date;
  r record;
  v_n bigint;
BEGIN
  IF current_user NOT IN ('postgres', 'supabase_admin')
     AND NOT public.admin_sedang_login() THEN
    RAISE EXCEPTION 'Hanya akun admin yang boleh masuk web ini.';
  END IF;
  IF p_senin IS NULL THEN
    RAISE EXCEPTION 'Senin minggu kosong.';
  END IF;
  v_senin := p_senin - ((EXTRACT(ISODOW FROM p_senin)::integer) - 1);

  FOR r IN
    SELECT lower(btrim(u.email)) AS email
    FROM public.users u
    WHERE u.peran IN ('pengirim', 'gudang', 'admin')
      AND nullif(btrim(u.email), '') IS NOT NULL
  LOOP
    v_n := public.gaji_kasbon_lapangan(r.email, v_senin);
    IF v_n <= 0 THEN
      DELETE FROM public.gaji_kasbon_minggu g
      WHERE g.senin = v_senin AND lower(btrim(g.email)) = r.email;
    ELSE
      INSERT INTO public.gaji_kasbon_minggu (senin, email, nilai)
      VALUES (v_senin, r.email, v_n)
      ON CONFLICT (senin, email) DO UPDATE SET
        nilai = EXCLUDED.nilai;
    END IF;
  END LOOP;
END;
$$;

DO $$
DECLARE
  d date;
BEGIN
  FOR d IN
    SELECT DISTINCT senin FROM public.gaji_kasbon_minggu
    UNION
    SELECT DATE '2026-10-12'
  LOOP
    PERFORM public.admin_gaji_kasbon_minggu_isi(d);
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.gaji_kasbon_id_buku(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_kasbon_id_buku(date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_kasbon(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon(date, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_kasbon_lapangan(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_kasbon_lapangan(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_kasbon_orang(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gaji_kasbon_orang(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.admin_gaji_kasbon_minggu_isi(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon_minggu_isi(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
