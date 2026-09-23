import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/kartu_toko.dart';
import '../uang.dart';
import '../umpan.dart';
import 'chip_status.dart';
import 'nota_sheet.dart';
import 'toko_repo.dart';

class TokoLayar extends StatefulWidget {
  const TokoLayar({super.key, required this.toko, required this.tanggal});

  final KartuToko toko;
  final DateTime tanggal;

  @override
  State<TokoLayar> createState() => _TokoLayarState();
}

class _TokoLayarState extends State<TokoLayar> {
  final _repo = TokoRepo(Supabase.instance.client);
  late KartuToko _toko;
  bool _muat = true;
  List<RingkasNota> _nota = [];

  @override
  void initState() {
    super.initState();
    _toko = widget.toko;
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final list = await _repo.notaToko(widget.tanggal, _toko.idPelanggan);
      final kartu = await _repo.kartu(widget.tanggal);
      final sama = kartu.where((t) => t.idPelanggan == _toko.idPelanggan);
      if (!mounted) return;
      setState(() {
        _nota = list;
        if (sama.isNotEmpty) _toko = sama.first;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      umpan(context, pesanGagal(e, 'Nota toko belum bisa dimuat.'));
    }
  }

  Widget _uangRasio(String uang, String rasio) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          uang,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF1B75CB),
          ),
        ),
        Text(
          rasio,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _nominal(RingkasNota n) {
    if (!n.sudahPack) {
      return _uangRasio(
        Uang.rp(n.omsetPacked),
        Uang.rasioLaba(omset: n.omsetPacked, laba: n.labaPacked),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _uangRasio(
          'Kiriman : ${Uang.rp(n.omsetPacked)}',
          Uang.rasioLaba(omset: n.omsetPacked, laba: n.labaPacked),
        ),
        const SizedBox(height: 2),
        _uangRasio(
          'Actual : ${Uang.rp(n.omsetActual)}',
          Uang.rasioLaba(omset: n.omsetActual, laba: n.labaActual),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_toko.nama.toUpperCase()),
      ),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muatData,
              child: _nota.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Belum ada nota untuk toko ini.')),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      itemCount: _nota.length,
                      itemBuilder: (context, i) {
                        final n = _nota[i];
                        final tanggal = Uang.tanggalJam(n.waktuOrder);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            onTap: () async {
                              final ubah = await tampilkanSheetRincianNota(
                                context: context,
                                namaToko: _toko.nama,
                                nota: n,
                              );
                              if (ubah && mounted) await _muatData();
                            },
                            child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _toko.nama.toUpperCase(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Text(
                                        'Nota: ${n.idTransaksi}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (tanggal.isNotEmpty)
                                        Text(
                                          tanggal,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    chipStatusNota(n.labelStatus),
                                    if (n.pending) ...[
                                      const SizedBox(height: 6),
                                      chipStatusNota('Pending'),
                                    ],
                                    const SizedBox(height: 6),
                                    _nominal(n),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
