import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import 'masukan_dialog.dart';
import 'masukan_repo.dart';

class KartuMasukan extends StatelessWidget {
  const KartuMasukan({
    super.key,
    required this.data,
    required this.sibuk,
    required this.onMuat,
    this.ditutup = false,
  });

  final RingkasMasuk data;
  final bool sibuk;
  final bool ditutup;
  final Future<void> Function() onMuat;

  static const maksSupplier = 5;
  static const tinggiTombol = 32.0;
  static const tinggiBaris = 32.0;
  static const tinggiRekap = 22.0;
  static const _padAtas = 8.0;
  static const _padBawah = 10.0;
  static const _jarakTombol = 8.0;
  static const _jarakRekap = 6.0;

  static double tinggiUntuk(int nSupplier) {
    final n = nSupplier <= 0 ? 1 : nSupplier.clamp(1, maksSupplier);
    return _padAtas +
        tinggiTombol +
        _jarakTombol +
        n * tinggiBaris +
        _jarakRekap +
        tinggiRekap * 2 +
        _padBawah;
  }

  int get _totalNilai {
    if (data.supplier.isEmpty) return data.nilai;
    final jum = data.supplier.fold<int>(0, (a, s) => a + s.nilai);
    return jum > data.nilai ? jum : data.nilai;
  }

  int get _totalOngkir {
    if (data.supplier.isEmpty) return data.ongkir;
    final jum = data.supplier.fold<int>(0, (a, s) => a + s.ongkir);
    return jum > data.ongkir ? jum : data.ongkir;
  }

  @override
  Widget build(BuildContext context) {
    final daftar = data.supplier;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, _padAtas, 10, _padBawah),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: tinggiTombol,
                    child: FilledButton(
                      onPressed: sibuk || ditutup
                          ? null
                          : () => bukaMasukan(
                                context: context,
                                onMuat: onMuat,
                                baru: true,
                              ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, tinggiTombol),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Barang masuk'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: _jarakTombol),
            Expanded(child: _daftarSupplier(daftar)),
            const SizedBox(height: _jarakRekap),
            _rekap('Total', _totalNilai),
            _rekap('Ongkir belanja', _totalOngkir),
          ],
        ),
      ),
    );
  }

  Widget _daftarSupplier(List<ChipSupplier> daftar) {
    if (daftar.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Belum ada data.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
      );
    }
    final gulir = daftar.length > maksSupplier;
    return Scrollbar(
      thumbVisibility: gulir,
      child: ListView.builder(
        primary: false,
        padding: EdgeInsets.zero,
        physics: gulir
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: daftar.length,
        itemExtent: tinggiBaris,
        itemBuilder: (context, i) => _baris(context, daftar[i]),
      ),
    );
  }

  Widget _baris(BuildContext context, ChipSupplier s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: tinggiBaris - 4,
        child: Row(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: sibuk || ditutup
                    ? null
                    : () => bukaMasukan(
                          context: context,
                          onMuat: onMuat,
                          idSupplier: s.id,
                        ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Tema.seed, width: 1.2),
                  ),
                  child: Text(
                    s.nama,
                    style: const TextStyle(
                      color: Tema.seed,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              Uang.angka(s.nilai),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rekap(String label, int n) {
    return SizedBox(
      height: tinggiRekap,
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            Uang.angka(n),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
