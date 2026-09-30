-- Kasbon gaji per orang untuk minggu Senin–Sabtu.
-- Pengirim: kasbon_supir (rute D) / kasbon_kenek (rute H) di setoran.
-- Semua peran: kasbon opname (public.kasbon).
-- Jalankan SETELAH 116. Boleh diulang.

DROP FUNCTION IF EXISTS public.admin_gaji_kasbon(date, date);
CREATE FUNCTION public.admin_gaji_kasbon(p_senin date, p_sabtu date)
RETURNS TABLE (email text, nilai bigint)
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
  WITH buku AS (
    SELECT b.id
    FROM public.setoran_buku b
    WHERE b.tanggal >= p_senin
      AND b.tanggal <= p_sabtu
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
    JOIN buku b ON b.id = s.id_setoran_buku
    WHERE u.peran = 'pengirim'
    GROUP BY lower(btrim(u.email))
  )
  SELECT
    x.email,
    sum(x.n)::bigint
  FROM (
    SELECT o.email, o.n FROM opname o
    UNION ALL
    SELECT k.email, k.n FROM kirim k
  ) x
  GROUP BY x.email
  HAVING sum(x.n) <> 0;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gaji_kasbon(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_gaji_kasbon(date, date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
