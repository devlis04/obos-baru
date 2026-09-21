import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import '../umpan.dart';
import 'ringkas_hari.dart';
import 'setoran_layar.dart';

Future<void> tampilkanSheetSetoran({
  required BuildContext context,
  required DateTime tanggal,
  required RingkasHari ringkas,
  required String rutePengirim,
  int belumKunci = 0,
  bool sudahSetor = false,
  bool bolehSetor = true,
}) {
  const gayaNilai = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Tema.seed,
  );
  const lebarLabel = 84.0;
  const lebarRasio = 52.0;
  final n = belumKunci > ringkas.wajibKunci ? belumKunci : ringkas.wajibKunci;
  final kunciDulu = n > 0;

  Widget barisUang({
    required String label,
    required int nilai,
    int? laba,
    Color? warna,
  }) {
    final gaya = gayaNilai.copyWith(color: warna ?? Tema.seed);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: lebarLabel, child: Text(label, style: gaya)),
          Expanded(
            child: Text(
              Uang.rp(nilai),
              textAlign: TextAlign.right,
              style: gaya,
            ),
          ),
          SizedBox(
            width: lebarRasio,
            child: laba == null
                ? const SizedBox.shrink()
                : Text(
                    Uang.rasioLaba(omset: nilai, laba: laba),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ringkasan pengiriman',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              Uang.tanggal(tanggal),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            Text(
              '${ringkas.jumlahToko} toko · ${ringkas.jumlahNota} nota',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const Divider(height: 24),
            barisUang(
              label: 'Order',
              nilai: ringkas.omsetOrder,
              laba: ringkas.labaOrder,
            ),
            barisUang(
              label: 'Kiriman',
              nilai: ringkas.omsetPacked,
              laba: ringkas.labaPacked,
            ),
            barisUang(
              label: 'Pending',
              nilai: ringkas.omsetPending,
              warna: Colors.orange.shade800,
            ),
            barisUang(
              label: 'Batal',
              nilai: ringkas.omsetBatal,
              warna: Colors.red,
            ),
            barisUang(
              label: 'Retur',
              nilai: ringkas.omsetRetur,
              warna: Colors.red,
            ),
            barisUang(
              label: 'Actual',
              nilai: ringkas.actualTampil,
              laba: ringkas.labaActual,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !bolehSetor || kunciDulu
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          ruteHalaman(
                            SetoranLayar(
                              tanggal: tanggal,
                              ringkas: ringkas,
                              rutePengirim: rutePengirim,
                            ),
                          ),
                        );
                      },
                child: Text(
                  !bolehSetor
                      ? 'Hanya lihat'
                      : kunciDulu
                      ? (n == 1
                          ? 'Kunci nota dulu (1)'
                          : 'Kunci nota dulu ($n)')
                      : (sudahSetor ? 'Simpan setoran' : 'Setor'),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
