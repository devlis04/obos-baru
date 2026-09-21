import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import 'kasbon_cek_setoran.dart';
import 'setoran_repo.dart';

Future<void> bukaDialogKasbon({
  required BuildContext context,
  required DateTime? tanggal,
  required String rute,
  required List<BarisSetoranRute> semuaRute,
}) async {
  final daftar = rute == 'Jumlah'
      ? semuaRute
      : semuaRute.where((b) => b.rute == rute).toList();
  if (daftar.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DialogKasbon(
      tanggal: tanggal,
      judul: rute == 'Jumlah' ? 'Kasbon semua rute' : 'Kasbon $rute',
      daftar: daftar,
      semuaRute: rute == 'Jumlah',
    ),
  );
}

class _DialogKasbon extends StatelessWidget {
  const _DialogKasbon({
    required this.tanggal,
    required this.judul,
    required this.daftar,
    required this.semuaRute,
  });

  final DateTime? tanggal;
  final String judul;
  final List<BarisSetoranRute> daftar;
  final bool semuaRute;

  static const _gayaTebal = TextStyle(fontWeight: FontWeight.bold);
  static const _gayaJudul = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
  static const _garis = Color(0xFF8FB4D9);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KasbonCekSetoran.instance,
      builder: (context, _) {
        final cek = KasbonCekSetoran.instance;
        final orang = [
          for (final b in daftar)
            for (final o in b.orangKasbon) (rute: b.rute, o: o),
        ];
        final jumKlaim = orang.fold<int>(0, (n, x) => n + x.o.klaim);
        DataCell uang(int n, {bool tebal = false}) => DataCell(
              Text(
                Uang.angka(n),
                textAlign: TextAlign.right,
                style: tebal ? _gayaTebal : null,
              ),
            );

        return AlertDialog(
          constraints: const BoxConstraints(minWidth: 0, maxWidth: 420),
          title: Text(
            judul,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          content: IsiDialog(
            child: IntrinsicWidth(
              child: DataTable(
                border: const TableBorder(
                  verticalInside: BorderSide(color: _garis, width: 1),
                ),
                columnSpacing: 16,
                horizontalMargin: 8,
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                columns: [
                  if (!semuaRute)
                    const DataColumn(
                      headingRowAlignment: MainAxisAlignment.center,
                      label: SizedBox(width: 28),
                    ),
                  const DataColumn(
                    headingRowAlignment: MainAxisAlignment.center,
                    label: Text('Orang', style: _gayaJudul),
                  ),
                  const DataColumn(
                    headingRowAlignment: MainAxisAlignment.center,
                    numeric: true,
                    label: Text('Klaim', style: _gayaJudul),
                  ),
                ],
                rows: [
                  for (final x in orang)
                    DataRow(
                      cells: [
                        if (!semuaRute)
                          DataCell(
                            Checkbox(
                              value: cek.centang(
                                tanggal: tanggal,
                                rute: x.rute,
                                peran: x.o.peran,
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => cek.setCentang(
                                tanggal: tanggal,
                                rute: x.rute,
                                peran: x.o.peran,
                                nilai: v ?? false,
                              ),
                            ),
                          ),
                        DataCell(
                          Text(
                            semuaRute ? '${x.rute} · ${x.o.label}' : x.o.label,
                          ),
                        ),
                        uang(x.o.klaim),
                      ],
                    ),
                  DataRow(
                    cells: [
                      if (!semuaRute) const DataCell(Text('')),
                      DataCell(
                        Text(
                          'Jumlah (${orang.length})',
                          style: _gayaTebal,
                        ),
                      ),
                      uang(jumKlaim, tebal: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }
}
