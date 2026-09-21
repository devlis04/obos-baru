import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import 'retur_toko.dart';

enum AksiReturToko { edit, batal }

Future<AksiReturToko?> tampilkanReturTokoSheet({
  required BuildContext context,
  required String namaToko,
  required List<BarisReturToko> baris,
}) {
  final nilai = baris.fold<int>(0, (a, b) => a + b.nilai);
  final dikunci = baris.any((b) => b.dikunci);
  return showModalBottomSheet<AksiReturToko>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Retur $namaToko',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sudah dicatat hari ini. Nilai mengurangi tagihan toko.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if (dikunci) ...[
              const SizedBox(height: 6),
              Text(
                'Sudah dikunci. Tidak bisa diubah.',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: baris.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final b = baris[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      b.nama.isEmpty ? b.kode : b.nama,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${b.kode} · ${b.qty} pcs'),
                    trailing: Text(
                      Uang.rp(b.nilai),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Tema.seed,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Nilai retur ${Uang.rp(nilai)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Tema.seed,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: dikunci
                        ? null
                        : () => Navigator.pop(ctx, AksiReturToko.batal),
                    child: const Text('Batal retur'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: dikunci
                        ? null
                        : () => Navigator.pop(ctx, AksiReturToko.edit),
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
