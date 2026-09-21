import 'package:flutter/material.dart';

import 'buku_repo.dart';
import 'opname_bagian.dart';

Future<int?> pilihBagianOpname(
  BuildContext context, {
  required List<BarisBuku> semua,
  required int jumlah,
  required int terpilih,
}) {
  final potong = bagiOpname(semua, jumlah: jumlah, namaBarang: (b) => b.nama);
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pilih bagian opname',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  jumlah <= 1
                      ? 'Satu bagian. Semua SKU di sini.'
                      : '$jumlah bagian hanya memilah daftar. Tiap HP isi bagiannya lalu tap Simpan. Refresh mengambil fisik HP lain. Tutup buku dari web admin.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in potong)
                      Card(
                        color: p.indeks == terpilih
                            ? const Color(0xFFD6E8F7)
                            : Colors.white,
                        child: ListTile(
                          enabled: p.baris.isNotEmpty,
                          title: Text(
                            p.judulDari(jumlah),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${p.rentang}\n${p.baris.length} SKU',
                          ),
                          isThreeLine: true,
                          onTap: p.baris.isEmpty
                              ? null
                              : () => Navigator.pop(ctx, p.indeks),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
