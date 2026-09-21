import 'package:flutter/material.dart';

import '../uang.dart';
import 'mutasi_repo.dart';

class KartuMutasi extends StatelessWidget {
  const KartuMutasi({
    super.key,
    required this.sibuk,
    required this.ditutup,
    required this.judulHari,
    this.onUnggah,
    this.onHapus,
  });

  final bool sibuk;
  final bool ditutup;
  final String judulHari;
  final VoidCallback? onUnggah;
  final VoidCallback? onHapus;

  static const _garis = Color(0xFF8FB4D9);
  static const _teks = 14.0;
  static const _judul = TextStyle(
    fontSize: _teks,
    height: 1.15,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );
  static const _isi = TextStyle(
    fontSize: _teks,
    height: 1.15,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MutasiSetoran.instance,
      builder: (context, _) {
        final daftar = [...MutasiSetoran.instance.daftar]..sort((a, b) {
            final ia = a.terikat ? 1 : 0;
            final ib = b.terikat ? 1 : 0;
            if (ia != ib) return ia - ib;
            return b.jumlah.compareTo(a.jumlah);
          });
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(1.15),
                            1: FlexColumnWidth(1.35),
                            2: FlexColumnWidth(1.1),
                            3: FlexColumnWidth(1.15),
                            4: FlexColumnWidth(1.25),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          border: const TableBorder(
                            verticalInside:
                                BorderSide(color: _garis, width: 1),
                          ),
                          children: [
                            TableRow(
                              children: [
                                _sel(const Text('Tanggal', style: _judul),
                                    tengah: true),
                                _sel(const Text('Jumlah', style: _judul),
                                    tengah: true),
                                _sel(const Text('Rekening', style: _judul),
                                    tengah: true),
                                _sel(const Text('Rute', style: _judul),
                                    tengah: true),
                                _sel(const Text('Status', style: _judul),
                                    tengah: true),
                              ],
                            ),
                            for (final m in daftar) _baris(m),
                          ],
                        ),
                        if (daftar.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                'Belum ada mutasi.',
                                style: TextStyle(
                                  fontSize: _teks,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton.icon(
                          onPressed: sibuk || ditutup ? null : onUnggah,
                          icon: const Icon(Icons.upload_file_outlined, size: 18),
                          label: const Text(
                            'Unggah mutasi CSV',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 32),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton(
                          onPressed: sibuk ||
                                  ditutup ||
                                  daftar.isEmpty ||
                                  onHapus == null
                              ? null
                              : () => _konfirmasiHapus(context),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 32),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text(
                            'Hapus mutasi buku ini',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _konfirmasiHapus(BuildContext context) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Hapus mutasi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          judulHari.isEmpty
              ? 'Buang semua mutasi buku ini?'
              : 'Buang semua mutasi $judulHari?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ya == true) onHapus?.call();
  }

  TableRow _baris(IsiMutasi m) {
    final teksStatus = m.terikat ? 'Cocok ${m.rute}' : 'Belum diikat';
    final rek = m.rekening.trim();
    return TableRow(
      children: [
        _sel(Text(m.tanggalMutasi ?? '-', style: _isi)),
        _sel(_uang(m.jumlah)),
        _sel(
          Tooltip(
            message: m.berita.trim().isEmpty ? 'Rekening' : m.berita.trim(),
            child: Text(
              rek.isEmpty ? '-' : rek,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _isi,
            ),
          ),
        ),
        _sel(
          Text(
            m.terikat ? m.rute : '-',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _isi,
          ),
          tengah: true,
        ),
        _sel(
          Text(
            teksStatus,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _teks,
              fontWeight: FontWeight.bold,
              color: m.terikat ? Colors.green.shade700 : Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _uang(int n) {
    return Row(
      children: [
        const SizedBox(width: 22, child: Text('Rp', style: _isi)),
        Expanded(
          child: Text(
            Uang.angka(n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: _isi,
          ),
        ),
      ],
    );
  }

  Widget _sel(Widget child, {bool tengah = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Align(
        alignment: tengah ? Alignment.center : Alignment.centerLeft,
        child: child,
      ),
    );
  }
}
