-- Pembagi EC/visit: pindah rute toko berlaku besok (Jakarta).
-- Minggu lalu: rute dari nota/scan minggu itu, bukan master toko hari ini.
-- Jangan UPDATE pelanggan. Jalankan SETELAH 164. Boleh diulang.

CREATE TABLE IF NOT EXISTS public.pelanggan_rute_riwayat (
  id_pelanggan text NOT NULL REFERENCES public.pelanggan (id_pelanggan),
  rute text NOT NULL,
  berlaku_dari date NOT NULL,
  PRIMARY KEY (id_pelanggan, berlaku_dari),
  CONSTRAINT pelanggan_rute_riwayat_rute_chk CHECK (btrim(rute) <> '')
);

COMMENT ON TABLE public.pelanggan_rute_riwayat IS
  'Rute toko untuk pembagi gaji. Baris baru berlaku_dari = besok Jakarta saat admin pindah jalur.';

ALTER TABLE public.pelanggan_rute_riwayat ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pelanggan_rute_riwayat FORCE ROW LEVEL SECURITY;

GRANT SELECT ON TABLE public.pelanggan_rute_riwayat
  TO authenticated, postgres, service_role;
GRANT INSERT, UPDATE, DELETE ON TABLE public.pelanggan_rute_riwayat
  TO postgres, service_role;
REVOKE ALL ON TABLE public.pelanggan_rute_riwayat FROM anon;

DROP POLICY IF EXISTS pelanggan_rute_riwayat_select ON public.pelanggan_rute_riwayat;
CREATE POLICY pelanggan_rute_riwayat_select
  ON public.pelanggan_rute_riwayat
  FOR SELECT
  TO authenticated
  USING (true);

INSERT INTO public.pelanggan_rute_riwayat (id_pelanggan, rute, berlaku_dari)
SELECT
  p.id_pelanggan,
  btrim(p.rute),
  DATE '2000-01-01'
FROM public.pelanggan p
WHERE btrim(COALESCE(p.rute, '')) <> ''
ON CONFLICT (id_pelanggan, berlaku_dari) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pelanggan_rute_riwayat_setelah_ubah()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_hari date;
  v_besok date;
  v_baru text;
BEGIN
  v_baru := btrim(COALESCE(NEW.rute, ''));
  IF TG_OP = 'UPDATE'
     AND btrim(COALESCE(OLD.rute, '')) IS NOT DISTINCT FROM v_baru THEN
    RETURN NEW;
  END IF;
  IF v_baru = '' THEN
    RETURN NEW;
  END IF;

  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_besok := v_hari + 1;

  DELETE FROM public.pelanggan_rute_riwayat
  WHERE id_pelanggan = NEW.id_pelanggan
    AND berlaku_dari > v_hari;

  INSERT INTO public.pelanggan_rute_riwayat (id_pelanggan, rute, berlaku_dari)
  VALUES (NEW.id_pelanggan, v_baru, v_besok)
  ON CONFLICT (id_pelanggan, berlaku_dari) DO UPDATE
  SET rute = EXCLUDED.rute;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pelanggan_rute_riwayat_ubah ON public.pelanggan;
CREATE TRIGGER pelanggan_rute_riwayat_ubah
  AFTER INSERT OR UPDATE OF rute ON public.pelanggan
  FOR EACH ROW
  EXECUTE FUNCTION public.pelanggan_rute_riwayat_setelah_ubah();

