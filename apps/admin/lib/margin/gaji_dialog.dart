import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dashboard/dashboard_repo.dart';
import '../jaringan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'gaji_repo.dart';
import 'margin_repo.dart';

Future<void> bukaDialogGaji({
  required BuildContext context,
  required DateTime senin,
  required DateTime sabtu,
  required List<BarisMarginRute> rute,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _DialogGaji(senin: senin, sabtu: sabtu, rute: rute),
  );
}

class _DialogGaji extends StatefulWidget {
  const _DialogGaji({
    required this.senin,
    required this.sabtu,
    required this.rute,
  });

  final DateTime senin;
  final DateTime sabtu;
  final List<BarisMarginRute> rute;

  @override
  State<_DialogGaji> createState() => _DialogGajiState();
}

class _DialogGajiState extends State<_DialogGaji> {
  final _repo = GajiRepo(Supabase.instance.client);
  final _ctrl = <String, TextEditingController>{};
  final _gulirTegak = ScrollController();
  static const _selaSales = 2.0;
  static const _selaKananKolom = 8.0;
  static const _selaKananTerima = 16.0;
  bool _sibuk = false;
  bool _muat = true;
  String? _gagal;
  IsiGaji? _isi;
  GajiSetelan _setelan = GajiSetelan.awal;
  IsiDashboard? _dash;
  List<GajiAbsen> _absen = const [];
  List<double>? _lebarSalesDasar;
  List<double>? _lebarBawahDasar;
  double _ukurSkala = 0;

  @override
  void initState() {
    super.initState();
    _pasangField(_setelan);
    _dash = _drafDash();
    _isi = hitungGaji(
      setelan: _setelan,
      ruteMargin: widget.rute,
      dash: _dash!,
      absen: const [],
    );
    _pasangTarget(_isi!.sales, timpa: true);
    _muatAwal();
  }

  IsiDashboard _drafDash() {
    return IsiDashboard(
      senin: widget.senin,
      sabtu: widget.sabtu,
      hari: widget.sabtu,
      total: KartuDash.totalKosong,
      rute: [
        for (final r in widget.rute)
          KartuDash(
            rute: r.rute,
            nama: r.nama,
            targetOmset: 0,
            targetPersen: 0,
            minggu: CapaianDash.kosong,
            hari: CapaianDash.kosong,
          ),
      ],
    );
  }

