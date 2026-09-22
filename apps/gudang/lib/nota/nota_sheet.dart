import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import '../umpan.dart';
import 'nota_repo.dart';
import 'transaksi_helper.dart';

Widget barisUangNota(String label, int nilai, String rasio) {
  const gayaUang = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Tema.seed,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  return Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 168,
            child: Row(
              children: [
                const Text('Rp', style: gayaUang),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    Uang.angka(nilai),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: gayaUang,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 42,
                  child: Text(
                    rasio,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

Widget barisBarangNota(
  ItemNota it, {
  bool tampilPacked = true,
  bool tampilActual = false,
}) {
  final gayaKiri = TextStyle(color: Colors.grey.shade600, fontSize: 12);
  const gayaNilai = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Tema.seed,
  );

  Widget baris({
    required String label,
    required int qty,
    required int harga,
    required int subtotal,
    required String rasio,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 58,
            child: Text(label, style: gayaKiri),
          ),
          Expanded(
            child: Text(
              ': $qty pcs x ${Uang.rp(harga)}',
              style: gayaKiri,
            ),
          ),
          Text(Uang.rp(subtotal), style: gayaNilai),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            child: Text(
              rasio,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  final packedQty = it.qtyPacked ?? 0;
  final packedHarga = it.hargaJualPacked ?? it.hargaJualOrder;
  final packedSub = it.subtotalPacked ?? packedQty * packedHarga;
  final beli = it.hargaBeli;

  final actualQty = it.qtyActual;
  final actualHarga = packedHarga > 0 ? packedHarga : it.hargaJualOrder;
  final actualSub = actualQty == null
      ? (it.subtotalActual ?? 0)
      : actualQty * actualHarga;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(it.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      baris(
        label: 'Order',
        qty: it.qtyOrder,
        harga: it.hargaJualOrder,
        subtotal: it.subtotalOrder,
        rasio: TransaksiHelper.rasioItem(
          hargaJual: it.hargaJualOrder,
          hargaBeli: beli,
        ),
      ),
      if (tampilPacked)
        baris(
          label: 'Kiriman',
          qty: packedQty,
          harga: packedHarga,
          subtotal: packedSub,
          rasio: TransaksiHelper.rasioItem(
            hargaJual: packedHarga,
            hargaBeli: beli,
          ),
        ),
      if (tampilActual)
        baris(
          label: 'Actual',
          qty: actualQty ?? 0,
          harga: actualHarga,
          subtotal: actualQty == null ? 0 : actualSub,
          rasio: TransaksiHelper.rasioItem(
            hargaJual: actualHarga,
            hargaBeli: beli,
          ),
        ),
    ],
  );
}

Widget chipStatusNota(String label) {
  final warna = switch (label) {
    'Terkirim' || 'Sedang dikirim' => Colors.green,
    'Batal' => Colors.red,
    'Pending' => Colors.orange.shade800,
    _ => Colors.amber.shade800,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: warna, width: 1.2),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: warna,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    ),
  );
}

String _teksWaktu(DateTime? w) {
  if (w == null) return '';
  final l = w.toLocal();
  final tgl =
      '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  final jam =
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  return '$tgl $jam';
}

Future<void> tampilkanSheetRincianNota({
  required BuildContext context,
  required RingkasNota nota,
  required Future<List<ItemNota>> Function() muatItem,
  required Future<void> Function() onPack,
  required Future<void> Function() onLihat,
  Future<void> Function(List<ItemNota> items)? onCetak,
  bool bolehPack = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return FutureBuilder<List<ItemNota>>(
        future: muatItem(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  pesanGagal(
                    snapshot.error ?? 'gagal',
                    'Rincian barang pada nota ini belum bisa ditampilkan.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final items = snapshot.data!;
          final tanggal = _teksWaktu(nota.waktuOrder);
          final packed = nota.waktuPacked != null || nota.status == 'dikirim';
          final actual = packed;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nota.namaPelanggan.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Nota: ${nota.idTransaksi}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  if (tanggal.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tanggal,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      chipStatusNota(nota.labelStatus),
                      if (nota.pending) ...[
                        const SizedBox(width: 6),
                        chipStatusNota('Pending'),
                      ],
                    ],
                  ),
                  const Divider(height: 24),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Rincian barang pada nota ini belum bisa ditampilkan.',
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => barisBarangNota(
                          items[i],
                          tampilPacked: packed,
                          tampilActual: actual,
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                  barisUangNota(
                    'Order',
                    nota.omsetOrder,
                    TransaksiHelper.rasioOmset(
                      omset: nota.omsetOrder,
                      modal: items.fold(0, (s, i) => s + i.qtyOrder * i.hargaBeli),
                    ),
                  ),
                  if (packed) ...[
                    const SizedBox(height: 8),
                    barisUangNota(
                      'Kiriman',
                      nota.omsetPacked,
                      TransaksiHelper.rasioOmset(
                        omset: nota.omsetPacked,
                        modal: items.fold(
                          0,
                          (s, i) => s + (i.qtyPacked ?? 0) * i.hargaBeli,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    barisUangNota(
                      'Actual',
                      nota.omsetActual,
                      TransaksiHelper.rasioOmset(
                        omset: nota.omsetActual,
                        modal: items.fold(
                          0,
                          (s, i) => s + (i.qtyActual ?? 0) * i.hargaBeli,
                        ),
                      ),
                    ),
                  ],
                  if (nota.bisaPack && bolehPack) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await onPack();
                        },
                        child: Text(
                          packed ? 'Ubah packing' : 'Siapkan pesanan',
                        ),
                      ),
                    ),
                  ],
                  if (nota.status != 'batal' &&
                      nota.status != 'terkirim' &&
                      !(nota.bisaPack && bolehPack) &&
                      items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await onLihat();
                        },
                        child: const Text('Lihat nota'),
                      ),
                    ),
                  ],
                  if (nota.status != 'batal' &&
                      items.any((it) => (it.qtyPacked ?? 0) > 0) &&
                      onCetak != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onCetak(items);
                        },
                        child: const Text('Cetak ulang'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
