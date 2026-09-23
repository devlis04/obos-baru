import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dialog_gulir_isi.dart';
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
  final _gulir = ScrollController();
  var _sortKolom = 0;
  var _sortNaik = true;

  @override
  void dispose() {
    _cari.dispose();
    _gulir.dispose();
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
        (b.nota > 0 && !b.jadwal && 'extra'.contains(f)) ||
        angka(b.nota) ||
        angka(b.sku) ||
        angka(b.order) ||
        angka(b.kiriman) ||
        angka(b.batal) ||
        angka(b.pending) ||
        angka(b.actual);
  }

  static double _rasioNilai(int omset, int modal) {
    if (omset <= 0 || modal <= 0) return 0;
    return (omset - modal) / modal * 100;
  }

  static String _rasioTeks(int omset, int modal) {
    return '${_rasioNilai(omset, modal).toStringAsFixed(2)}%';
  }

  int _grup(TokoDash t) {
    if (t.jadwal) return 0;
    if (t.nota > 0) return 1;
    return 2;
  }

  int _banding(TokoDash a, TokoDash b) {
    if (_sortKolom == 0) {
      final g = _grup(a).compareTo(_grup(b));
      if (g != 0) return _sortNaik ? g : -g;
    }
    final r = switch (_sortKolom) {
      0 => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
      1 => a.teksVisit.compareTo(b.teksVisit),
      2 => a.nota.compareTo(b.nota),
      3 => a.sku.compareTo(b.sku),
      4 => a.order.compareTo(b.order),
      5 => _rasioNilai(a.order, a.modalOrder)
          .compareTo(_rasioNilai(b.order, b.modalOrder)),
      6 => a.kiriman.compareTo(b.kiriman),
      7 => _rasioNilai(a.kiriman, a.modalKiriman)
          .compareTo(_rasioNilai(b.kiriman, b.modalKiriman)),
      8 => a.batal.compareTo(b.batal),
      9 => a.pending.compareTo(b.pending),
      10 => _rasioNilai(a.pending, a.modalPending)
          .compareTo(_rasioNilai(b.pending, b.modalPending)),
      11 => a.actual.compareTo(b.actual),
      12 => _rasioNilai(a.actual, a.modalActual)
          .compareTo(_rasioNilai(b.actual, b.modalActual)),
      _ => a.status.toLowerCase().compareTo(b.status.toLowerCase()),
    };
    return _sortNaik ? r : -r;
  }

  static const _lebar = <double>[
    160,
    112,
    52,
    44,
    92,
    56,
    92,
    56,
    68,
    88,
    56,
    92,
    56,
    80,
  ];

  void _urut(int i) {
    setState(() {
      if (_sortKolom == i) {
        _sortNaik = !_sortNaik;
      } else {
        _sortKolom = i;
        _sortNaik = i == 0;
      }
    });
  }

  Widget _sel(
    String teks, {
    int i = 0,
    bool angka = false,
    bool tengah = false,
    bool tebal = false,
    Widget? anak,
  }) {
    return SizedBox(
      width: _lebar[i],
      child: Padding(
        padding: EdgeInsets.only(
          left: i == 0 ? 0 : 6,
          right: i == _lebar.length - 1 ? 0 : 4,
        ),
        child: anak ??
            Align(
              alignment: tengah
                  ? Alignment.center
                  : angka
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
              child: Text(
                teks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: tengah
                    ? TextAlign.center
                    : angka
                        ? TextAlign.right
                        : TextAlign.left,
                style: TextStyle(
                  fontWeight: tebal ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
      ),
    );
  }

  Widget _kepala() {
    const judul = [
      'Toko',
      'Visit',
      'Nota',
      'SKU',
      'Order',
      '%',
      'Kiriman',
      '%',
      'Batal',
      'Pending',
      '%',
      'Actual',
      '%',
      'Status',
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _garis)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < judul.length; i++)
            InkWell(
              onTap: () => _urut(i),
              child: SizedBox(
                width: _lebar[i],
                height: 36,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 6,
                    right: i == judul.length - 1 ? 0 : 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          judul[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_sortKolom == i)
                        Icon(
                          _sortNaik
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _baris({
    required List<Widget> sel,
    bool jumlah = false,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: jumlah ? Colors.grey.shade50 : null,
        border: const Border(bottom: BorderSide(color: _garis, width: 0.5)),
      ),
      child: SizedBox(
        height: 40,
        child: Row(children: sel),
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
    final jumModalOrder = tampil.fold<int>(0, (a, b) => a + b.modalOrder);
    final jumModalKiriman = tampil.fold<int>(0, (a, b) => a + b.modalKiriman);
    final jumModalPending = tampil.fold<int>(0, (a, b) => a + b.modalPending);
    final jumModalActual = tampil.fold<int>(0, (a, b) => a + b.modalActual);

    Widget uang(int n, int i, {bool tebal = false}) => _sel(
          Uang.angka(n),
          i: i,
          angka: true,
          tebal: tebal,
        );

    Widget persen(int omset, int modal, int i, {bool tebal = false}) => _sel(
          _rasioTeks(omset, modal),
          i: i,
          angka: true,
          tebal: tebal,
        );

    List<Widget> nilaiToko(TokoDash? b, {bool tebal = false}) {
      final order = b?.order ?? jumOrder;
      final kiriman = b?.kiriman ?? jumKiriman;
      final pending = b?.pending ?? jumPending;
      final actual = b?.actual ?? jumActual;
      return [
        uang(b?.nota ?? jumNota, 2, tebal: tebal),
        uang(b?.sku ?? jumSku, 3, tebal: tebal),
        uang(order, 4, tebal: tebal),
        persen(order, b?.modalOrder ?? jumModalOrder, 5, tebal: tebal),
        uang(kiriman, 6, tebal: tebal),
        persen(kiriman, b?.modalKiriman ?? jumModalKiriman, 7, tebal: tebal),
        uang(b?.batal ?? jumBatal, 8, tebal: tebal),
        uang(pending, 9, tebal: tebal),
        persen(pending, b?.modalPending ?? jumModalPending, 10, tebal: tebal),
        uang(actual, 11, tebal: tebal),
        persen(actual, b?.modalActual ?? jumModalActual, 12, tebal: tebal),
      ];
    }

    return DialogGulirIsi(
      lebar: _lebar.fold<double>(0, (a, b) => a + b),
      controller: _gulir,
      itemCount: tampil.length,
      judul: Row(
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
      kepala: _kepala(),
      jumlah: _baris(
        jumlah: true,
        sel: [
          _sel(
            'Jumlah (${tampil.length})',
            tebal: true,
          ),
          _sel('', i: 1),
          ...nilaiToko(null, tebal: true),
          _sel('', i: 13),
        ],
      ),
      itemBuilder: (context, i) {
        final b = tampil[i];
        return _baris(
          sel: [
            _sel(
              '',
              anak: _namaToko(context, b),
            ),
            _sel(b.teksVisit, i: 1, tengah: true),
            ...nilaiToko(b),
            _sel(b.status, i: 13, tengah: true),
          ],
        );
      },
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
