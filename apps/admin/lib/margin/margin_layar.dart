import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/admin_drawer.dart';
import '../jaringan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'gaji_dialog.dart';
import 'margin_repo.dart';

class MarginLayar extends StatefulWidget {
  const MarginLayar({super.key});

  @override
  State<MarginLayar> createState() => _MarginLayarState();
}

class _MarginLayarState extends State<MarginLayar> {
  final _repo = MarginRepo(Supabase.instance.client);
  List<BarisMarginBuku> _semua = const [];
  List<BarisMarginRuteBuku> _semuaRute = const [];
  bool _muat = true;
  late DateTime _senin;
  _UkuranTabel _u = const _UkuranTabel(1);

  @override
  void initState() {
    super.initState();
    _senin = _seninDari(_hariAcuan(DateTime.now()));
    _muatData();
  }

  DateTime _hariAcuan(DateTime w) {
    var hari = DateTime(w.year, w.month, w.day);
    if (hari.weekday == DateTime.sunday) {
      hari = hari.subtract(const Duration(days: 1));
    }
    return hari;
  }

  DateTime _seninDari(DateTime w) {
    final h = DateTime(w.year, w.month, w.day);
    return h.subtract(Duration(days: h.weekday - 1));
  }

  DateTime get _sabtu => _senin.add(const Duration(days: 5));

  bool get _mingguIni {
    final s = _seninDari(_hariAcuan(DateTime.now()));
    return s.year == _senin.year &&
        s.month == _senin.month &&
        s.day == _senin.day;
  }

  String get _judulMinggu {
    if (_mingguIni) return 'Minggu ini';
    return '${Uang.pendek(_senin)} – ${Uang.tanggal(_sabtu)}';
  }

  List<BarisMarginBuku> get _baris {
    final sabtu = _sabtu;
    return [
      for (final b in _semua)
        if (b.tanggal != null &&
            !b.tanggal!.isBefore(_senin) &&
            !b.tanggal!.isAfter(sabtu))
          b,
    ];
  }

  List<BarisMarginRute> get _ruteMinggu {
    final idMinggu = {for (final b in _baris) b.id};
    final gabung = <String, BarisMarginRute>{};
    final bopBukuPengirim = <String, int>{};
    for (final r in _semuaRute) {
      if (!idMinggu.contains(r.id)) continue;
      if (r.rutePengirim.isNotEmpty) {
        bopBukuPengirim['${r.id}|${r.rutePengirim}'] = r.bop;
      }
      final lama = gabung[r.rute];
      if (lama == null) {
        gabung[r.rute] = BarisMarginRute(
          rute: r.rute,
          nama: r.nama,
          rutePengirim: r.rutePengirim,
          nota: r.nota,
          omset: r.omset,
          modal: r.modal,
          margin: r.margin,
          marginRetur: r.marginRetur,
          ongkir: 0,
          bop: 0,
          selisihOpname: 0,
        );
      } else {
        gabung[r.rute] = BarisMarginRute(
          rute: r.rute,
          nama: lama.nama.isNotEmpty ? lama.nama : r.nama,
          rutePengirim: lama.rutePengirim.isNotEmpty
              ? lama.rutePengirim
              : r.rutePengirim,
          nota: lama.nota + r.nota,
          omset: lama.omset + r.omset,
          modal: lama.modal + r.modal,
          margin: lama.margin + r.margin,
          marginRetur: lama.marginRetur + r.marginRetur,
          ongkir: 0,
          bop: 0,
          selisihOpname: 0,
        );
      }
    }
    final bopPengirim = <String, int>{};
    for (final e in bopBukuPengirim.entries) {
      final p = e.key.substring(e.key.indexOf('|') + 1);
      bopPengirim[p] = (bopPengirim[p] ?? 0) + e.value;
    }
    final list = gabung.values.toList()
      ..sort((a, b) => a.rute.toLowerCase().compareTo(b.rute.toLowerCase()));
    var ongkirPool = 0;
    var selisihPool = 0;
    for (final b in _baris) {
      if (!b.ditutup) continue;
      ongkirPool += b.ongkir;
      selisihPool += b.selisihOpname;
    }
    return _bagiPorsi(
      _bagiPorsi(
        _bagiBopPengirim(list, bopPengirim),
        ongkirPool,
        (r, v) => r.salin(ongkir: v),
      ),
      selisihPool,
      (r, v) => r.salin(selisihOpname: v),
    );
  }

