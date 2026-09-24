-- Geser buku terbuka mundur ke hari kerja berikutnya setelah buku tutup terakhir.
-- 22 tutup + 24 terbuka → 24 menjadi 23. Tidak membuat baris baru.
-- Gagal jika tanggal tujuan sudah dipakai buku lain. Jalankan SETELAH 102. Sekali jalan.

DO $$
DECLARE
  v_buka bigint;
  v_lama date;
  v_prev date;
  v_tujuan date;
  v_ada bigint;
BEGIN
  SELECT b.id, b.tanggal
  INTO v_buka, v_lama
  FROM public.setoran_buku b
  WHERE NOT b.ditutup
  ORDER BY b.id
  LIMIT 1;
  IF v_buka IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku terbuka.';
  END IF;

  SELECT max(b.tanggal)
  INTO v_prev
  FROM public.setoran_buku b
  WHERE b.ditutup;

  IF v_prev IS NULL THEN
    RAISE EXCEPTION 'Tidak ada buku tutup sebagai acuan.';
  END IF;

  v_tujuan := public.hari_buku_berikut(v_prev);
  IF v_lama IS NOT DISTINCT FROM v_tujuan THEN
    RAISE NOTICE 'Buku terbuka sudah tanggal %.', v_tujuan;
    RETURN;
  END IF;
  IF v_lama <= v_tujuan THEN
    RAISE EXCEPTION
      'Buku terbuka tanggal % tidak lebih maju dari tujuan %.',
      v_lama, v_tujuan;
  END IF;

  SELECT b.id
  INTO v_ada
  FROM public.setoran_buku b
  WHERE b.tanggal = v_tujuan
    AND b.id IS DISTINCT FROM v_buka
  LIMIT 1;
  IF v_ada IS NOT NULL THEN
    RAISE EXCEPTION 'Sudah ada buku % tanggal %.', v_ada, v_tujuan;
  END IF;

  UPDATE public.setoran_buku
  SET tanggal = v_tujuan
  WHERE id = v_buka;
  UPDATE public.stok_opname
  SET tanggal = v_tujuan
  WHERE id_setoran_buku = v_buka;

  RAISE NOTICE 'Buku % tanggal % → %.', v_buka, v_lama, v_tujuan;
END;
$$;
