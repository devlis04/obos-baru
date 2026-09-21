import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pesan.dart';
import '../setoran/daftar_rinci_dialog.dart';
import '../setoran/setoran_repo.dart';
import '../uang.dart';
import 'dashboard_repo.dart';

Future<void> bukaTokoDash({
  required BuildContext context,
  required DateTime hari,
  required String rute,
  required String nama,
}) async {
  final repo = DashboardRepo(Supabase.instance.client);
  IsiTokoDash data;
  try {
    data = await repo.tokoHari(hari: hari, rute: rute);
  } catch (e) {
    if (!context.mounted) return;
    tampilPesan(
      context,
      Jaringan.mati(e)
          ? 'Tidak ada internet. Daftar toko belum bisa dibuka.'
          : pesanGagal(e, 'Daftar toko belum bisa dibaca.'),
    );
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => DialogTokoDash(data: data, namaSales: nama),
  );
}

class DialogTokoDash extends StatefulWidget {
  const DialogTokoDash({
    super.key,
    required this.data,
    required this.namaSales,
  });

  final IsiTokoDash data;
  final String namaSales;

  @override
  State<DialogTokoDash> createState() => _DialogTokoDashState();
}

class _DialogTokoDashState extends State<DialogTokoDash> {
  static const _garis = Color(0xFF8FB4D9);
  final _cari = TextEditingController();
  var _sortKolom = 0;
  var _sortNaik = true;

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  String get _judul {
    final sales = widget.namaSales.trim();
    final rute = widget.data.rute;
    final tgl = Uang.tanggal(widget.data.hari);
    if (sales.isEmpty) return 'Toko $rute · $tgl';
    return 'Toko $rute · $sales · $tgl';
  }

  bool _cocok(TokoDash b) {
    final f = _cari.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    final digit = f.replaceAll(RegExp(r'[^0-9]'), '');
    bool angka(int n) {
      if (digit.isNotEmpty && n.toString().contains(digit)) return true;
      return Uang.angka(n).toLowerCase().contains(f);
    }

    return b.nama.toLowerCase().contains(f) ||
        b.idPelanggan.toLowerCase().contains(f) ||
        b.status.toLowerCase().contains(f) ||
        b.teksVisit.toLowerCase().contains(f) ||
        angka(b.nota) ||
        angka(b.sku) ||
        angka(b.order) ||
        angka(b.kiriman) ||
        angka(b.batal) ||
        angka(b.pending) ||
        angka(b.actual);
  }

  int _banding(TokoDash a, TokoDash b) {
    final r = switch (_sortKolom) {
      0 => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
      1 => a.teksVisit.compareTo(b.teksVisit),
      2 => a.nota.compareTo(b.nota),
      3 => a.sku.compareTo(b.sku),
      4 => a.order.compareTo(b.order),
      5 => a.kiriman.compareTo(b.kiriman),
      6 => a.batal.compareTo(b.batal),
      7 => a.pending.compareTo(b.pending),
      8 => a.actual.compareTo(b.actual),
      _ => a.status.toLowerCase().compareTo(b.status.toLowerCase()),
    };
    return _sortNaik ? r : -r;
  }

  DataColumn _kolom(String judul, int i, {bool angka = false, double? lebar}) {
    return DataColumn(
      numeric: angka,
      headingRowAlignment: MainAxisAlignment.center,
      onSort: (idx, naik) => setState(() {
        _sortKolom = i;
        _sortNaik = naik;
      }),
      label: SizedBox(
        width: lebar,
        child: Text(
          judul,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tampil = widget.data.toko.where(_cocok).toList()..sort(_banding);
    final jumNota = tampil.fold<int>(0, (a, b) => a + b.nota);
    final jumSku = tampil.fold<int>(0, (a, b) => a + b.sku);
    final jumOrder = tampil.fold<int>(0, (a, b) => a + b.order);
    final jumKiriman = tampil.fold<int>(0, (a, b) => a + b.kiriman);
    final jumBatal = tampil.fold<int>(0, (a, b) => a + b.batal);
    final jumPending = tampil.fold<int>(0, (a, b) => a + b.pending);
    final jumActual = tampil.fold<int>(0, (a, b) => a + b.actual);
    const gayaJumlah = TextStyle(fontWeight: FontWeight.bold);

    DataCell uang(int n, {bool tebal = false}) => DataCell(
          Text(
            Uang.angka(n),
            textAlign: TextAlign.right,
            style: tebal ? gayaJumlah : null,
          ),
        );

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              _judul,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 460,
            child: TextField(
              controller: _cari,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cari toko, visit, status, atau angka',
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 32,
                ),
                suffixIcon: _cari.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _cari.clear();
                          setState(() {});
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        width: 980,
        child: widget.data.toko.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Tidak ada toko untuk sales ini di hari itu.'),
              )
            : DaftarGulirDialog(
                faktor: 0.62,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: const TableBorder(
                      verticalInside: BorderSide(color: _garis, width: 1),
                    ),
                    columnSpacing: 12,
                    horizontalMargin: 8,
                    headingRowHeight: 36,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 40,
                    sortColumnIndex: _sortKolom,
                    sortAscending: _sortNaik,
                    columns: [
                      _kolom('Toko', 0, lebar: 168),
                      _kolom('Visit', 1, lebar: 88),
                      _kolom('Nota', 2, angka: true, lebar: 56),
                      _kolom('SKU', 3, angka: true, lebar: 56),
                      _kolom('Order', 4, angka: true),
                      _kolom('Kiriman', 5, angka: true),
                      _kolom('Batal', 6, angka: true),
                      _kolom('Pending', 7, angka: true),
                      _kolom('Actual', 8, angka: true),
                      _kolom('Status', 9, lebar: 80),
                    ],
                    rows: [
                      for (final b in tampil)
                        DataRow(
                          cells: [
                            DataCell(_namaToko(context, b)),
                            DataCell(Text(b.teksVisit)),
                            uang(b.nota),
                            uang(b.sku),
                            uang(b.order),
                            uang(b.kiriman),
                            uang(b.batal),
                            uang(b.pending),
                            uang(b.actual),
                            DataCell(Text(b.status)),
                          ],
                        ),
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              'Jumlah (${tampil.length})',
                              style: gayaJumlah,
                            ),
                          ),
                          const DataCell(Text('')),
                          uang(jumNota, tebal: true),
                          uang(jumSku, tebal: true),
                          uang(jumOrder, tebal: true),
                          uang(jumKiriman, tebal: true),
                          uang(jumBatal, tebal: true),
                          uang(jumPending, tebal: true),
                          uang(jumActual, tebal: true),
                          const DataCell(Text('')),
                        ],
                      ),
                    ],
                  ),
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
  }

  Widget _namaToko(BuildContext context, TokoDash b) {
    final isiNota = b.isi['nota_list'];
    final adaNota = isiNota is List && isiNota.isNotEmpty;
    return Tooltip(
      message: 'Rincian nota',
      child: InkWell(
        onTap: !adaNota
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (ctx) => DialogNotaToko(
                    jenis: 'actual',
                    toko: TokoSetoranRinci.dari(b.isi),
                    tanggal: widget.data.hari,
                  ),
                ),
        child: Text(
          b.nama.isEmpty ? b.idPelanggan : b.nama,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: adaNota ? Tema.seed : null,
            decoration: adaNota ? TextDecoration.underline : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
