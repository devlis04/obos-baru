import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/admin_drawer.dart';
import '../jaringan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'dashboard_repo.dart';
import 'dialog_toko_dash.dart';

class DashboardLayar extends StatefulWidget {
  const DashboardLayar({super.key});

  @override
  State<DashboardLayar> createState() => _DashboardLayarState();
}

class _DashboardLayarState extends State<DashboardLayar> {
  final _repo = DashboardRepo(Supabase.instance.client);
  bool _muat = true;
  bool _tokoBuka = false;
  late DateTime _senin;
  late DateTime _hari;
  IsiDashboard _isi = IsiDashboard.kosong(DateTime(2000), DateTime(2000));

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    var hari = DateTime(now.year, now.month, now.day);
    if (hari.weekday == DateTime.sunday) {
      hari = hari.subtract(const Duration(days: 1));
    }
    _hari = hari;
    _senin = _seninDari(_hari);
    _isi = IsiDashboard.kosong(_senin, _hari);
    _muatData();
  }

  DateTime _seninDari(DateTime w) {
    final h = DateTime(w.year, w.month, w.day);
    return h.subtract(Duration(days: h.weekday - 1));
  }

  bool get _mingguIni {
    final s = _seninDari(DateTime.now());
    return s.year == _senin.year &&
        s.month == _senin.month &&
        s.day == _senin.day;
  }

  bool get _hariIni {
    final n = DateTime.now();
    return n.year == _hari.year && n.month == _hari.month && n.day == _hari.day;
  }

  String get _judulMinggu {
    if (_mingguIni) return 'Pencapaian minggu ini';
    return 'Pencapaian ${Uang.pendek(_senin)} – ${Uang.tanggal(_isi.sabtu)}';
  }

  String get _judulHari {
    if (_hariIni) return 'Pencapaian hari ini';
    return 'Pencapaian ${Uang.hariTanggal(_hari)}';
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final isi = await _repo.isi(senin: _senin, hari: _hari);
      if (!mounted) return;
      setState(() {
        _isi = isi;
        _senin = isi.senin;
        _hari = isi.hari;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Dashboard belum bisa dimuat.'
            : pesanGagal(e, 'Dashboard belum bisa dimuat.'),
      );
    }
  }

  Future<void> _bukaTokoHari(KartuDash k) async {
    if (_muat || _tokoBuka || k.rute.isEmpty) return;
    setState(() => _tokoBuka = true);
    try {
      await bukaTokoDash(
        context: context,
        hari: _hari,
        rute: k.rute,
        nama: k.nama,
      );
    } finally {
      if (mounted) setState(() => _tokoBuka = false);
    }
  }

  DateTime _jepitHariKeMinggu(DateTime hari, DateTime senin) {
    final sabtu = senin.add(const Duration(days: 5));
    if (hari.isBefore(senin)) return senin;
    if (hari.isAfter(sabtu)) return sabtu;
    return hari;
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
    final senin = _seninDari(picked);
    setState(() {
      _senin = senin;
      _hari = _jepitHariKeMinggu(_hari, senin);
    });
    await _muatData();
  }

  Future<void> _pilihHari() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hari,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal pencapaian',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    final hari = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _hari = hari;
      _senin = _seninDari(hari);
    });
    await _muatData();
  }

  double _persenLaba(int omset, int laba) {
    final modal = omset - laba;
    if (omset <= 0 || modal <= 0) return 0;
    return (laba / modal) * 100;
  }

  String _teksRasio(int omset, int laba) {
    return '${_persenLaba(omset, laba).toStringAsFixed(2)}%';
  }

  double _pct(num nilai, num target) {
    if (target <= 0) return 0;
    return nilai / target;
  }

  static const _lebarIsiTotal = 280.0;
  static const _lebarKartuKiri = 292.0;
  static const _teks = 14.0;
  static const _teksIsi = 12.0;
  static const _ikonKalender = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    minimumSize: WidgetStatePropertyAll(Size(32, 32)),
    maximumSize: WidgetStatePropertyAll(Size(32, 32)),
  );

  List<(KartuDash?, KartuDash?)> _pasanganRute() {
    final list = [..._isi.rute]
      ..sort((a, b) => a.rute.toLowerCase().compareTo(b.rute.toLowerCase()));
    final out = <(KartuDash?, KartuDash?)>[];
    for (var i = 0; i < list.length; i += 2) {
      out.add((list[i], i + 1 < list.length ? list[i + 1] : null));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Segarkan',
            onPressed: _muat ? null : _muatData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const AdminDrawer(halaman: HalamanAdmin.dashboard),
      body: RepaintBoundary(
        child: Column(
        children: [
          SizedBox(
            height: 3,
            child: _muat
                ? LinearProgressIndicator(
                    backgroundColor: theme.colorScheme.primary.withAlpha(30),
                  )
                : const SizedBox.expand(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _muatData,
              child: LayoutBuilder(
                builder: (context, c) {
                  final duaSisi = c.maxWidth >= 980;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: c.maxHeight,
                      width: c.maxWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: duaSisi
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _kolomTotal(theme),
                                  const SizedBox(width: 8),
                                  Expanded(child: _kolomRute()),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 11, child: _kolomTotal(theme)),
                                  const SizedBox(height: 6),
                                  Expanded(flex: 12, child: _kolomRute()),
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

  Widget _kolomTotal(ThemeData theme) {
    return SizedBox(
      width: _lebarKartuKiri,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 16, child: _kartuMinggu(theme)),
          const SizedBox(height: 6),
          Expanded(flex: 9, child: _kartuHari(theme)),
        ],
      ),
    );
  }

  Widget _kolomRute() {
    final pasang = _pasanganRute();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Per rute',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: _teks),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _isi.rute.isEmpty && !_muat
              ? Text(
                  'Belum ada akun sales di users.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: _teks),
                )
              : Column(
                  children: [
                    for (var i = 0; i < pasang.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _slotRute(pasang[i].$1)),
                            const SizedBox(width: 8),
                            Expanded(child: _slotRute(pasang[i].$2)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _slotRute(KartuDash? k) {
    if (k == null) return const SizedBox.expand();
    return _kartuRute(k);
  }

  Widget _kartuMinggu(ThemeData theme) {
    final t = _isi.total;
    final m = t.minggu;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 6, 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total · $_judulMinggu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _teks,
                    ),
                  ),
                ),
                IconButton(
                  style: _ikonKalender,
                  tooltip: 'Pilih minggu',
                  onPressed: _muat ? null : _pilihMinggu,
                  icon: const Icon(
                    Icons.date_range_outlined,
                    color: Tema.biru,
                    size: 20,
                  ),
                ),
              ],
            ),
            const Divider(height: 4),
            Expanded(
              child: _isiTarget(
                _barisTarget(
                  label: 'Rasio laba',
                  warna: Colors.green,
                  targetText: '${t.targetPersen.toStringAsFixed(2)}%',
                  orderText: _teksRasio(m.omsetOrder, m.labaOrder),
                  kirimanText: _teksRasio(m.omsetKiriman, m.labaKiriman),
                  actualText: _teksRasio(m.omsetActual, m.labaActual),
                  persentaseOrder: _pct(
                    _persenLaba(m.omsetOrder, m.labaOrder),
                    t.targetPersen,
                  ),
                  persentaseActual: _pct(
                    _persenLaba(m.omsetActual, m.labaActual),
                    t.targetPersen,
                  ),
                ),
              ),
            ),
            const Divider(height: 4),
            Expanded(
              child: _isiTarget(
                _barisTarget(
                  label: 'Total omset',
                  warna: theme.colorScheme.primary,
                  targetText: Uang.rp(t.targetOmset),
                  orderText: Uang.rp(m.omsetOrder),
                  kirimanText: Uang.rp(m.omsetKiriman),
                  actualText: Uang.rp(m.omsetActual),
                  persentaseOrder: _pct(m.omsetOrder, t.targetOmset),
                  persentaseActual: _pct(m.omsetActual, t.targetOmset),
                ),
              ),
            ),
            const Divider(height: 4),
            Expanded(
              child: _isiTarget(
                _barisTarget(
                  label: 'Effective call',
                  warna: Colors.orangeAccent,
                  targetText: '${m.targetEc} toko',
                  orderText: '${m.ecOrder} toko',
                  kirimanText: '${m.ecKiriman} toko',
                  actualText: '${m.ecActual} toko',
                  persentaseOrder: _pct(m.ecOrder, m.targetEc),
                  persentaseActual: _pct(m.ecActual, m.targetEc),
                ),
              ),
            ),
            const Divider(height: 4),
            Expanded(
              child: _isiTarget(
                _barisTarget(
                  label: 'Kunjungan visit',
                  warna: Colors.red,
                  targetText: '${m.targetVisit} toko',
                  orderText: m.xcOrder > 0 || m.xcBatal > 0
                      ? 'XC ${m.xcOrder}${m.xcBatal > 0 ? ' · batal ${m.xcBatal}' : ''}'
                      : null,
                  actualText: '${m.visit} toko',
                  persentaseActual: _pct(m.visit, m.targetVisit),
                  tampilkanOrder: m.xcOrder > 0 || m.xcBatal > 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kartuHari(ThemeData theme) {
    final t = _isi.total;
    final h = t.hari;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 6, 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total · $_judulHari',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _teks,
                    ),
                  ),
                ),
                IconButton(
                  style: _ikonKalender,
                  tooltip: 'Pilih tanggal',
                  onPressed: _muat ? null : _pilihHari,
                  icon: const Icon(
                    Icons.calendar_today_outlined,
                    color: Tema.biru,
                    size: 20,
                  ),
                ),
              ],
            ),
            const Divider(height: 4),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _kotakHari(
                      label: 'Rasio laba',
                      warna: Colors.green,
                      orderText: _teksRasio(h.omsetOrder, h.labaOrder),
                      kirimanText: _teksRasio(h.omsetKiriman, h.labaKiriman),
                      actualText: _teksRasio(h.omsetActual, h.labaActual),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _kotakHari(
                      label: 'Omset',
                      warna: theme.colorScheme.primary,
                      orderText: Uang.rp(h.omsetOrder),
                      kirimanText: Uang.rp(h.omsetKiriman),
                      actualText: Uang.rp(h.omsetActual),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _kotakHari(
                      label: 'Effective call',
                      warna: Colors.orangeAccent,
                      targetText: '${h.targetEc} toko',
                      orderText: '${h.ecOrder} toko',
                      kirimanText: '${h.ecKiriman} toko',
                      actualText: '${h.ecActual} toko',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _kotakHari(
                      label: 'Visit · Extra call',
                      warna: Colors.red,
                      targetText: '${h.targetVisit} toko',
                      orderText: h.xcBatal > 0
                          ? 'XC ${h.xcOrder} · batal ${h.xcBatal}'
                          : 'XC ${h.xcOrder} toko',
                      actualText: '${h.visit} toko',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kartuRute(KartuDash k) {
    final m = k.minggu;
    final h = k.hari;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k.judul,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: _teks,
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _sisiRute(
                      judul: 'Minggu',
                      aksi: Text(
                        k.targetOmset > 0
                            ? 'Target ${Uang.rp(k.targetOmset)}'
                            : 'Target —',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: _teksIsi,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      anak: [
                        _kepalaTiga(),
                        _barisKecil(
                          'Omset',
                          Uang.rp(m.omsetOrder),
                          Uang.rp(m.omsetKiriman),
                          Uang.rp(m.omsetActual),
                        ),
                        _barisKecil(
                          'Rasio',
                          _teksRasio(m.omsetOrder, m.labaOrder),
                          _teksRasio(m.omsetKiriman, m.labaKiriman),
                          _teksRasio(m.omsetActual, m.labaActual),
                        ),
                        _barisKecil(
                          'EC',
                          '${m.ecOrder}',
                          '${m.ecKiriman}',
                          '${m.ecActual}',
                        ),
                        _barisKecil(
                          'XC',
                          '${m.xcOrder}',
                          '${m.xcKiriman}',
                          '${m.xcActual}',
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            m.xcBatal > 0
                                ? 'Visit ${m.visit} / ${m.targetVisit} · XC batal ${m.xcBatal}'
                                : 'Visit ${m.visit} / ${m.targetVisit}',
                            style: const TextStyle(
                              fontSize: _teksIsi,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(
                    width: 10,
                    thickness: 1,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: _sisiRute(
                      judul: _hariIni ? 'Hari ini' : Uang.tanggal(_hari),
                      aksi: IconButton(
                        style: _ikonKalender,
                        tooltip: 'Toko hari ini',
                        onPressed: _muat || _tokoBuka
                            ? null
                            : () => _bukaTokoHari(k),
                        icon: const Icon(
                          Icons.storefront_outlined,
                          color: Tema.biru,
                          size: 18,
                        ),
                      ),
                      anak: [
                        _kepalaTiga(),
                        _barisKecil(
                          'Omset',
                          Uang.rp(h.omsetOrder),
                          Uang.rp(h.omsetKiriman),
                          Uang.rp(h.omsetActual),
                        ),
                        _barisKecil(
                          'Rasio',
                          _teksRasio(h.omsetOrder, h.labaOrder),
                          _teksRasio(h.omsetKiriman, h.labaKiriman),
                          _teksRasio(h.omsetActual, h.labaActual),
                        ),
                        _barisKecil(
                          'EC',
                          '${h.ecOrder}',
                          '${h.ecKiriman}',
                          '${h.ecActual}',
                        ),
                        _barisKecil(
                          'XC',
                          '${h.xcOrder}',
                          '${h.xcKiriman}',
                          '${h.xcActual}',
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            h.xcBatal > 0
                                ? 'Visit ${h.visit} / ${h.targetVisit} · XC batal ${h.xcBatal}'
                                : 'Visit ${h.visit} / ${h.targetVisit}',
                            style: const TextStyle(
                              fontSize: _teksIsi,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sisiRute({
    required String judul,
    required List<Widget> anak,
    Widget? aksi,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final lebar = !c.maxWidth.isFinite || c.maxWidth <= 0
            ? 240.0
            : c.maxWidth;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: lebar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        judul,
                        style: TextStyle(
                          fontSize: _teksIsi,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    ?aksi,
                  ],
                ),
                ...anak,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kepalaTiga() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              'Order',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              'Kiriman',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              'Actual',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _isiTarget(Widget anak) {
    return LayoutBuilder(
      builder: (context, c) {
        final lebar = !c.maxWidth.isFinite || c.maxWidth <= 0
            ? _lebarIsiTotal
            : c.maxWidth;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(width: lebar, child: anak),
        );
      },
    );
  }

  Widget _nilaiRute(
    String teks, {
    TextAlign align = TextAlign.left,
    FontWeight berat = FontWeight.w600,
  }) {
    final arah = align == TextAlign.right
        ? Alignment.centerRight
        : align == TextAlign.center
        ? Alignment.center
        : Alignment.centerLeft;
    return Expanded(
      child: Align(
        alignment: arah,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: arah,
          child: Text(
            teks,
            maxLines: 1,
            textAlign: align,
            style: TextStyle(fontSize: _teksIsi, fontWeight: berat),
          ),
        ),
      ),
    );
  }

  Widget _barisKecil(String label, String order, String kiriman, String actual) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(fontSize: _teksIsi, color: Colors.grey.shade700),
            ),
          ),
          _nilaiRute(order),
          _nilaiRute(kiriman, align: TextAlign.center),
          _nilaiRute(actual, align: TextAlign.right, berat: FontWeight.w700),
        ],
      ),
    );
  }

  Widget _barisTarget({
    required String label,
    required Color warna,
    required String targetText,
    required String actualText,
    required double persentaseActual,
    String? orderText,
    String? kirimanText,
    double persentaseOrder = 0,
    bool tampilkanOrder = true,
    bool tampilCincin = true,
  }) {
    final gayaTarget = TextStyle(
      fontSize: _teksIsi,
      color: Colors.grey.shade600,
      fontWeight: FontWeight.w500,
    );
    const gayaIsi = TextStyle(
      fontSize: _teksIsi,
      color: Colors.black87,
      fontWeight: FontWeight.bold,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: warna,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: _teks,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _barisUang('Target', targetText, gayaTarget),
              if (tampilkanOrder) _barisUang('Order', orderText ?? '', gayaIsi),
              if (kirimanText != null) _barisUang('Kiriman', kirimanText, gayaIsi),
              _barisUang('Actual', actualText, gayaIsi),
            ],
          ),
        ),
        if (tampilCincin) ...[
          if (tampilkanOrder) ...[
            _cincin(label: 'Order', persentase: persentaseOrder, warna: warna),
            const SizedBox(width: 8),
          ],
          _cincin(label: 'Actual', persentase: persentaseActual, warna: warna),
        ],
      ],
    );
  }

  Widget _barisUang(String judul, String nilai, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 1),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(judul, style: style)),
          Expanded(
            child: Text(
              nilai,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cincin({
    required String label,
    required double persentase,
    required Color warna,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(42, 42),
                painter: _CincinPainter(percentage: persentase, color: warna),
              ),
              Text(
                '${(persentase * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: persentase >= 1 ? 8 : 9,
                  fontWeight: FontWeight.bold,
                  color: warna,
                ),
              ),
            ],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _kotakHari({
    required String label,
    required Color warna,
    required String actualText,
    String? orderText,
    String? kirimanText,
    String? targetText,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: Tema.sudut,
        border: Border.all(color: Tema.seed),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: warna,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: _teksIsi,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            if (targetText != null) ...[
              const SizedBox(height: 4),
              Text(
                'Target : $targetText',
                style: TextStyle(fontSize: _teksIsi, color: Colors.grey.shade600),
              ),
            ],
            if (orderText != null)
              Text(
                'Order : $orderText',
                style: const TextStyle(
                  fontSize: _teksIsi,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (kirimanText != null)
              Text(
                'Kiriman : $kirimanText',
                style: const TextStyle(
                  fontSize: _teksIsi,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              orderText == null && kirimanText == null && targetText == null
                  ? actualText
                  : 'Actual : $actualText',
              style: const TextStyle(
                fontSize: _teksIsi,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CincinPainter extends CustomPainter {
  _CincinPainter({required this.percentage, required this.color});

  final double percentage;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const strokeWidth = 5.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = color.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);
    if (percentage > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        rect,
        -3.141592653589793 / 2,
        percentage.clamp(0.0, 1.0) * 2 * 3.141592653589793,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CincinPainter oldDelegate) {
    return oldDelegate.percentage != percentage || oldDelegate.color != color;
  }
}
