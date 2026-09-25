import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pelanggan/pelanggan.dart';
import '../pelanggan/pelanggan_repo.dart';
import '../pesan.dart';
import '../transaksi/riwayat_layar.dart';
import '../transaksi/transaksi_repo.dart';
import '../uang.dart';

class DashboardLayar extends StatefulWidget {
  const DashboardLayar({super.key, required this.rute});

  final String rute;

  @override
  State<DashboardLayar> createState() => _DashboardLayarState();
}

class _DashboardLayarState extends State<DashboardLayar> {
  final _nota = TransaksiRepo(Supabase.instance.client);
  final _toko = PelangganRepo(Supabase.instance.client);

  bool _muat = false;
  late DateTime _hariKartu;
  late DateTime _seninKartu;
  List<Pelanggan> _tokoRute = [];

  int _omsetMingguOrder = 0;
  int _labaMingguOrder = 0;
  int _omsetMingguPacked = 0;
  int _labaMingguPacked = 0;
  int _omsetMingguActual = 0;
  int _labaMingguActual = 0;
  int _omsetHariOrder = 0;
  int _labaHariOrder = 0;
  int _omsetHariPacked = 0;
  int _labaHariPacked = 0;
  int _omsetHariActual = 0;
  int _labaHariActual = 0;
  int _ecMingguOrder = 0;
  int _ecMingguPacked = 0;
  int _ecMingguActual = 0;
  int _xcMingguOrder = 0;
  int _xcMingguPacked = 0;
  int _xcMingguBatal = 0;
  int _xcHariOrder = 0;
  int _xcHariPacked = 0;
  int _xcHariBatal = 0;
  int _ecHariOrder = 0;
  int _ecHariPacked = 0;
  int _ecHariActual = 0;
  int _visitMinggu = 0;
  int _visitHari = 0;

  int _targetOmset = 0;
  double _targetPersenLaba = 0;
  int _targetEc = 1;
  int _targetVisit = 1;
  int _targetEcHari = 1;
  int _targetVisitHari = 1;