CREATE OR REPLACE FUNCTION public.gaji_rute_toko_pada(
  p_id_pelanggan text,
  p_tanggal date,
  p_senin date
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_id text;
  v_hari date;
  v_senin date;
  v_sabtu date;
  v_as_of date;
  v_r text;
  v_nota text;
BEGIN
  v_id := btrim(COALESCE(p_id_pelanggan, ''));
  IF v_id = '' THEN
    RETURN NULL;
  END IF;

  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_as_of := COALESCE(p_tanggal, v_hari);
  IF v_as_of > v_hari THEN
    v_as_of := v_hari;
  END IF;

  v_senin := p_senin;
  IF v_senin IS NOT NULL THEN
    v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::int) - 1);
  END IF;
  v_sabtu := CASE WHEN v_senin IS NULL THEN NULL ELSE v_senin + 5 END;

  SELECT r.rute INTO v_r
  FROM public.pelanggan_rute_riwayat r
  WHERE r.id_pelanggan = v_id
    AND r.berlaku_dari <= v_as_of
  ORDER BY r.berlaku_dari DESC
  LIMIT 1;

  IF v_r IS NULL THEN
    SELECT nullif(btrim(p.rute), '') INTO v_r
    FROM public.pelanggan p
    WHERE p.id_pelanggan = v_id;
  END IF;

  -- Minggu sudah lewat: kunci ke rute nota/scan minggu itu.
  IF v_senin IS NOT NULL AND v_sabtu IS NOT NULL AND v_sabtu < v_hari THEN
    SELECT nullif(btrim(t.rute), '') INTO v_nota
    FROM public.v_transaksi_hari_label t
    WHERE t.id_pelanggan = v_id
      AND t.hari_label >= v_senin
      AND t.hari_label <= v_sabtu
      AND btrim(COALESCE(t.rute, '')) <> ''
    ORDER BY t.hari_label DESC, t.waktu_order DESC NULLS LAST
    LIMIT 1;
    IF v_nota IS NOT NULL THEN
      RETURN v_nota;
    END IF;

    SELECT nullif(btrim(k.rute), '') INTO v_nota
    FROM public.kunjungan_sales k
    WHERE k.id_pelanggan = v_id
      AND k.tanggal >= v_senin
      AND k.tanggal <= v_sabtu
      AND btrim(COALESCE(k.rute, '')) <> ''
    ORDER BY k.tanggal DESC, k.id DESC
    LIMIT 1;
    IF v_nota IS NOT NULL THEN
      RETURN v_nota;
    END IF;
  END IF;

  -- Minggu berjalan: nota packed hari ini tetap di rute lama.
  IF v_senin IS NOT NULL
     AND v_sabtu IS NOT NULL
     AND v_hari >= v_senin
     AND v_hari <= v_sabtu THEN
    SELECT nullif(btrim(t.rute), '') INTO v_nota
    FROM public.transaksi t
    WHERE t.id_pelanggan = v_id
      AND t.waktu_packed IS NOT NULL
      AND (t.waktu_packed AT TIME ZONE 'Asia/Jakarta')::date = v_hari
      AND btrim(COALESCE(t.rute, '')) <> ''
    ORDER BY t.waktu_packed DESC NULLS LAST
    LIMIT 1;
    IF v_nota IS NOT NULL THEN
      RETURN v_nota;
    END IF;
  END IF;

  RETURN v_r;
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_n_toko_rute(p_rute text, p_senin date)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer;
  v_hari date;
  v_senin date;
  v_as_of date;
  v_kode text;
BEGIN
  v_kode := btrim(COALESCE(p_rute, ''));
  IF v_kode = '' THEN
    RETURN 0;
  END IF;

  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_senin := COALESCE(p_senin, v_hari);
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::int) - 1);
  v_as_of := LEAST(v_hari, v_senin + 5);

  IF v_senin < DATE '2026-10-12' THEN
    SELECT s.n_toko INTO v_n
    FROM public.gaji_toko_rute_snap s
    WHERE s.rute = v_kode;
    IF FOUND THEN
      RETURN GREATEST(COALESCE(v_n, 0), 0);
    END IF;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(
      public.gaji_rute_toko_pada(p.id_pelanggan, v_as_of, v_senin),
      ''
    )) = v_kode;
  RETURN GREATEST(COALESCE(v_n, 0), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.gaji_n_toko_semua(p_senin date)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_n integer;
  v_hari date;
  v_senin date;
  v_as_of date;
BEGIN
  v_hari := (timezone('Asia/Jakarta', clock_timestamp()))::date;
  v_senin := COALESCE(p_senin, v_hari);
  v_senin := v_senin - ((EXTRACT(ISODOW FROM v_senin)::int) - 1);
  v_as_of := LEAST(v_hari, v_senin + 5);

  IF v_senin < DATE '2026-10-12' THEN
    SELECT coalesce(sum(s.n_toko), 0)::integer INTO v_n
    FROM public.gaji_toko_rute_snap s
    WHERE s.rute IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );
    IF COALESCE(v_n, 0) > 0 THEN
      RETURN v_n;
    END IF;
  END IF;

  SELECT count(*)::integer INTO v_n
  FROM public.pelanggan p
  WHERE COALESCE(p.aktif, true)
    AND btrim(p.id_pelanggan) <> ''
    AND p.id_pelanggan NOT LIKE 'TMP%'
    AND btrim(COALESCE(
      public.gaji_rute_toko_pada(p.id_pelanggan, v_as_of, v_senin),
      ''
    )) IN (
      SELECT btrim(u.rute) FROM public.users u
      WHERE u.peran = 'sales' AND nullif(btrim(u.rute), '') IS NOT NULL
    );
  RETURN GREATEST(COALESCE(v_n, 0), 0);
END;
$$;

REVOKE ALL ON FUNCTION public.gaji_rute_toko_pada(text, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_rute_toko_pada(text, date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_rute_toko_pada(text, date, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_n_toko_rute(text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_n_toko_rute(text, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_n_toko_rute(text, date)
  TO authenticated, postgres, service_role;
REVOKE ALL ON FUNCTION public.gaji_n_toko_semua(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gaji_n_toko_semua(date) FROM anon;
GRANT EXECUTE ON FUNCTION public.gaji_n_toko_semua(date)
  TO authenticated, postgres, service_role;

NOTIFY pgrst, 'reload schema';