  List<BarisMarginRute> _bagiBopPengirim(
    List<BarisMarginRute> list,
    Map<String, int> bopPengirim,
  ) {
    final grup = <String, List<int>>{};
    for (var i = 0; i < list.length; i++) {
      final p = list[i].rutePengirim;
      if (p.isEmpty) continue;
      grup.putIfAbsent(p, () => []).add(i);
    }
    final out = List<BarisMarginRute>.from(list);
    for (final e in grup.entries) {
      final idx = e.value;
      final pool = bopPengirim[e.key] ?? 0;
      final nets = [
        for (final i in idx) out[i].margin - out[i].marginRetur,
      ];
      final denom = nets.fold<int>(0, (a, n) => a + n);
      var sisa = pool;
      for (var k = 0; k < idx.length; k++) {
        final int v;
        if (k == idx.length - 1) {
          v = sisa;
        } else if (denom <= 0) {
          v = pool ~/ idx.length;
        } else {
          v = ((nets[k] / denom) * pool).round();
        }
        sisa -= v;
        out[idx[k]] = out[idx[k]].salin(bop: v);
      }
    }
    return out;
  }

  List<BarisMarginRute> _bagiPorsi(
    List<BarisMarginRute> list,
    int pool,
    BarisMarginRute Function(BarisMarginRute r, int v) pasang,
  ) {
    if (list.isEmpty) return list;
    final nets = [for (final r in list) r.margin - r.marginRetur];
    final denom = nets.fold<int>(0, (a, n) => a + n);
    final out = List<BarisMarginRute>.from(list);
    var sisa = pool;
    for (var k = 0; k < out.length; k++) {
      final int v;
      if (k == out.length - 1) {
        v = sisa;
      } else if (denom <= 0) {
        v = pool ~/ out.length;
      } else {
        v = ((nets[k] / denom) * pool).round();
      }
      sisa -= v;
      out[k] = pasang(out[k], v);
    }
    return out;
  }

