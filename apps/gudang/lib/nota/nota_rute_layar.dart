import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../barang/barang.dart';
import '../barang/barang_repo.dart';
import '../lantai.dart';
import '../printer_thermal.dart';
import '../umpan.dart';
import 'nota_repo.dart';
import 'nota_review_layar.dart';
import 'nota_sheet.dart';
import 'transaksi_helper.dart';

class NotaRuteLayar extends StatefulWidget {
  const NotaRuteLayar({
    super.key,
    required this.tanggal,
    required this.rute,
    required this.namaSales,
    this.bukuHidup = true,
  });

  final DateTime tanggal;
  final String rute;
  final String namaSales;
  final bool bukuHidup;

  @override
  State<NotaRuteLayar> createState() => _NotaRuteLayarState();
}

class _NotaRuteLayarState extends State<NotaRuteLayar> {
  final _repo = NotaRepo(Supabase.instance.client);
  bool _muat = true;
  List<RingkasNota> _nota = [];

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData({bool diam = false}) async {
    if (!diam) setState(() => _muat = true);
    try {
      final list = await _repo.rute(widget.tanggal, widget.rute);
      if (!mounted) return;
      setState(() {
        _nota = list;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nota = [];
        _muat = false;
      });
      umpan(context, pesanGagal(e, 'Nota rute ini belum bisa dimuat.'));
    }
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

  Color _warnaStatus(String label) {
    switch (label) {
      case 'Terkirim':
      case 'Sedang dikirim':
        return Colors.green;
      case 'Batal':
        return Colors.red;
      default:
        return Colors.amber.shade800;
    }
  }

  Future<void> _bukaSheet(RingkasNota nota) {
    return tampilkanSheetRincianNota(
      context: context,
      nota: nota,
      bolehPack: widget.bukuHidup,
      muatItem: () => _repo.item(nota.idTransaksi),
      onPack: () => _bukaReview(nota),
      onLihat: () async {
        await Navigator.of(context).push(
          ruteHalaman(
            NotaReviewLayar(
              nota: nota,
              namaSales: widget.namaSales,
              bukuHidup: widget.bukuHidup,
            ),
          ),
        );
        if (mounted) await _muatData(diam: true);
      },
      onCetak: (items) => _cetakUlang(nota, items),
    );
  }

  Future<void> _bukaReview(RingkasNota nota) async {
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      ruteHalaman(
        NotaReviewLayar(
          nota: nota,
          namaSales: widget.namaSales,
          bukuHidup: widget.bukuHidup,
        ),
      ),
    );
    if (mounted) await _muatData(diam: true);
  }

  Future<void> _cetakUlang(RingkasNota nota, List<ItemNota> items) async {
    final qty = <String, int>{};
    for (final it in items) {
      final q = it.qtyPacked ?? 0;
      if (q > 0) qty[it.idBarang] = q;
    }
    if (qty.isEmpty) {
      umpan(context, 'Belum ada jumlah packing untuk dicetak.');
      return;
    }
    var daftar = <Barang>[];
    try {
      daftar = await BarangRepo(Supabase.instance.client)
          .banyak(qty.keys.toList());
    } catch (_) {}
    final byId = {for (final b in daftar) b.id: b};
    for (final it in items) {
      if ((qty[it.idBarang] ?? 0) <= 0) continue;
      final live = byId[it.idBarang];
      final dasar = live ??
          Barang.cetak(
            id: it.idBarang,
            nama: it.nama,
            hargaJual: it.hargaDasarKunci,
          );
      byId[it.idBarang] = TransaksiHelper.pakaiKunciNota(dasar, it);
    }
    if (!mounted) return;
    await PrinterThermal.cetakUlangUi(
      context: context,
      namaToko: nota.namaPelanggan,
      namaSales: widget.namaSales,
      tanggalNota: nota.waktuOrder,
      keranjangQty: qty,
      daftarBarang: byId.values.toList(),
    );
  }

  Widget _chip(String teks, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: warna, width: 1.2),
      ),
      child: Text(
        teks,
        style: TextStyle(
          color: warna,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
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
            color: Tema.seed,
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

  Widget _nominal(RingkasNota nota) {
    final rasioOrder = TransaksiHelper.rasioOmset(
      omset: nota.omsetOrder,
      modal: nota.omsetOrder - nota.labaOrder,
    );
    if (!nota.sudahPack) {
      return _uangRasio(TransaksiHelper.rp(nota.omsetOrder), rasioOrder);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _uangRasio('Order : ${TransaksiHelper.rp(nota.omsetOrder)}', rasioOrder),
        const SizedBox(height: 2),
        _uangRasio(
          'Kiriman : ${TransaksiHelper.rp(nota.omsetPacked)}',
          TransaksiHelper.rasioOmset(
            omset: nota.omsetPacked,
            modal: nota.omsetPacked - nota.labaPacked,
          ),
        ),
        const SizedBox(height: 2),
        _uangRasio(
          'Actual : ${TransaksiHelper.rp(nota.omsetActual)}',
          TransaksiHelper.rasioOmset(
            omset: nota.omsetActual,
            modal: nota.omsetActual - nota.labaActual,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.namaSales)),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _muatData(diam: true),
              child: _nota.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Belum ada nota untuk rute ini.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      itemCount: _nota.length,
                      itemBuilder: (context, i) {
                        final nota = _nota[i];
                        final waktu = _teksWaktu(nota.waktuOrder);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            onTap: () => _bukaSheet(nota),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nota.namaPelanggan,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          'Nota: ${nota.idTransaksi}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (waktu.isNotEmpty)
                                          Text(
                                            waktu,
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
                                      _chip(
                                        nota.labelStatus,
                                        _warnaStatus(nota.labelStatus),
                                      ),
                                      if (nota.pending) ...[
                                        const SizedBox(height: 6),
                                        _chip(
                                          'Pending',
                                          Colors.orange.shade800,
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      _nominal(nota),
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