  Future<void> _muatAwal() async {
    try {
      final hasil = await Future.wait<Object>([
        _repo.setelan(),
        _repo.dashboard(senin: widget.senin, hari: widget.sabtu),
        _repo.absen(senin: widget.senin, sabtu: widget.sabtu),
        _repo.kasbon(senin: widget.senin, sabtu: widget.sabtu),
      ]);
      if (!mounted) return;
      final setelan = hasil[0] as GajiSetelan;
      final dash = hasil[1] as IsiDashboard;
      final absen = hasil[2] as List<GajiAbsen>;
      final kasbon = hasil[3] as Map<String, int>;
      final isi = hitungGaji(
        setelan: setelan,
        ruteMargin: widget.rute,
        dash: dash,
        absen: absen,
        kasbonOrang: kasbon,
      );
      _pasangField(setelan);
      _pasangTarget(isi.sales, timpa: true);
      _pasangKasbon([
        ...isi.pengirim,
        ...isi.gudang,
        ...isi.admin,
      ], timpa: true);
      _buangUkur();
      setState(() {
        _setelan = setelan;
        _dash = dash;
        _absen = absen;
        _isi = isi;
        _gagal = null;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _muat = false;
        _gagal = Jaringan.mati(e)
            ? 'Tidak ada internet. Gaji belum bisa dihitung.'
            : pesanGagal(e, 'Gaji belum bisa dihitung. Jalankan SQL 116.');
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _gulirTegak.dispose();
    super.dispose();
  }

  void _pasangField(GajiSetelan s) {
    void p(String k, int n) {
      final c = _ctrl[k];
      if (c == null) {
        _ctrl[k] = TextEditingController(text: Uang.angka(n));
      } else {
        c.text = Uang.angka(n);
      }
    }

    p('bop', s.bopMobil);
    p('ongkir', s.ongkirSemua);
    p('snet', s.salesNet);
    p('svis', s.salesVisit);
    p('sec', s.salesEc);
    p('kirim', s.pengirim);
    p('gud', s.gudang);
    p('slot', s.gudangSlot);
    p('adm', s.admin);
  }

  TextEditingController _c(String k, int n) {
    return _ctrl.putIfAbsent(
      k,
      () => TextEditingController(text: Uang.angka(n)),
    );
  }

  GajiSetelan _dariField() {
    int n(String k, int cad) =>
        _ctrl[k] == null ? cad : Uang.angkaTeks(_ctrl[k]!.text);
    return GajiSetelan(
      bopMobil: n('bop', _setelan.bopMobil),
      ongkirSemua: n('ongkir', _setelan.ongkirSemua),
      salesNet: n('snet', _setelan.salesNet),
      salesVisit: n('svis', _setelan.salesVisit),
      salesEc: n('sec', _setelan.salesEc),
      pengirim: n('kirim', _setelan.pengirim),
      gudang: n('gud', _setelan.gudang),
      gudangSlot: n('slot', _setelan.gudangSlot).clamp(1, 99),
      admin: n('adm', _setelan.admin),
      omsetSemua: 0,
      rasioSales: 0,
    );
  }

  String _kunciOmset(String rute) => 'o:$rute';
  String _kunciRasio(String rute) => 'r:$rute';
  String _kunciKasbon(BarisGajiOrang o) =>
      'kb:${kunciKasbon(o.email, o.rute, o.nama)}';

  String _teksRasio(double n) =>
      n == 0 ? '0' : n.toStringAsFixed(2).replaceAll('.', ',');

  void _pasangTarget(List<BarisGajiSales> list, {required bool timpa}) {
    void p(String k, String t) {
      final c = _ctrl[k];
      if (c == null) {
        _ctrl[k] = TextEditingController(text: t);
      } else if (timpa) {
        c.text = t;
      }
    }

    for (final s in list) {
      p(_kunciOmset(s.rute), Uang.angka(s.omsetTarget));
      p(_kunciRasio(s.rute), _teksRasio(s.rasioTarget));
    }
  }

  void _pasangKasbon(List<BarisGajiOrang> list, {required bool timpa}) {
    void p(String k, String t) {
      final c = _ctrl[k];
      if (c == null) {
        _ctrl[k] = TextEditingController(text: t);
      } else if (timpa) {
        c.text = t;
      }
    }

    for (final o in list) {
      p(_kunciKasbon(o), Uang.angka(o.kasbon));
    }
  }

  Map<String, int> _kasbonDariField() {
    final orang = [...?_isi?.pengirim, ...?_isi?.gudang, ...?_isi?.admin];
    return {
      for (final o in orang)
        kunciKasbon(o.email, o.rute, o.nama): Uang.angkaTeks(
          _ctrl[_kunciKasbon(o)]?.text ?? '',
        ),
    };
  }

  Map<String, int> _omsetDariField() {
    return {
      for (final s in _isi?.sales ?? const <BarisGajiSales>[])
        s.rute: Uang.angkaTeks(_ctrl[_kunciOmset(s.rute)]?.text ?? ''),
    };
  }

  Map<String, double> _rasioDariField() {
    return {
      for (final s in _isi?.sales ?? const <BarisGajiSales>[])
        s.rute: Uang.qtyTeks(_ctrl[_kunciRasio(s.rute)]?.text ?? '').toDouble(),
    };
  }

  List<Map<String, Object>> _targetUntukSimpan() {
    return [
      for (final s in _isi?.sales ?? const <BarisGajiSales>[])
        {
          'rute': s.rute,
          'omset': Uang.angkaTeks(_ctrl[_kunciOmset(s.rute)]?.text ?? ''),
          'rasio': Uang.qtyTeks(_ctrl[_kunciRasio(s.rute)]?.text ?? '')
              .toDouble(),
        },
    ];
  }

  List<Map<String, Object>> _kasbonUntukSimpan() {
    final orang = [...?_isi?.pengirim, ...?_isi?.gudang, ...?_isi?.admin];
    return [
      for (final o in orang)
        if (o.email.trim().isNotEmpty)
          {
            'email': o.email.trim().toLowerCase(),
            'nilai': Uang.angkaTeks(_ctrl[_kunciKasbon(o)]?.text ?? ''),
          },
    ];
  }

  void _hitungUlang() {
    final isi = _isi;
    final dash = _dash;
    if (isi == null || dash == null) return;
    final s = _dariField();
    setState(() {
      _setelan = s;
      _isi = hitungGaji(
        setelan: s,
        ruteMargin: widget.rute,
        dash: dash,
        absen: _absen,
        omsetRute: _omsetDariField(),
        rasioRute: _rasioDariField(),
        kasbonOrang: _kasbonDariField(),
      );
      _buangUkur();
    });
  }

  Future<void> _simpan() async {
    if (_sibuk) return;
    final s = _dariField();
    setState(() => _sibuk = true);
    try {
      await _repo.simpan(s);
      final target = _targetUntukSimpan();
      if (target.isNotEmpty) {
        await _repo.simpanTarget(target);
      }
      if (!mounted) return;
      tampilPesan(context, 'Patokan gaji dan target sales tersimpan.');
      _hitungUlang();
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Patokan belum tersimpan.'
            : pesanGagal(
                e,
                'Patokan belum tersimpan. Jalankan SQL 116 dan 118.',
              ),
      );
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _simpanKasbon() async {
    if (_sibuk) return;
    final isi = _kasbonUntukSimpan();
    if (isi.isEmpty) {
      tampilPesan(context, 'Tidak ada email kasbon yang bisa disimpan.');
      return;
    }
    setState(() => _sibuk = true);
    try {
      await _repo.simpanKasbonMinggu(senin: widget.senin, isi: isi);
      if (!mounted) return;
      tampilPesan(context, 'Kasbon gaji minggu ini tersimpan.');
      _hitungUlang();
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Kasbon gaji belum tersimpan.'
            : pesanGagal(e, 'Kasbon gaji belum tersimpan. Jalankan SQL 122.'),
      );
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layar = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: layar.width - 20,
          maxWidth: layar.width - 20,
          maxHeight: layar.height - 20,
        ),
        child: Column(
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
            if (_gagal != null && !_muat)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(
                  _gagal!,
                  style: TextStyle(color: Tema.redup, fontSize: _font),
                ),
              ),
            if (_isi != null)
              Flexible(
                child: AbsorbPointer(
                  absorbing: _muat,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final isi = _isi!;
                      final skala = _skala;
                      if (_lebarSalesDasar == null ||
                          _lebarBawahDasar == null ||
                          _ukurSkala != skala) {
                        _ukurSkala = skala;
                        _lebarSalesDasar = _angkaKolom12(isi);
                        _lebarBawahDasar = _angkaKolomBawah(isi);
                      }
                      var sales = _lebarSalesDasar!;
                      var bawah = _lebarBawahDasar!;
                      final jum = math.max(
                        sales.fold<double>(0, (a, b) => a + b),
                        bawah.fold<double>(0, (a, b) => a + b),
                      );
                      final maxW = math.max(c.maxWidth - 12, 1.0);
                      final k = jum > maxW ? maxW / jum : 1.0;
                      if (k < 1) {
                        sales = [for (final x in sales) x * k];
                        bawah = [for (final x in bawah) x * k];
                      }
                      return Scrollbar(
                        controller: _gulirTegak,
                        child: SingleChildScrollView(
                          controller: _gulirTegak,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _kepala(),
                                _tabelSales(isi, sales),
                                _tabelBawah(isi, bawah),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _ringkasPerusahaan(isi),
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  Widget _kepala() {
    return SizedBox(
      height: _baris,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                'Gaji · ${Uang.pendek(widget.senin)} – ${Uang.tanggal(widget.sabtu)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: _font),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: (_sibuk || _muat || _isi == null)
                      ? null
                      : _simpanKasbon,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: TextStyle(fontSize: _font),
                  ),
                  child: const Text('Simpan kasbon'),
                ),
                TextButton(
                  onPressed: (_sibuk || _muat) ? null : _simpan,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: TextStyle(fontSize: _font),
                  ),
                  child: const Text('Simpan patokan'),
                ),
                TextButton(
                  onPressed: (_sibuk || _muat || _isi == null)
                      ? null
                      : _hitungUlang,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: TextStyle(fontSize: _font),
                  ),
                  child: const Text('Hitung'),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double get _skala {
    final w = MediaQuery.sizeOf(context).width - 20;
    return (w / 1468).clamp(1.0, 1.12);
  }

  double get _font => 13 * _skala;
  double get _baris => 33 * _skala;
  TextStyle get _gayaIsi => TextStyle(fontSize: _font, height: 1.1);
  TextStyle get _gayaKepala => TextStyle(
    fontSize: _font,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  Widget _ringkasPerusahaan(IsiGaji isi) {
    const sela = SizedBox(width: 24);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Net actual ${Uang.rp(isi.netActual)}',
          style: _gayaKepala,
          textAlign: TextAlign.left,
        ),
        sela,
        Text(
          'Gaji semua ${Uang.rp(isi.gajiSemua)}',
          style: _gayaKepala,
          textAlign: TextAlign.left,
        ),
        sela,
        Text(
          'Sisa perusahaan ${Uang.rp(isi.sisaPerusahaan)}',
          style: _gayaKepala,
          textAlign: TextAlign.left,
        ),
      ],
    );
  }

  static const _patokanIsi = [
    ('BOP / mobil', 'bop'),
    ('Ongkir semua', 'ongkir'),
    ('Sales net', 'snet'),
    ('Sales visit', 'svis'),
    ('Sales EC', 'sec'),
    ('Pengirim', 'kirim'),
    ('Gudang', 'gud'),
    ('Slot gudang', 'slot'),
    ('Admin', 'adm'),
  ];

  static const _dekorKecil = InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    border: OutlineInputBorder(),
  );

  void _buangUkur() {
    _lebarSalesDasar = null;
    _lebarBawahDasar = null;
  }

  /// 4 px di atas/bawah garis field ke garis antar baris. Tinggi baris tidak diubah.
  Widget _fieldDalamBaris(Widget field, {bool selaLintang = true}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: selaLintang ? 4 : 0,
        vertical: 4,
      ),
      child: SizedBox(height: _baris - 8, child: field),
    );
  }

  double _lebarAngka(String teks, {double min = 40}) {
    final tp = TextPainter(
      text: TextSpan(text: teks, style: _gayaIsi),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width + 14;
    tp.dispose();
    return w < min ? min : w;
  }

  double _lebarKolom(
    String kepala,
    Iterable<String> isi, {
    bool field = false,
    double ekstra = 0,
  }) {
    var w = _ukurTeks(kepala, _gayaKepala);
    for (final t in isi) {
      final n = field ? _lebarAngka(t, min: 32) : _ukurTeks(t, _gayaIsi);
      if (n > w) w = n;
    }
    return w + ekstra;
  }

  List<String> _teksOrang(List<BarisGajiOrang> list, {required String jenis}) {
    return [
      for (final o in list)
        switch (jenis) {
          'nama' => _judulOrang(o),
          'absen' => '${o.hari}',
          'gaji' => Uang.rp(o.gaji),
          'kasbon' => _ctrl[_kunciKasbon(o)]?.text ?? Uang.angka(o.kasbon),
          'terima' => Uang.rp(
            o.gaji -
                (_ctrl[_kunciKasbon(o)] == null
                    ? o.kasbon
                    : Uang.angkaTeks(_ctrl[_kunciKasbon(o)]!.text)),
          ),
          _ => '',
        },
    ];
  }

  ({
    int omset,
    String rasio,
    int netT,
    int netA,
    double pct,
    int benNet,
    int visit,
    int toko,
    int benV,
    int ec,
    int benE,
    int total,
  })
  _totSales(IsiGaji isi) {
    var omset = 0;
    var rasioW = 0.0;
    var netT = 0;
    var netA = 0;
    var benNet = 0;
    var visit = 0;
    var toko = 0;
    var benV = 0;
    var ec = 0;
    var benE = 0;
    var total = 0;
    for (final s in isi.sales) {
      final o = Uang.angkaTeks(
        _ctrl[_kunciOmset(s.rute)]?.text ?? Uang.angka(s.omsetTarget),
      );
      final r = Uang.qtyTeks(_ctrl[_kunciRasio(s.rute)]?.text ?? '').toDouble();
      omset += o;
      rasioW += o * r;
      netT += s.netTarget;
      netA += s.netActual;
      benNet += s.benNet;
      visit += s.visit;
      toko += s.toko;
      benV += s.benVisit;
      ec += s.ec;
      benE += s.benEc;
      total += s.total;
    }
    return (
      omset: omset,
      rasio: _teksRasio(omset == 0 ? 0 : rasioW / omset),
      netT: netT,
      netA: netA,
      pct: netT == 0 ? 0.0 : netA / netT,
      benNet: benNet,
      visit: visit,
      toko: toko,
      benV: benV,
      ec: ec,
      benE: benE,
      total: total,
    );
  }

  List<double> _angkaKolom12(IsiGaji isi) {
    final t = _totSales(isi);
    return [
      _lebarKolom('Rute sales', [
        for (final s in isi.sales)
          s.nama.isEmpty ? s.rute : '${s.rute} · ${s.nama}',
        'Total',
      ]),
      _lebarKolom('Omset target', [
        '000.000.000',
        Uang.angka(t.omset),
        for (final s in isi.sales)
          _ctrl[_kunciOmset(s.rute)]?.text ?? Uang.angka(s.omsetTarget),
      ], field: true),
      _lebarKolom('Rasio %', [
        '00,00',
        t.rasio,
        for (final s in isi.sales) _ctrl[_kunciRasio(s.rute)]?.text ?? '0',
      ], field: true),
      _lebarKolom('Net target', [
        Uang.rp(t.netT),
        for (final s in isi.sales) Uang.rp(s.netTarget),
      ]),
      _lebarKolom('Net actual', [
        Uang.rp(t.netA),
        for (final s in isi.sales) Uang.rp(s.netActual),
      ]),
      _lebarKolom('Net %', [
        teksRasioGaji(t.pct),
        for (final s in isi.sales) teksRasioGaji(s.pctNet),
      ]),
      _lebarKolom('Ben. net', [
        Uang.rp(t.benNet),
        for (final s in isi.sales) Uang.rp(s.benNet),
      ]),
      _lebarKolom('Visit', [
        '${t.visit}/${t.toko}',
        for (final s in isi.sales) '${s.visit}/${s.toko}',
      ]),
      _lebarKolom('Ben. visit', [
        Uang.rp(t.benV),
        for (final s in isi.sales) Uang.rp(s.benVisit),
      ]),
      _lebarKolom('EC', ['${t.ec}', for (final s in isi.sales) '${s.ec}']),
      _lebarKolom('Ben. EC', [
        Uang.rp(t.benE),
        for (final s in isi.sales) Uang.rp(s.benEc),
      ]),
      _lebarKolom('Total', [
        Uang.rp(t.total),
        for (final s in isi.sales) Uang.rp(s.total),
      ]),
    ];
  }

  List<double> _angkaKolomBawah(IsiGaji isi) {
    int totGaji(List<BarisGajiOrang> list) {
      var n = 0;
      for (final o in list) {
        n += o.gaji;
      }
      return n;
    }

    int totKasbon(List<BarisGajiOrang> list) {
      var n = 0;
      for (final o in list) {
        final c = _ctrl[_kunciKasbon(o)];
        n += c == null ? o.kasbon : Uang.angkaTeks(c.text);
      }
      return n;
    }

    List<double> blok(
      List<BarisGajiOrang> list,
      String judul, {
      required bool absen,
    }) {
      final gaji = totGaji(list);
      final kb = totKasbon(list);
      final out = <double>[
        _lebarKolom(judul, [..._teksOrang(list, jenis: 'nama'), 'Total']),
      ];
      if (absen) {
        out.add(_lebarKolom('Absen', _teksOrang(list, jenis: 'absen')));
      }
      out.addAll([
        _lebarKolom('Gaji', [
          ..._teksOrang(list, jenis: 'gaji'),
          Uang.rp(gaji),
        ], ekstra: _selaKananKolom),
        _lebarKolom('Kasbon', [
          ..._teksOrang(list, jenis: 'kasbon'),
          Uang.angka(kb),
          '0.000.000',
        ], field: true),
        _lebarKolom('Terima', [
          ..._teksOrang(list, jenis: 'terima'),
          Uang.rp(gaji - kb),
        ], ekstra: _selaKananTerima),
      ]);
      return out;
    }

    final patokan = _ukurTeks('Ongkir semua', _gayaIsi) + 4 + _lebarPatokan();
    return [
      ...blok(isi.pengirim, 'Rute pengirim', absen: true),
      ...blok(isi.gudang, 'Rute gudang', absen: true),
      ...blok(isi.admin, 'Rute admin', absen: false),
      patokan,
    ];
  }

  Map<int, TableColumnWidth> _petaKolom(List<double> w) {
    return {for (var i = 0; i < w.length; i++) i: FixedColumnWidth(w[i])};
  }

  double _lebarPatokan() {
    var panjang = '';
    for (final k in const [
      'bop',
      'ongkir',
      'snet',
      'svis',
      'sec',
      'kirim',
      'gud',
      'slot',
      'adm',
    ]) {
      final t = _ctrl[k]?.text ?? '';
      if (t.length > panjang.length) panjang = t;
    }
    return _lebarAngka(panjang, min: 72);
  }

  Widget _fieldPatokan(int i) {
    if (i < 0 || i >= _patokanIsi.length) return _selKosong();
    final (label, kunci) = _patokanIsi[i];
    final awal = switch (kunci) {
      'bop' => _setelan.bopMobil,
      'ongkir' => _setelan.ongkirSemua,
      'snet' => _setelan.salesNet,
      'svis' => _setelan.salesVisit,
      'sec' => _setelan.salesEc,
      'kirim' => _setelan.pengirim,
      'gud' => _setelan.gudang,
      'slot' => _setelan.gudangSlot,
      'adm' => _setelan.admin,
      _ => 0,
    };
    return SizedBox(
      height: _baris,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: _font, color: Tema.redup),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _fieldDalamBaris(
              TextField(
                controller: _c(kunci, awal),
                style: _gayaIsi,
                expands: true,
                maxLines: null,
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.number,
                inputFormatters: const [UangFormatRibuan()],
                decoration: _dekorKecil,
              ),
              selaLintang: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _selOmset(String rute) {
    return _fieldDalamBaris(
      TextField(
        controller: _c(_kunciOmset(rute), 0),
        style: _gayaIsi,
        expands: true,
        maxLines: null,
        textAlign: TextAlign.right,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.number,
        inputFormatters: const [UangFormatRibuan()],
        decoration: _dekorKecil,
      ),
    );
  }

  Widget _selRasio(String rute) {
    return _fieldDalamBaris(
      TextField(
        controller: _ctrl.putIfAbsent(
          _kunciRasio(rute),
          () => TextEditingController(text: '0'),
        ),
        style: _gayaIsi,
        expands: true,
        maxLines: null,
        textAlign: TextAlign.right,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: _dekorKecil,
      ),
    );
  }

  Widget _selSales(
    String teks, {
    bool angka = true,
    bool tebal = false,
    bool kepala = false,
    bool abu = false,
    double? padKanan,
  }) {
    final kanan = padKanan ?? _selaSales / 2;
    final align = kepala
        ? TextAlign.center
        : (angka ? TextAlign.right : TextAlign.left);
    final isi = SizedBox(
      height: _baris,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_selaSales / 2, 0, kanan, 0),
        child: Align(
          alignment: kepala
              ? Alignment.center
              : (angka ? Alignment.centerRight : Alignment.centerLeft),
          child: Text(
            teks,
            style: kepala || tebal ? _gayaKepala : _gayaIsi,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ),
    );
    if (!abu) return isi;
    return ColoredBox(color: const Color(0xFFE8EAF0), child: isi);
  }

  Widget _selSelaKanan(
    String teks, {
    bool kepala = false,
    bool tebal = false,
    bool abu = false,
    double selaKanan = _selaKananKolom,
  }) {
    return _selSales(
      teks,
      kepala: kepala,
      tebal: tebal,
      abu: abu,
      padKanan: _selaSales / 2 + selaKanan,
    );
  }

  Widget _selKosong({bool abu = false}) {
    final isi = SizedBox(height: _baris, width: double.infinity);
    if (!abu) return isi;
    return ColoredBox(color: const Color(0xFFE8EAF0), child: isi);
  }

  double _ukurTeks(String teks, TextStyle gaya, {double ekstra = 0}) {
    final tp = TextPainter(
      text: TextSpan(text: teks, style: gaya),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width + _selaSales + ekstra;
    tp.dispose();
    return w;
  }

  Widget _tabelSales(IsiGaji isi, List<double> lebar) {
    final t = _totSales(isi);
    const garis = BorderSide(width: 0.5, color: Color(0xFFD0D4DC));
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: _petaKolom(lebar),
      border: const TableBorder(horizontalInside: garis, bottom: garis),
      children: [
        TableRow(
          children: [
            _selSales('Rute sales', angka: false, kepala: true),
            _selSales('Omset target', kepala: true),
            _selSales('Rasio %', kepala: true),
            _selSales('Net target', kepala: true),
            _selSales('Net actual', kepala: true),
            _selSales('Net %', kepala: true),
            _selSales('Ben. net', kepala: true),
            _selSales('Visit', kepala: true),
            _selSales('Ben. visit', kepala: true),
            _selSales('EC', kepala: true),
            _selSales('Ben. EC', kepala: true),
            _selSales('Total', kepala: true),
          ],
        ),
        for (final s in isi.sales)
          TableRow(
            children: [
              _selSales(
                s.nama.isEmpty ? s.rute : '${s.rute} · ${s.nama}',
                angka: false,
              ),
              _selOmset(s.rute),
              _selRasio(s.rute),
              _selSales(Uang.rp(s.netTarget)),
              _selSales(Uang.rp(s.netActual)),
              _selSales(teksRasioGaji(s.pctNet)),
              _selSales(Uang.rp(s.benNet)),
              _selSales('${s.visit}/${s.toko}'),
              _selSales(Uang.rp(s.benVisit)),
              _selSales('${s.ec}'),
              _selSales(Uang.rp(s.benEc)),
              _selSales(Uang.rp(s.total)),
            ],
          ),
        TableRow(
          children: [
            _selSales('Total', angka: false, tebal: true, abu: true),
            _selSales(Uang.rp(t.omset), tebal: true, abu: true),
            _selSales(t.rasio, tebal: true, abu: true),
            _selSales(Uang.rp(t.netT), tebal: true, abu: true),
            _selSales(Uang.rp(t.netA), tebal: true, abu: true),
            _selSales(teksRasioGaji(t.pct), tebal: true, abu: true),
            _selSales(Uang.rp(t.benNet), tebal: true, abu: true),
            _selSales('${t.visit}/${t.toko}', tebal: true, abu: true),
            _selSales(Uang.rp(t.benV), tebal: true, abu: true),
            _selSales('${t.ec}', tebal: true, abu: true),
            _selSales(Uang.rp(t.benE), tebal: true, abu: true),
            _selSales(Uang.rp(t.total), tebal: true, abu: true),
          ],
        ),
      ],
    );
  }

  Widget _selKasbon(BarisGajiOrang o, {bool abu = false}) {
    final isi = _fieldDalamBaris(
      TextField(
        controller: _c(_kunciKasbon(o), o.kasbon),
        style: _gayaIsi,
        expands: true,
        maxLines: null,
        textAlign: TextAlign.right,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.number,
        inputFormatters: const [UangFormatRibuan()],
        decoration: _dekorKecil,
        onChanged: (_) {
          if (mounted) setState(() {});
        },
      ),
    );
    if (!abu) return isi;
    return ColoredBox(color: const Color(0xFFE8EAF0), child: isi);
  }

  List<Widget> _selBlokOrang(
    List<BarisGajiOrang> list,
    int i, {
    required bool tampilAbsen,
  }) {
    var tot = 0;
    var totKasbon = 0;
    for (final o in list) {
      tot += o.gaji;
      final c = _ctrl[_kunciKasbon(o)];
      totKasbon += c == null ? o.kasbon : Uang.angkaTeks(c.text);
    }
    final totTerima = tot - totKasbon;
    if (i < list.length) {
      final o = list[i];
      final c = _ctrl[_kunciKasbon(o)];
      final kb = c == null ? o.kasbon : Uang.angkaTeks(c.text);
      return [
        _selSales(_judulOrang(o), angka: false),
        if (tampilAbsen) _selSales('${o.hari}'),
        _selSelaKanan(Uang.rp(o.gaji)),
        _selKasbon(o),
        _selSelaKanan(Uang.rp(o.gaji - kb), selaKanan: _selaKananTerima),
      ];
    }
    if (i == list.length) {
      return [
        _selSales('Total', angka: false, tebal: true, abu: true),
        if (tampilAbsen) _selKosong(abu: true),
        _selSelaKanan(Uang.rp(tot), tebal: true, abu: true),
        _selSales(Uang.rp(totKasbon), tebal: true, abu: true),
        _selSelaKanan(
          Uang.rp(totTerima),
          tebal: true,
          abu: true,
          selaKanan: _selaKananTerima,
        ),
      ];
    }
    return [
      _selKosong(),
      if (tampilAbsen) _selKosong(),
      _selKosong(),
      _selKosong(),
      _selKosong(),
    ];
  }

  Widget _tabelBawah(IsiGaji isi, List<double> lebar) {
    final n = [
      isi.pengirim.length + 1,
      isi.gudang.length + 1,
      isi.admin.length + 1,
      _patokanIsi.length,
    ].reduce(math.max);
    const garis = BorderSide(width: 0.5, color: Color(0xFFD0D4DC));
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: _petaKolom(lebar),
      border: const TableBorder(horizontalInside: garis, bottom: garis),
      children: [
        TableRow(
          children: [
            _selSales('Rute pengirim', angka: false, kepala: true),
            _selSales('Absen', kepala: true),
            _selSelaKanan('Gaji', kepala: true),
            _selSales('Kasbon', kepala: true),
            _selSelaKanan('Terima', kepala: true, selaKanan: _selaKananTerima),
            _selSales('Rute gudang', angka: false, kepala: true),
            _selSales('Absen', kepala: true),
            _selSelaKanan('Gaji', kepala: true),
            _selSales('Kasbon', kepala: true),
            _selSelaKanan('Terima', kepala: true, selaKanan: _selaKananTerima),
            _selSales('Rute admin', angka: false, kepala: true),
            _selSelaKanan('Gaji', kepala: true),
            _selSales('Kasbon', kepala: true),
            _selSelaKanan('Terima', kepala: true, selaKanan: _selaKananTerima),
            _selKosong(),
          ],
        ),
        for (var i = 0; i < n; i++)
          TableRow(
            children: [
              ..._selBlokOrang(isi.pengirim, i, tampilAbsen: true),
              ..._selBlokOrang(isi.gudang, i, tampilAbsen: true),
              ..._selBlokOrang(isi.admin, i, tampilAbsen: false),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _selaSales / 2),
                child: _fieldPatokan(i),
              ),
            ],
          ),
      ],
    );
  }

  String _judulOrang(BarisGajiOrang o) {
    if (o.rute.isEmpty) return o.nama.isEmpty ? '—' : o.nama;
    if (o.nama.isEmpty) return o.rute;
    return '${o.rute} · ${o.nama}';
  }
}
