import 'package:flutter/material.dart';

import '../barang/barang.dart';
import 'package:obos_core/obos_core.dart';
import 'transaksi_helper.dart';

class DialogQty extends StatefulWidget {
  const DialogQty({
    super.key,
    required this.barang,
    required this.qtySekarang,
    required this.qtyGrupTanpaIni,
    required this.onTerapkan,
  });

  final Barang barang;
  final int qtySekarang;
  final int qtyGrupTanpaIni;
  final void Function(int qty) onTerapkan;

  static Future<void> show(
    BuildContext context, {
    required Barang barang,
    required int qtySekarang,
    required int qtyGrupTanpaIni,
    required void Function(int qty) onTerapkan,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DialogQty(
        barang: barang,
        qtySekarang: qtySekarang,
        qtyGrupTanpaIni: qtyGrupTanpaIni,
        onTerapkan: onTerapkan,
      ),
    );
  }

  @override
  State<DialogQty> createState() => _DialogQtyState();
}

class _DialogQtyState extends State<DialogQty> {
  late int _qty;
  late TextEditingController _teks;

  @override
  void initState() {
    super.initState();
    _qty = widget.qtySekarang;
    _teks = TextEditingController(text: _qty > 0 ? '$_qty' : '');
  }

  @override
  void dispose() {
    _teks.dispose();
    super.dispose();
  }

  int get _qtyGrup => widget.qtyGrupTanpaIni + _qty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strata = widget.barang.strataAktif;
    final hargaGrup = TransaksiHelper.hargaDariQtyGrup(
      barang: widget.barang,
      totalQtyGrup: _qtyGrup,
    );

    return AlertDialog(
      title: Text(
        widget.barang.nama,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: IsiDialog(
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Id: ${widget.barang.id} | Grup: ${widget.barang.idGrup}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            Text(
              'Jumlah grup saat ini: $_qtyGrup pcs → ${TransaksiHelper.rp(hargaGrup)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const Divider(height: 12),
            const Text(
              'Strata harga kelompok (id grup):',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '• Beli < ${strata.isNotEmpty ? strata.first.minimal : 1} pcs grup = ${TransaksiHelper.rp(widget.barang.hargaJual)} (harga normal)',
              style: const TextStyle(fontSize: 12),
            ),
            if (strata.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '• Tidak ada strata grosir untuk barang ini.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...strata.map((item) {
                final tercapai = _qtyGrup >= item.minimal;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    '• Minimal ${item.minimal} pcs grup = ${TransaksiHelper.rp(item.jual)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: tercapai ? FontWeight.bold : FontWeight.normal,
                      color: tercapai ? Colors.green.shade700 : Colors.black87,
                    ),
                  ),
                );
              }),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    size: 32,
                    color: Tema.seed,
                  ),
                  onPressed: _qty > 0
                      ? () {
                          setState(() {
                            _qty--;
                            _teks.text = _qty > 0 ? '$_qty' : '';
                          });
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _teks,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      hintText: '0',
                    ),
                    onChanged: (val) {
                      setState(() {
                        _qty = int.tryParse(val) ?? 0;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    size: 32,
                    color: Tema.seed,
                  ),
                  onPressed: () {
                    setState(() {
                      _qty++;
                      _teks.text = '$_qty';
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            widget.onTerapkan(_qty);
            Navigator.pop(context);
          },
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}
