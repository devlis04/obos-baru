import 'dart:async';

import 'package:flutter/material.dart';

import 'package:obos_core/obos_core.dart';

import '../jaringan.dart';
import '../masukan/masukan_csv.dart';
import '../pesan.dart';
import 'barang.dart';
import 'barang_csv.dart';
import 'barang_repo.dart';

class BarangCsvDialog {
  static Future<void> buka({
    required BuildContext context,
    required BarangRepo repo,
    required VoidCallback onSelesai,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _Isi(repo: repo, onSelesai: onSelesai),
    );
  }
}

class _Isi extends StatefulWidget {
  const _Isi({required this.repo, required this.onSelesai});

  final BarangRepo repo;
  final VoidCallback onSelesai;

  @override
  State<_Isi> createState() => _IsiState();
}

class _IsiState extends State<_Isi> {
  bool _proses = false;
  List<Barang>? _semua;
  String? _galat;

  ButtonStyle get _isi => FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  ButtonStyle get _garis => OutlinedButton.styleFrom(
        foregroundColor: Tema.biru,
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_muatSemua());
  }

  Future<void> _muatSemua() async {
    try {
      final list = await widget.repo.semua();
      if (!mounted) return;
      setState(() {
        _semua = list;
        _galat = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _galat = Jaringan.mati(e)
            ? 'Tidak ada internet. Data CSV belum bisa dimuat.'
            : pesanGagal(e, 'Data CSV belum bisa dimuat.'),
      );
    }
  }

  Future<void> _unduhBarang() async {
    final list = _semua;
    if (list == null) {
      setState(() => _galat = 'Data masih dimuat. Coba lagi sebentar.');
      return;
    }
    try {
      unduhBerkasCsv('barang.csv', BarangCsv.dariBarang(list));
      if (!mounted) return;
      tampilPesan(context, 'CSV barang diunduh.');
    } catch (e) {
      if (mounted) {
        setState(() => _galat = pesanGagal(e, 'CSV barang belum terunduh.'));
      }
    }
  }

  Future<void> _unduhStok() async {
    final list = _semua;
    if (list == null) {
      setState(() => _galat = 'Data masih dimuat. Coba lagi sebentar.');
      return;
    }
    try {
      unduhBerkasCsv('barang_stok.csv', BarangCsv.dariStok(list));
      if (!mounted) return;
      tampilPesan(context, 'CSV stok diunduh.');
    } catch (e) {
      if (mounted) {
        setState(() => _galat = pesanGagal(e, 'CSV stok belum terunduh.'));
      }
    }
  }

  Future<void> _templateBarang() async {
    try {
      unduhBerkasCsv('template_barang.csv', BarangCsv.templateBarang());
      if (!mounted) return;
      tampilPesan(context, 'Template barang diunduh.');
    } catch (e) {
      if (mounted) {
        setState(() => _galat = pesanGagal(e, 'Template belum terunduh.'));
      }
    }
  }

  Future<void> _templateStok() async {
    try {
      unduhBerkasCsv('template_stok.csv', BarangCsv.templateStok());
      if (!mounted) return;
      tampilPesan(context, 'Template stok diunduh.');
    } catch (e) {
      if (mounted) {
        setState(() => _galat = pesanGagal(e, 'Template belum terunduh.'));
      }
    }
  }

  Future<void> _unggahBarang() async {
    final teks = await pilihBerkasCsv();
    if (teks == null || !mounted) return;
    final baris = BarangCsv.bacaBarang(teks);
    if (baris.isEmpty) {
      setState(() => _galat = 'CSV barang kosong atau tanpa id.');
      return;
    }
    setState(() => _proses = true);
    try {
      final hasil = await widget.repo.unggahBarang(baris);
      if (!mounted) return;
      await _muatSemua();
      widget.onSelesai();
      await _tampilHasil('Unggah barang', hasil);
    } catch (e) {
      if (mounted) {
        setState(() => _galat = pesanGagal(e, 'CSV barang belum terunggah.'));
      }
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  Future<void> _unggahStok() async {
    final teks = await pilihBerkasCsv();
    if (teks == null || !mounted) return;
    final baris = BarangCsv.bacaStok(teks);
    if (baris.isEmpty) {
      setState(() => _galat = 'CSV stok kosong atau tanpa id.');
      return;
    }
    setState(() => _proses = true);
    try {
      final hasil = await widget.repo.unggahStok(baris);
      if (!mounted) return;
      await _muatSemua();
      widget.onSelesai();
      await _tampilHasil('Unggah stok', hasil);
    } catch (e) {
      if (mounted) {
        setState(() => _galat = pesanGagal(e, 'CSV stok belum terunggah.'));
      }
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  Future<void> _tampilHasil(String judul, List<BarisCsv> hasil) async {
    final ok = hasil.where((e) => e.ok).length;
    final gagal = hasil.length - ok;
    if (!mounted) return;
    tampilPesan(context, '$judul: $ok berhasil, $gagal gagal.');
    setState(() {
      _galat = gagal == 0 ? null : '$judul: $ok berhasil, $gagal gagal.';
    });
    if (gagal == 0) return;
    final salah = hasil.where((e) => !e.ok).take(12).toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(judul),
        content: SingleChildScrollView(
          child: Text(
            salah
                .map((e) => 'Baris ${e.baris} (${e.id}): ${e.pesan}')
                .join('\n'),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _kelompok(String judul, String ket, List<Widget> tombol) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(judul, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(ket, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: tombol),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CSV barang'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_proses || (_semua == null && _galat == null))
              const LinearProgressIndicator(minHeight: 2),
            if (_galat != null) ...[
              Text(
                _galat!,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
            ],
            _kelompok(
              'Master barang',
              'Hanya ubah id yang sudah ada: grup, nama, satuan, rincian, kategori, pemasok utama, jual, strata, aktif. SKU baru dari Barang masuk. Kolom id_supplier_utama = id supplier (kosong = tidak diubah, 0 = hapus utama). Ganti utama: modal dan jual ikut (pembulatan Rp 500). Kolom hapus = 1: hapus, atau nonaktif jika sudah dipakai nota.',
              [
                OutlinedButton(
                  style: _garis,
                  onPressed: _proses ? null : _unduhBarang,
                  child: const Text('Unduh data'),
                ),
                OutlinedButton(
                  style: _garis,
                  onPressed: _proses ? null : _templateBarang,
                  child: const Text('Unduh template'),
                ),
                FilledButton(
                  style: _isi,
                  onPressed: _proses ? null : _unggahBarang,
                  child: const Text('Unggah CSV'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _kelompok(
              'Stok',
              'Hanya ubah stok id yang sudah ada. Kolom nama hanya pembantu baca.',
              [
                OutlinedButton(
                  style: _garis,
                  onPressed: _proses ? null : _unduhStok,
                  child: const Text('Unduh data'),
                ),
                OutlinedButton(
                  style: _garis,
                  onPressed: _proses ? null : _templateStok,
                  child: const Text('Unduh template'),
                ),
                FilledButton(
                  style: _isi,
                  onPressed: _proses ? null : _unggahStok,
                  child: const Text('Unggah CSV'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _proses ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