  Future<void> _pilihMinggu() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _senin,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal di minggu Senin–Sabtu',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    setState(() => _senin = _seninDari(picked));
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final isi = await _repo.isi();
      if (!mounted) return;
      setState(() {
        _semua = isi.buku;
        _semuaRute = isi.rute;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semua = const [];
        _semuaRute = const [];
        _muat = false;
      });
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Margin buku belum bisa dimuat.'
            : pesanGagal(e, 'Margin buku belum bisa dimuat.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tampil = _baris;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Margin buku'),
        actions: [
          IconButton(
            tooltip: 'Gaji minggu ini',
            onPressed: _muat
                ? null
                : () => bukaDialogGaji(
                      context: context,
                      senin: _senin,
                      sabtu: _sabtu,
                      rute: _ruteMinggu,
                    ),
            icon: const Icon(Icons.payments_outlined),
          ),
          IconButton(
            tooltip: 'Pilih minggu',
            onPressed: _muat ? null : _pilihMinggu,
            icon: const Icon(Icons.date_range_outlined),
          ),
        ],
      ),
      drawer: const AdminDrawer(halaman: HalamanAdmin.margin),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 3,
            child: _muat
                ? LinearProgressIndicator(
                    backgroundColor: Tema.biru.withAlpha(30),
                  )
                : const SizedBox.expand(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Text(
              '$_judulMinggu · kotor actual per cap buku. '
              'Rasio = (omset − modal) / modal. '
              'Net = (margin − margin retur − BOP − ongkir) + selisih opname. '
              'Klik selisih opname untuk sesuaikan. Buku hidup belum final.',
              style: const TextStyle(
                fontSize: 13,
                color: Tema.redup,
                height: 1.25,
              ),
            ),
          ),
          Expanded(
            child: tampil.isEmpty && !_muat
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                        child: Text(
                          _semua.isEmpty
                              ? 'Belum ada buku setoran.'
                              : 'Tidak ada buku di minggu ini.',
                          style: const TextStyle(color: Tema.redup),
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _muatData,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final rute = _ruteMinggu;
                        final isi = c.maxWidth - 8;
                        _u = _UkuranTabel(
                          (isi / _lebarDasar).clamp(1.0, 1.45),
                        );
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: c.maxWidth - 8,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _judulBagian('Per buku'),
                                    _tabelBuku(tampil),
                                    if (rute.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          8,
                                          8,
                                          8,
                                          8,
                                        ),
                                        child: Text(
                                          'Tidak ada nota terkirim di rute minggu ini.',
                                          style: TextStyle(color: Tema.redup),
                                        ),
                                      )
                                    else ...[
                                      _judulBagian('Per rute sales'),
                                      _tabelRute(rute),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _judulBagian(String teks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Text(
        teks,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: _u.font,
        ),
      ),
    );
  }

  static const _dasarKolom = <double>[
    176, 96, 56, 52, 118, 118, 118, 64, 118, 108, 108, 118, 118, 100,
  ];
  static final _lebarDasar = _dasarKolom.fold<double>(0, (a, b) => a + b);

  Map<int, TableColumnWidth> get _lebarKolom => {
        for (var i = 0; i < _dasarKolom.length; i++)
          i: FixedColumnWidth(_dasarKolom[i] * _u.skala),
      };

  Widget _selTab(
    String teks, {
    bool tebal = false,
    bool angka = false,
    VoidCallback? onTap,
    bool garis = false,
    bool tengah = false,
  }) {
    var gaya = tebal ? _u.isiTebal : _u.isi;
    if (garis) gaya = gaya.copyWith(decoration: TextDecoration.underline);
    final AlignmentGeometry letak;
    if (tengah) {
      letak = Alignment.center;
    } else if (angka) {
      letak = Alignment.centerRight;
    } else {
      letak = Alignment.centerLeft;
    }
    Widget isi = Align(
      alignment: letak,
      child: Text(
        teks,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: tengah ? TextAlign.center : TextAlign.start,
        style: gaya,
      ),
    );
    isi = SizedBox(
      height: _u.baris,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: isi,
      ),
    );
    if (onTap == null) return isi;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: isi),
    );
  }

  Widget _kepalaTab(String teks) {
    return SizedBox(
      height: _u.baris,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.center,
          child: Text(
            teks,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _u.kepala,
          ),
        ),
      ),
    );
  }

  TableRow _barisKepala(List<String> labels) {
    return TableRow(
      children: [
        for (final label in labels) _kepalaTab(label),
      ],
    );
  }

  Table _tabel(List<TableRow> rows) {
    return Table(
      columnWidths: _lebarKolom,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(width: 0.7, color: Colors.grey.shade300),
      ),
      children: rows,
    );
  }

  Table _tabelBuku(List<BarisMarginBuku> tampil) {
    return _tabel([
      _barisKepala(const [
        'Buku',
        'Tanggal',
        'Status',
        'Nota',
        'Omset',
        'Modal',
        'Margin',
        'Rasio',
        'Margin retur',
        'BOP',
        'Ongkir',
        'Selisih opname',
        'Net margin',
        'Kasbon',
      ]),
      for (final b in tampil) _barisTabel(b),
      if (tampil.isNotEmpty) _barisTotal(tampil),
    ]);
  }

  Table _tabelRute(List<BarisMarginRute> rute) {
    return _tabel([
      _barisKepala(const [
        'Rute',
        'Rute pengirim',
        '',
        'Nota',
        'Omset',
        'Modal',
        'Margin',
        'Rasio',
        'Margin retur',
        'BOP',
        'Ongkir',
        'Selisih opname',
        'Net margin',
        '',
      ]),
      for (final r in rute) _barisRute(r),
      _totalRute(rute),
    ]);
  }

  TableRow _barisRute(BarisMarginRute r) {
    final label = r.nama.isEmpty ? r.rute : '${r.rute} · ${r.nama}';
    return TableRow(
      children: [
        _selTab(label),
        _selTab(
          r.rutePengirim.isEmpty ? '—' : r.rutePengirim,
          tengah: true,
        ),
        _selTab(''),
        _selTab(Uang.angka(r.nota), angka: true),
        _selTab(Uang.rp(r.omset), angka: true),
        _selTab(Uang.rp(r.modal), angka: true),
        _selTab(Uang.rp(r.margin), angka: true),
        _selTab(Uang.rasioOmset(omset: r.omset, modal: r.modal), angka: true),
        _selTab(Uang.rp(r.marginRetur), angka: true),
        _selTab(Uang.rp(r.bop), angka: true),
        _selTab(Uang.rp(r.ongkir), angka: true),
        _selTab(Uang.rp(r.selisihOpname), angka: true),
        _selTab(Uang.rp(r.netMargin), angka: true),
        _selTab(''),
      ],
    );
  }

  TableRow _totalRute(List<BarisMarginRute> rute) {
    var nota = 0;
    var omset = 0;
    var modal = 0;
    var margin = 0;
    var retur = 0;
    var ongkir = 0;
    var bop = 0;
    var selisih = 0;
    var net = 0;
    for (final r in rute) {
      nota += r.nota;
      omset += r.omset;
      modal += r.modal;
      margin += r.margin;
      retur += r.marginRetur;
      ongkir += r.ongkir;
      bop += r.bop;
      selisih += r.selisihOpname;
      net += r.netMargin;
    }
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFE8EAF0)),
      children: [
        _selTab('Total', tebal: true),
        _selTab(''),
        _selTab(''),
        _selTab(Uang.angka(nota), tebal: true, angka: true),
        _selTab(Uang.rp(omset), tebal: true, angka: true),
        _selTab(Uang.rp(modal), tebal: true, angka: true),
        _selTab(Uang.rp(margin), tebal: true, angka: true),
        _selTab(
          Uang.rasioOmset(omset: omset, modal: modal),
          tebal: true,
          angka: true,
        ),
        _selTab(Uang.rp(retur), tebal: true, angka: true),
        _selTab(Uang.rp(bop), tebal: true, angka: true),
        _selTab(Uang.rp(ongkir), tebal: true, angka: true),
        _selTab(Uang.rp(selisih), tebal: true, angka: true),
        _selTab(Uang.rp(net), tebal: true, angka: true),
        _selTab(''),
      ],
    );
  }

  TableRow _barisTabel(BarisMarginBuku b) {
    final tgl = b.tanggal == null ? '—' : Uang.tanggal(b.tanggal!);
    return TableRow(
      decoration: b.ditutup
          ? null
          : BoxDecoration(color: Tema.kuning.withAlpha(40)),
      children: [
        _selTab('${b.id}'),
        _selTab(tgl, tengah: true),
        _selTab(b.ditutup ? 'Tutup' : 'Hidup', tengah: true),
        _selTab(Uang.angka(b.nota), angka: true),
        _selTab(Uang.rp(b.omset), angka: true),
        _selTab(Uang.rp(b.modal), angka: true),
        _selTab(Uang.rp(b.margin), angka: true),
        _selTab(Uang.rasioOmset(omset: b.omset, modal: b.modal), angka: true),
        _selTab(Uang.rp(b.marginRetur), angka: true),
        _selTab(Uang.rp(b.bop), angka: true),
        _selTab(Uang.rp(b.ongkir), angka: true),
        _selTab(
          Uang.rp(b.selisihOpname),
          angka: true,
          tebal: b.selisihOpnameManual,
          garis: true,
          onTap: () => _editSelisihOpname(b),
        ),
        _selTab(Uang.rp(b.netMargin), angka: true),
        _selTab(Uang.rp(b.kasbon), angka: true),
      ],
    );
  }

  Future<void> _editSelisihOpname(BarisMarginBuku b) async {
    final ctrl = TextEditingController(text: Uang.angka(b.selisihOpname));
    final aksi = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Selisih opname buku ${b.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hitungan opname: ${Uang.rp(b.selisihOpnameHitung)}'
                '${b.selisihOpnameManual ? ' · sedang disesuaikan' : ''}',
                style: const TextStyle(color: Tema.redup, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lebih stok menambah, potong margin mengurangi. '
                'Kasbon opname tidak masuk. Rasio tidak berubah.',
                style: TextStyle(fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Nilai',
                  hintText: 'Minus = kurang margin',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'hitung'),
              child: const Text('Pakai hitungan'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'simpan'),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
    if (!mounted || aksi == null) {
      ctrl.dispose();
      return;
    }
    final nilai = _angkaBertanda(ctrl.text);
    ctrl.dispose();
    try {
      await _repo.simpanSelisihOpname(
        id: b.id,
        nilai: nilai,
        manual: aksi == 'simpan',
      );
      await _muatData();
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Selisih opname belum tersimpan.'
            : pesanGagal(e, 'Selisih opname belum tersimpan.'),
      );
    }
  }

  int _angkaBertanda(String s) {
    final t = s.trim().replaceAll('−', '-');
    final neg = t.startsWith('-');
    return neg ? -Uang.angkaTeks(t) : Uang.angkaTeks(t);
  }

  TableRow _barisTotal(List<BarisMarginBuku> tampil) {
    final tutup = tampil.where((b) => b.ditutup);
    var nota = 0;
    var omset = 0;
    var modal = 0;
    var margin = 0;
    var retur = 0;
    var ongkir = 0;
    var bop = 0;
    var kasbon = 0;
    var selisih = 0;
    var net = 0;
    for (final b in tutup) {
      nota += b.nota;
      omset += b.omset;
      modal += b.modal;
      margin += b.margin;
      retur += b.marginRetur;
      ongkir += b.ongkir;
      bop += b.bop;
      kasbon += b.kasbon;
      selisih += b.selisihOpname;
      net += b.netMargin;
    }
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFE8EAF0)),
      children: [
        _selTab('Total', tebal: true),
        _selTab('tutup', tebal: true, tengah: true),
        _selTab(''),
        _selTab(Uang.angka(nota), tebal: true, angka: true),
        _selTab(Uang.rp(omset), tebal: true, angka: true),
        _selTab(Uang.rp(modal), tebal: true, angka: true),
        _selTab(Uang.rp(margin), tebal: true, angka: true),
        _selTab(
          Uang.rasioOmset(omset: omset, modal: modal),
          tebal: true,
          angka: true,
        ),
        _selTab(Uang.rp(retur), tebal: true, angka: true),
        _selTab(Uang.rp(bop), tebal: true, angka: true),
        _selTab(Uang.rp(ongkir), tebal: true, angka: true),
        _selTab(Uang.rp(selisih), tebal: true, angka: true),
        _selTab(Uang.rp(net), tebal: true, angka: true),
        _selTab(Uang.rp(kasbon), tebal: true, angka: true),
      ],
    );
  }
}

class _UkuranTabel {
  const _UkuranTabel(this.skala);

  final double skala;

  double get baris => 32 * skala;
  double get font => 13 * skala;

  TextStyle get isi => TextStyle(fontSize: font, height: 1.2);
  TextStyle get isiTebal => TextStyle(
        fontSize: font,
        height: 1.2,
        fontWeight: FontWeight.w700,
      );
  TextStyle get kepala => TextStyle(
        fontSize: font,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      );
}
