import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/kartu_toko.dart';
import '../lantai.dart';
import '../uang.dart';
import '../umpan.dart';
import 'chip_status.dart';
import 'toko_repo.dart';

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

Widget barisBarangNota(ItemNota it, {int? qtyTebus, int? hargaTebus}) {
  final gayaKiri = TextStyle(color: Colors.grey.shade600, fontSize: 12);
  const gayaNilai = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Tema.seed,
  );
  final gayaRasio = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 11,
    color: Colors.grey.shade600,
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
              style: gayaRasio,
            ),
          ),
        ],
      ),
    );
  }

  final actualQty = qtyTebus ?? it.qtyActual ?? 0;
  final actualHarga = hargaTebus ??
      it.hargaJualActual ??
      (it.hargaJualOrder > 0 ? it.hargaJualOrder : it.hargaJualPacked);
  final actualSub = (qtyTebus != null || it.qtyActual != null)
      ? actualQty * actualHarga
      : (it.subtotalActual ?? 0);
  final beli = it.hargaBeli;

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
        rasio: Uang.rasioItem(
          hargaJual: it.hargaJualOrder,
          hargaBeli: beli,
        ),
      ),
      baris(
        label: 'Kiriman',
        qty: it.qtyPacked,
        harga: it.hargaJualPacked,
        subtotal: it.subtotalPacked,
        rasio: Uang.rasioItem(
          hargaJual: it.hargaJualPacked,
          hargaBeli: beli,
        ),
      ),
      baris(
        label: 'Actual',
        qty: actualQty,
        harga: actualHarga,
        subtotal: actualSub,
        rasio: Uang.rasioItem(
          hargaJual: actualHarga,
          hargaBeli: beli,
        ),
      ),
    ],
  );
}

Future<bool> tampilkanSheetRincianNota({
  required BuildContext context,
  required String namaToko,
  required RingkasNota nota,
}) async {
  final repo = TokoRepo(Supabase.instance.client);
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return FutureBuilder<List<ItemNota>>(
        future: repo.item(nota.idTransaksi),
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
          return _IsiSheetRincian(
            namaToko: namaToko,
            nota: nota,
            items: snapshot.data!,
            repo: repo,
          );
        },
      );
    },
  );
  return hasil == true;
}

class _IsiSheetRincian extends StatefulWidget {
  const _IsiSheetRincian({
    required this.namaToko,
    required this.nota,
    required this.items,
    required this.repo,
  });

  final String namaToko;
  final RingkasNota nota;
  final List<ItemNota> items;
  final TokoRepo repo;

  @override
  State<_IsiSheetRincian> createState() => _IsiSheetRincianState();
}

class _IsiSheetRincianState extends State<_IsiSheetRincian> {
  bool _kirim = false;

  bool get _dikirim =>
      widget.nota.status == 'dikirim' && !widget.nota.pending;

  bool get _pending => widget.nota.pending;

  Future<bool> _konfirmasi({
    required String judul,
    required String isi,
    required String ya,
    bool bahaya = false,
  }) async {
    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          judul,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: IsiDialog(child: Text(isi)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            style: bahaya
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ya),
          ),
        ],
      ),
    );
    return hasil == true;
  }

  Future<void> _aksi(bool pending) async {
    if (_kirim) return;
    final ok = pending
        ? await _konfirmasi(
            judul: 'Pending nota?',
            isi: 'Pengiriman nota ini ditunda. Lanjutkan?',
            ya: 'Pending',
          )
        : await _konfirmasi(
            judul: 'Batalkan nota?',
            isi:
                'Jumlah packing dikembalikan ke stok. Nota batal dan tidak bisa diubah lagi. Lanjutkan?',
            ya: 'Batalkan',
            bahaya: true,
          );
    if (!ok || !mounted) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    setState(() => _kirim = true);
    try {
      if (pending) {
        await widget.repo.pendingNota(widget.nota.idTransaksi);
      } else {
        await widget.repo.batalNota(widget.nota.idTransaksi);
      }
      if (!mounted) return;
      umpan(context, pending ? 'Nota di-pending.' : 'Nota dibatalkan.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _kirim = false);
      umpan(
        context,
        pesanGagal(
          e,
          pending ? 'Nota belum bisa di-pending.' : 'Nota belum bisa dibatalkan.',
        ),
      );
    }
  }

  Widget _tombolAksi() {
    final gaya = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: Size.zero,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_dikirim)
          TextButton.icon(
            style: gaya.copyWith(
              foregroundColor: WidgetStateProperty.all(Colors.orange.shade800),
            ),
            onPressed: _kirim ? null : () => _aksi(true),
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: const Text('Pending'),
          ),
        TextButton.icon(
          style: gaya.copyWith(
            foregroundColor: WidgetStateProperty.all(Colors.red),
          ),
          onPressed: _kirim ? null : () => _aksi(false),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Batalkan'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tanggal = Uang.tanggalJam(widget.nota.waktuOrder);
    final items = widget.items;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.namaToko.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Nota: ${widget.nota.idTransaksi}',
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
                chipStatusNota(widget.nota.labelStatus),
                if (widget.nota.pending) ...[
                  const SizedBox(width: 6),
                  chipStatusNota('Pending'),
                ],
                if (_dikirim || _pending) ...[
                  const Spacer(),
                  _tombolAksi(),
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
                  itemBuilder: (context, i) => barisBarangNota(items[i]),
                ),
              ),
            const Divider(height: 24),
            barisUangNota(
              'Order',
              widget.nota.omsetOrder,
              Uang.rasioOmset(
                omset: widget.nota.omsetOrder,
                modal: items.fold(0, (s, i) => s + i.qtyOrder * i.hargaBeli),
              ),
            ),
            if (widget.nota.sudahPack) ...[
              const SizedBox(height: 8),
              barisUangNota(
                'Kiriman',
                widget.nota.omsetPacked,
                Uang.rasioOmset(
                  omset: widget.nota.omsetPacked,
                  modal: items.fold(0, (s, i) => s + i.qtyPacked * i.hargaBeli),
                ),
              ),
              const SizedBox(height: 8),
              barisUangNota(
                'Actual',
                widget.nota.omsetActual,
                Uang.rasioOmset(
                  omset: widget.nota.omsetActual,
                  modal: items.fold(
                    0,
                    (s, i) => s + (i.qtyActual ?? 0) * i.hargaBeli,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
