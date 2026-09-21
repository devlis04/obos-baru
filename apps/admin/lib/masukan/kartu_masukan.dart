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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
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
                        minimumSize: const Size(0, 32),
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
            const SizedBox(height: 8),
            if (data.supplier.isEmpty)
              Text(
                'Belum ada data.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              )
            else
              for (final s in data.supplier)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SizedBox(
                    height: 28,
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
                                border: Border.all(
                                  color: Tema.seed,
                                  width: 1.2,
                                ),
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
                ),
            const SizedBox(height: 6),
            _rekap('Total', data.nilai),
            _rekap('Ongkir belanja', data.ongkir),
          ],
        ),
      ),
    );
  }

  Widget _rekap(String label, int n) {
    return SizedBox(
      height: 22,
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