  double _pctOmset = 0;
  double _pctLaba = 0;
  double _pctEc = 0;
  double _pctOmsetPacked = 0;
  double _pctLabaPacked = 0;
  double _pctEcPacked = 0;
  double _pctOmsetActual = 0;
  double _pctLabaActual = 0;
  double _pctEcActual = 0;
  double _pctVisitActual = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _hariKartu = MingguKunjungan.hari(now);
    _seninKartu = MingguKunjungan.seninDari(now);
    _muatSemua();
  }

  String get _rute => widget.rute.trim();

  bool get _hariIni => MingguKunjungan.samaHari(_hariKartu, DateTime.now());

  bool get _mingguIni =>
      MingguKunjungan.samaHari(_seninKartu, MingguKunjungan.senin());

  String get _judulMinggu {
    if (_mingguIni) return 'Pencapaian Minggu Ini';
    final minggu = _seninKartu.add(const Duration(days: 6));
    return 'Pencapaian ${MingguKunjungan.tampilPendek(_seninKartu)} - ${MingguKunjungan.tampil(minggu)}';
  }

  String get _judulHari {
    if (_hariIni) return 'Pencapaian Hari Ini';
    return 'Pencapaian ${MingguKunjungan.tampil(_hariKartu)}';
  }

  Future<void> _muatSemua() async {
    setState(() => _muat = true);

    var targetGagal = false;
    var target = TargetSales.kosong;
    try {
      target = await _nota.targetSaya();
    } catch (_) {
      targetGagal = true;
    }

    List<Pelanggan> tokoRute = [];
    try {
      tokoRute = await _toko.tokoRute(_rute);
      tokoRute = [
        for (final t in tokoRute)
          if (!t.id.startsWith('TMP')) t,
      ];
    } catch (_) {
      tokoRute = [];
    }

    final totalToko = tokoRute.isEmpty ? 1 : tokoRute.length;
    var targetEc = totalToko;
    var targetVisit = totalToko;
    if (targetEc < 1) targetEc = 1;
    if (targetVisit < 1) targetVisit = 1;
    final targetHari = _targetHari(_hariKartu, tokoRute);

    final visitMap = {
      for (final t in tokoRute) t.id: (t.visit ?? '').trim(),
    };
    final hariKartu = await _dataKartu(
      dari: _hariKartu,
      sampai: _hariKartu,
      visitMap: visitMap,
    );
    final mingguKartu = await _dataKartu(
      dari: _seninKartu,
      sampai: _seninKartu.add(const Duration(days: 6)),
      visitMap: visitMap,
    );
    if (!mounted) return;

    setState(() {
      _tokoRute = tokoRute;
      _targetOmset = target.omset;
      _targetPersenLaba = target.persenLaba;
      _targetEc = targetEc;
      _targetVisit = targetVisit;
      _targetEcHari = targetHari.ec;
      _targetVisitHari = targetHari.visit;
      _pasangMinggu(mingguKartu);
      _pasangHari(hariKartu);
      _muat = false;
    });

    if (targetGagal && _targetOmset == 0) {
      tampilPesan(
        context,
        'Target omset dan rasio laba belum bisa dibaca. Jalankan supabase/009_target_sales.sql, lalu isi public.target_sales. Atau periksa internet.',
      );
    }
  }

  ({int ec, int visit}) _targetHari(DateTime tanggal, List<Pelanggan> toko) {
    final nama = MingguKunjungan.namaHari(tanggal);
    var jumlah = 0;
    for (final t in toko) {
      if ((t.visit ?? '').trim() == nama) jumlah++;
    }
    if (jumlah < 1) jumlah = 1;
    return (ec: jumlah, visit: jumlah);
  }

  void _pasangMinggu(_Capaian data) {
    final persenOrder = _persenLaba(data.omsetOrder, data.labaOrder);
    final persenPacked = _persenLaba(data.omsetPacked, data.labaPacked);
    final persenActual = _persenLaba(data.omsetActual, data.labaActual);
    _omsetMingguOrder = data.omsetOrder;
    _labaMingguOrder = data.labaOrder;
    _omsetMingguPacked = data.omsetPacked;
    _labaMingguPacked = data.labaPacked;
    _omsetMingguActual = data.omsetActual;
    _labaMingguActual = data.labaActual;
    _ecMingguOrder = data.ecOrder;
    _ecMingguPacked = data.ecPacked;
    _ecMingguActual = data.ecActual;
    _visitMinggu = data.visit;
    _xcMingguOrder = data.xcOrder;
    _xcMingguPacked = data.xcPacked;
    _xcMingguBatal = data.xcBatal;
    _pctOmset = _targetOmset > 0 ? data.omsetOrder / _targetOmset : 0;
    _pctLaba = _targetPersenLaba > 0 ? persenOrder / _targetPersenLaba : 0;
    _pctEc = data.ecOrder / _targetEc;
    _pctOmsetPacked = _targetOmset > 0 ? data.omsetPacked / _targetOmset : 0;
    _pctLabaPacked =
        _targetPersenLaba > 0 ? persenPacked / _targetPersenLaba : 0;
    _pctEcPacked = data.ecPacked / _targetEc;
    _pctOmsetActual = _targetOmset > 0 ? data.omsetActual / _targetOmset : 0;
    _pctLabaActual =
        _targetPersenLaba > 0 ? persenActual / _targetPersenLaba : 0;
    _pctEcActual = data.ecActual / _targetEc;
    _pctVisitActual = data.visit / _targetVisit;
  }

  void _pasangHari(_Capaian data) {
    _omsetHariOrder = data.omsetOrder;
    _labaHariOrder = data.labaOrder;
    _omsetHariPacked = data.omsetPacked;
    _labaHariPacked = data.labaPacked;
    _omsetHariActual = data.omsetActual;
    _labaHariActual = data.labaActual;
    _ecHariOrder = data.ecOrder;
    _ecHariPacked = data.ecPacked;
    _ecHariActual = data.ecActual;
    _visitHari = data.visit;
    _xcHariOrder = data.xcOrder;
    _xcHariPacked = data.xcPacked;
    _xcHariBatal = data.xcBatal;
  }

  double _persenLaba(int omset, int laba) {
    final modal = omset - laba;
    if (omset <= 0 || modal <= 0) return 0;
    return (laba / modal) * 100;
  }

  String _teksRasio(int omset, int laba) {
    final modal = omset - laba;
    if (omset <= 0 || modal <= 0) return '0.00%';
    return '${((laba / modal) * 100).toStringAsFixed(2)}%';
  }

  Map<String, String> get _visitMap => {
        for (final t in _tokoRute) t.id: (t.visit ?? '').trim(),
      };

  bool _jadwalToko(String idPelanggan, DateTime? waktu, Map<String, String> visitMap) {
    if (idPelanggan.isEmpty || waktu == null) return false;
    final lokal = waktu.toLocal();
    return visitMap[idPelanggan] ==
        MingguKunjungan.namaHari(DateTime(lokal.year, lokal.month, lokal.day));
  }

  Future<_Capaian> _dataKartu({
    required DateTime dari,
    required DateTime sampai,
    Map<String, String>? visitMap,
  }) async {
    final jadwal = visitMap ?? _visitMap;
    var omsetOrder = 0;
    var labaOrder = 0;
    var omsetPacked = 0;
    var labaPacked = 0;
    var omsetActual = 0;
    var labaActual = 0;
    final ecOrder = <String>{};
    final ecPacked = <String>{};
    final ecActual = <String>{};
    final xcOrder = <String>{};
    final xcPacked = <String>{};
    final xcActual = <String>{};
    final xcBatal = <String>{};
    var visit = 0;
    try {
      final nota = await _nota.untukRentang(
        dari: DateTime(dari.year, dari.month, dari.day),
        sampai: DateTime(sampai.year, sampai.month, sampai.day, 23, 59, 59, 999),
        ringkas: true,
      );
      for (final n in nota) {
        final diJadwal = _jadwalToko(n.idPelanggan, n.waktuOrder, jadwal);
        if (n.status == 'batal' && n.idPelanggan.isNotEmpty && !diJadwal) {
          xcBatal.add(n.idPelanggan);
        }
        if (!n.batalSales) {
          omsetOrder += n.totalOrder;
          labaOrder += n.totalOrder - n.modalOrder;
          if (n.idPelanggan.isNotEmpty) {
            if (diJadwal) {
              ecOrder.add(n.idPelanggan);
            } else {
              xcOrder.add(n.idPelanggan);
            }
          }
        }
        if (!n.batalGudang && n.punyaPacked) {
          omsetPacked += n.totalPacked;
          labaPacked += n.totalPacked - n.modalPacked;
          if (n.idPelanggan.isNotEmpty) {
            if (diJadwal) {
              ecPacked.add(n.idPelanggan);
            } else {
              xcPacked.add(n.idPelanggan);
            }
          }
        }
        if (!n.batalPengirim) {
          omsetActual += n.totalActual;
          labaActual += n.totalActual - n.modalActual;
          if (n.idPelanggan.isNotEmpty && n.status == 'terkirim') {
            if (diJadwal) {
              ecActual.add(n.idPelanggan);
            } else {
              xcActual.add(n.idPelanggan);
            }
          }
        }
      }
    } catch (_) {
      if (mounted) {
        tampilPesan(
          context,
          'Ringkasan nota belum bisa dimuat. Periksa internet lalu ketuk ikon segarkan.',
        );
      }
    }
    try {
      visit = (await _toko.idKunjunganJadwal(
        rute: _rute,
        dari: dari,
        sampai: sampai,
        visitToko: jadwal,
      ))
          .length;
    } catch (_) {}
    return _Capaian(
      omsetOrder: omsetOrder,
      labaOrder: labaOrder,
      ecOrder: ecOrder.length,
      xcOrder: xcOrder.length,
      omsetPacked: omsetPacked,
      labaPacked: labaPacked,
      ecPacked: ecPacked.length,
      xcPacked: xcPacked.length,
      omsetActual: omsetActual,
      labaActual: labaActual,
      ecActual: ecActual.length,
      xcActual: xcActual.length,
      xcBatal: xcBatal.length,
      visit: visit,
    );
  }

  Future<void> _pilihMinggu() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _seninKartu,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal di minggu yang ingin ditampilkan',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    setState(() => _seninKartu = MingguKunjungan.seninDari(picked));
    await _muatMinggu(_seninKartu);
  }

  Future<void> _muatMinggu(DateTime senin) async {
    try {
      final data = await _dataKartu(
        dari: senin,
        sampai: senin.add(const Duration(days: 6)),
      );
      if (!mounted) return;
      setState(() => _pasangMinggu(data));
    } catch (e) {
      if (!mounted) return;
      if (Jaringan.mati(e)) {
        tampilPesan(
          context,
          'Tidak ada internet. Analisis minggu itu belum bisa dimuat. Coba lagi nanti.',
        );
      }
    }
  }

  Future<void> _pilihHari() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hariKartu,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal pencapaian',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    final hari = MingguKunjungan.hari(picked);
    setState(() => _hariKartu = hari);
    await _muatHari(hari);
  }

  Future<void> _muatHari(DateTime hari) async {
    try {
      final data = await _dataKartu(dari: hari, sampai: hari);
      if (!mounted) return;
      final targetHari = _targetHari(hari, _tokoRute);
      setState(() {
        _pasangHari(data);
        _targetEcHari = targetHari.ec;
        _targetVisitHari = targetHari.visit;
      });
    } catch (e) {
      if (!mounted) return;
      if (Jaringan.mati(e)) {
        tampilPesan(
          context,
          'Tidak ada internet. Pencapaian tanggal itu belum bisa dimuat. Coba lagi nanti.',
        );
      }
    }
  }

  Widget _barisUang(String judul, Widget nilai, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: SizedBox(
        width: 248,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(judul, style: style),
            ),
            Expanded(child: nilai),
          ],
        ),
      ),
    );
  }

  Widget _teksNilai(String nilai, TextStyle style) {
    return Text(
      nilai,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
      style: style.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
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
    String? packedText,
    double persentaseOrder = 0,
    double persentasePacked = 0,
    bool tampilkanTahap = true,
  }) {
    final gayaTarget = TextStyle(
      fontSize: 10,
      color: Colors.grey.shade600,
      fontWeight: FontWeight.w500,
    );
    const gayaIsi = TextStyle(
      fontSize: 10,
      color: Colors.black87,
      fontWeight: FontWeight.bold,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 262,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: warna,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  _barisUang(
                    'Target',
                    _teksNilai(targetText, gayaTarget),
                    gayaTarget,
                  ),
                  if (tampilkanTahap) ...[
                    const SizedBox(height: 1),
                    _barisUang(
                      'Order',
                      _teksNilai(orderText ?? '', gayaIsi),
                      gayaIsi,
                    ),
                    const SizedBox(height: 1),
                    _barisUang(
                      'Kiriman',
                      _teksNilai(packedText ?? '', gayaIsi),
                      gayaIsi,
                    ),
                  ],
                  const SizedBox(height: 1),
                  _barisUang(
                    'Actual',
                    _teksNilai(actualText, gayaIsi),
                    gayaIsi,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tampilkanTahap) ...[
                _cincin(
                  label: 'Order',
                  persentase: persentaseOrder,
                  warna: warna,
                ),
                const SizedBox(width: 4),
                _cincin(
                  label: 'Kiriman',
                  persentase: persentasePacked,
                  warna: warna,
                ),
                const SizedBox(width: 4),
              ],
              _cincin(
                label: 'Actual',
                persentase: persentaseActual,
                warna: warna,
              ),
            ],
          ),
        ),
      ],
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
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(32, 32),
                painter: _CincinPainter(percentage: persentase, color: warna),
              ),
              Text(
                '${(persentase * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: persentase >= 1 ? 6 : 7,
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
            fontSize: 7,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _ikonKartu({
    required String tooltip,
    required IconData ikon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(ikon, color: Tema.seed, size: 22),
    );
  }

  Widget _kotakHari({
    required String label,
    required Color warna,
    required String actualText,
    String? orderText,
    String? packedText,
    String? targetText,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            if (targetText != null) ...[
              const SizedBox(height: 2),
              Text(
                'Target   : $targetText',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (orderText != null) ...[
              const SizedBox(height: 1),
              Text(
                'Order    : $orderText',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
            if (packedText != null) ...[
              const SizedBox(height: 1),
              Text(
                'Kiriman : $packedText',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
            const SizedBox(height: 1),
            Text(
              orderText == null && targetText == null
                  ? actualText
                  : 'Actual   : $actualText',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Ringkasan penjualan'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _muat
              ? LinearProgressIndicator(
                  backgroundColor: theme.colorScheme.primary.withAlpha(30),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                )
              : const SizedBox(height: 4),
        ),
      ),
      body: _muat
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: 4,
              itemBuilder: (context, index) => const Card(
                margin: EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    height: 64,
                    child: ColoredBox(color: Colors.black12),
                  ),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _muatSemua,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: Column(
                          children: [
                            Expanded(
                              flex: 13,
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 2, 6, 4),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _judulMinggu,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _ikonKartu(
                                            tooltip: 'Pilih minggu',
                                            ikon: Icons.date_range_outlined,
                                            onPressed: _muat ? null : _pilihMinggu,
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 4),
                                      Expanded(
                                        child: _barisTarget(
                                          label: 'Rasio Laba',
                                          warna: Colors.green,
                                          targetText:
                                              '${_targetPersenLaba.toStringAsFixed(2)}%',
                                          orderText: _teksRasio(
                                            _omsetMingguOrder,
                                            _labaMingguOrder,
                                          ),
                                          packedText: _teksRasio(
                                            _omsetMingguPacked,
                                            _labaMingguPacked,
                                          ),
                                          actualText: _teksRasio(
                                            _omsetMingguActual,
                                            _labaMingguActual,
                                          ),
                                          persentaseOrder: _pctLaba,
                                          persentasePacked: _pctLabaPacked,
                                          persentaseActual: _pctLabaActual,
                                        ),
                                      ),
                                      const Divider(height: 2),
                                      Expanded(
                                        child: _barisTarget(
                                          label: 'Total Omset',
                                          warna: theme.colorScheme.primary,
                                          targetText: Uang.rp(_targetOmset),
                                          orderText: Uang.rp(_omsetMingguOrder),
                                          packedText: Uang.rp(_omsetMingguPacked),
                                          actualText: Uang.rp(_omsetMingguActual),
                                          persentaseOrder: _pctOmset,
                                          persentasePacked: _pctOmsetPacked,
                                          persentaseActual: _pctOmsetActual,
                                        ),
                                      ),
                                      const Divider(height: 2),
                                      Expanded(
                                        child: _barisTarget(
                                          label: 'Effective Call',
                                          warna: Colors.orangeAccent,
                                          targetText: '$_targetEc toko',
                                          orderText: '$_ecMingguOrder toko',
                                          packedText: '$_ecMingguPacked toko',
                                          actualText: '$_ecMingguActual toko',
                                          persentaseOrder: _pctEc,
                                          persentasePacked: _pctEcPacked,
                                          persentaseActual: _pctEcActual,
                                        ),
                                      ),
                                      const Divider(height: 2),
                                      Expanded(
                                        child: _barisTarget(
                                          label: 'Kunjungan visit',
                                          warna: Colors.red,
                                          targetText: '$_targetVisit toko',
                                          actualText: '$_visitMinggu toko',
                                          persentaseActual: _pctVisitActual,
                                          tampilkanTahap: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              flex: 9,
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 2, 6, 4),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _judulHari,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _ikonKartu(
                                            tooltip: 'Pilih tanggal',
                                            ikon: Icons.calendar_today_outlined,
                                            onPressed: _muat ? null : _pilihHari,
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 8),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _kotakHari(
                                                      label: 'Rasio Laba',
                                                      warna: Colors.green,
                                                      orderText: _teksRasio(
                                                        _omsetHariOrder,
                                                        _labaHariOrder,
                                                      ),
                                                      packedText: _teksRasio(
                                                        _omsetHariPacked,
                                                        _labaHariPacked,
                                                      ),
                                                      actualText: _teksRasio(
                                                        _omsetHariActual,
                                                        _labaHariActual,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: _kotakHari(
                                                      label: 'Omset',
                                                      warna: theme.colorScheme.primary,
                                                      orderText: Uang.rp(_omsetHariOrder),
                                                      packedText:
                                                          Uang.rp(_omsetHariPacked),
                                                      actualText:
                                                          Uang.rp(_omsetHariActual),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _kotakHari(
                                                      label: 'Effective Call',
                                                      warna: Colors.orangeAccent,
                                                      targetText: '$_targetEcHari toko',
                                                      orderText: '$_ecHariOrder toko',
                                                      packedText: '$_ecHariPacked toko',
                                                      actualText: '$_ecHariActual toko',
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: _kotakHari(
                                                      label: 'Kunjungan visit',
                                                      warna: Colors.red,
                                                      targetText:
                                                          '$_targetVisitHari toko',
                                                      actualText: '$_visitHari toko',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 34,
                                        child: OutlinedButton(
                                          onPressed: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => RiwayatLayar(
                                                  tanggal: _hariKartu,
                                                ),
                                              ),
                                            );
                                            if (mounted) await _muatSemua();
                                          },
                                          child: Text(
                                            _hariIni
                                                ? 'Rincian Transaksi Hari Ini'
                                                : 'Rincian Transaksi Tanggal Ini',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
    );
  }
}

class _Capaian {
  const _Capaian({
    required this.omsetOrder,
    required this.labaOrder,
    required this.ecOrder,
    required this.xcOrder,
    required this.omsetPacked,
    required this.labaPacked,
    required this.ecPacked,
    required this.xcPacked,
    required this.omsetActual,
    required this.labaActual,
    required this.ecActual,
    required this.xcActual,
    required this.xcBatal,
    required this.visit,
  });

  final int omsetOrder;
  final int labaOrder;
  final int ecOrder;
  final int xcOrder;
  final int omsetPacked;
  final int labaPacked;
  final int ecPacked;
  final int xcPacked;
  final int omsetActual;
  final int labaActual;
  final int ecActual;
  final int xcActual;
  final int xcBatal;
  final int visit;
}

class _CincinPainter extends CustomPainter {
  _CincinPainter({required this.percentage, required this.color});

  final double percentage;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const strokeWidth = 4.0;
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
