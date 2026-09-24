-- Tanggal buku berikutnya = hari kerja berikutnya (Sabtu → Senin), sama public 102.
-- Buku terbuka tidak digeser ke hari ini. Jangan 001. Jalankan SETELAH 016. Lalu ulang 004.
-- Boleh diulang.

CREATE OR REPLACE FUNCTION obos.hari_buku_berikut(p_tanggal date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE EXTRACT(ISODOW FROM p_tanggal)::integer
    WHEN 6 THEN p_tanggal + 2
    WHEN 7 THEN p_tanggal + 1
    ELSE p_tanggal + 1
  END;
$$;

CREATE OR REPLACE FUNCTION obos.tanggal_buku_baru()
RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path = obos
AS $$
DECLARE
  v_last date;
  v_today date;
BEGIN
  v_today := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  SELECT b.tanggal
  INTO v_last
  FROM obos.setoran_buku b
  ORDER BY b.tanggal DESC NULLS LAST, b.id DESC
  LIMIT 1;
  IF v_last IS NULL THEN
    IF EXTRACT(ISODOW FROM v_today)::integer = 7 THEN
      RETURN v_today + 1;
    END IF;
    RETURN v_today;
  END IF;
  RETURN obos.hari_buku_berikut(v_last);
END;
$$;
