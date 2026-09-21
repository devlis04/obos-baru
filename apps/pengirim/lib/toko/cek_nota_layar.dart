import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/kartu_toko.dart';
import '../lantai.dart';
import '../uang.dart';
import '../umpan.dart';
import 'harga_tebus.dart';
import 'toko_repo.dart';

class CekNotaHasil {
  const CekNotaHasil({required this.qtyTebus, required this.dibatalkan});

  final Map<String, int> qtyTebus;
  final bool dibatalkan;
}

class CekNotaLayar extends StatefulWidget {
  const CekNotaLayar({
    super.key,
    required this.namaToko,
    required this.nota,
    this.qtyAwal = const {},
  });

  final String namaToko;
  final RingkasNota nota;
  final Map<String, int> qtyAwal;

  @override
  State<CekNotaLayar> createState() => _CekNotaLayarState();
}

class _CekNotaLayarState extends State<CekNotaLayar> {
  final _repo = TokoRepo(Supabase.instance.client);
  bool _muat = true;
  List<ItemNota> _item = [];
  final Map<String, int> _qty = {};

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final list = await _repo.item(widget.nota.idTransaksi);
      _item = list;
      _qty
        ..clear()
        ..addEntries(
          list.map(
            (e) => MapEntry(
              e.idBarang,
              widget.qtyAwal[e.idBarang] ?? e.qtyPacked,
            ),
          ),
        );
      if (!mounted) return;
      setState(() => _muat = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      umpan(context, pesanGagal(e, 'Rincian nota belum bisa dimuat.'));
    }
  }

  int get _total => omsetTebus(_item, _qty);

  void _setQty(ItemNota it, int n) {
    setState(() => _qty[it.idBarang] = n.clamp(0, it.qtyPacked));
  }

  Future<void> _simpan() async {
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    final kosong = !_qty.values.any((q) => q > 0);
    Navigator.of(context).pop(
      CekNotaHasil(qtyTebus: Map<String, int>.from(_qty), dibatalkan: kosong),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.namaToko.toUpperCase())),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _muat ? null : _simpan,
            child: Text('Simpan tebus · ${Uang.rp(_total)}'),
          ),
        ),
      ),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: _item.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final it = _item[i];
                final q = _qty[it.idBarang] ?? 0;
                final harga = hargaJualTebus(
                  item: it,
                  semua: _item,
                  qty: _qty,
                );
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.nama,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Kiriman: ${it.qtyPacked} × ${Uang.rp(it.hargaJualPacked)}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          q <= 0
                              ? 'Tebus: 0 (batal)'
                              : 'Tebus: $q × ${Uang.rp(harga)}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Tebus'),
                            const Spacer(),
                            IconButton(
                              onPressed: () => _setQty(it, q - 1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '$q',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _setQty(it, q + 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
