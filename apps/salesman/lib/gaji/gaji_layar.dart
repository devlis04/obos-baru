import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pelanggan/pelanggan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'gaji_repo.dart';

class GajiLayar extends StatefulWidget {
  const GajiLayar({super.key, required this.rute});

  final String rute;

  @override
  State<GajiLayar> createState() => _GajiLayarState();
}

class _GajiLayarState extends State<GajiLayar> {
  final _repo = GajiSalesRepo(Supabase.instance.client);
  bool _muat = true;
  String? _gagal;
  late DateTime _hari;
  IsiGajiSales? _minggu;

  @override
  void initState() {
    super.initState();
    _hari = MingguKunjungan.hari(DateTime.now());
    _muatUlang();
  }

  bool get _mingguIni => MingguKunjungan.samaHari(
        MingguKunjungan.seninDari(_hari),
        MingguKunjungan.senin(),
      );

  String get _judulMinggu {
    final m = _minggu;
    if (m == null || _mingguIni) return 'Benefit Minggu Ini';
    return 'Benefit ${MingguKunjungan.tampilPendek(m.senin)} - ${MingguKunjungan.tampil(m.sabtu)}';
  }

  Future<void> _muatUlang() async {
    setState(() {
      _muat = true;
      _gagal = null;
    });
    try {
      final isi = await _repo.lihat(_hari);
      if (!mounted) return;
      setState(() {
        _minggu = isi;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _muat = false;
        _gagal = Jaringan.mati(e)
            ? 'Tidak ada internet. Benefit belum bisa dimuat.'
            : e is PostgrestException && e.message.trim().isNotEmpty
                ? e.message.trim()
                : 'Benefit belum bisa dimuat. Jalankan SQL 134.';
      });
      tampilPesan(context, _gagal!);
    }
  }

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hari,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal. Kartu mengikuti Senin–Sabtu tanggal itu.',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    setState(() => _hari = MingguKunjungan.hari(picked));
    await _muatUlang();
  }

  String _teksRasio(double n) => '${n.toStringAsFixed(2)}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minggu = _minggu;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.rute.isEmpty ? 'Benefit' : 'Benefit · ${widget.rute}'),
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
      body: _muat && minggu == null
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: 1,
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
              onRefresh: _muatUlang,
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
                            if (_gagal != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                child: Text(
                                  _gagal!,
                                  style: const TextStyle(color: Tema.redup),
                                ),
                              ),
                            if (minggu != null)
                              Expanded(
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      2,
                                      6,
                                      8,
                                    ),
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
                                            IconButton(
                                              tooltip: 'Pilih minggu',
                                              onPressed:
                                                  _muat ? null : _pilihTanggal,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              icon: const Icon(
                                                Icons.date_range_outlined,
                                                color: Tema.seed,
                                                size: 22,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (minggu.nama.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '${minggu.rute} · ${minggu.nama}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        const Divider(height: 6),
                                        _slotCapai(
                                          _barisCapai(
                                            label: 'Rasio laba',
                                            warna: Colors.green,
                                            targetText: _teksRasio(
                                              minggu.rasioTarget,
                                            ),
                                            actualText: _teksRasio(
                                              minggu.rasioActual,
                                            ),
                                            persentase: minggu.pctRasio,
                                          ),
                                        ),
                                        const Divider(height: 2),
                                        _slotCapai(
                                          _barisCapai(
                                            label: 'Total omset',
                                            warna: theme.colorScheme.primary,
                                            targetText: Uang.rp(
                                              minggu.omsetTarget,
                                            ),
                                            actualText: Uang.rp(
                                              minggu.omsetActual,
                                            ),
                                            persentase: minggu.pctOmset,
                                            benefitText: Uang.rp(
                                              minggu.benOmset,
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 2),
                                        _slotCapai(
                                          _barisCapai(
                                            label: 'Effective call',
                                            warna: Colors.orangeAccent,
                                            targetText:
                                                '${minggu.ecTarget} toko',
                                            actualText: '${minggu.ec} toko',
                                            persentase: minggu.pctEc,
                                            benefitText: Uang.rp(
                                              minggu.benEc,
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 2),
                                        _slotCapai(
                                          _barisCapai(
                                            label: 'Kunjungan visit',
                                            warna: Colors.red,
                                            targetText:
                                                '${minggu.visitTarget} toko',
                                            actualText:
                                                '${minggu.visit} toko',
                                            persentase: minggu.pctVisit,
                                            benefitText: Uang.rp(
                                              minggu.benVisit,
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 2),
                                        _slotCapai(
                                          _barisCapai(
                                            label: 'BOP pengirim',
                                            warna: Colors.blueGrey,
                                            actualText: Uang.rp(
                                              minggu.bopPengirim,
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 2),
                                        _slotCapai(
                                          _barisCapai(
                                            label: 'Benefit total',
                                            warna: Colors.black87,
                                            actualText: Uang.rp(minggu.total),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Perkiraan benefit Senin–Sabtu. Bisa berubah sampai '
                                          'packing, kirim, retur, dan BOP rute selesai.',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 11,
                                            height: 1.35,
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

  Widget _barisUang(String judul, String nilai, TextStyle style) {
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
            Expanded(
              child: Text(
                nilai,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: style.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotCapai(Widget anak) {
    return Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: anak,
      ),
    );
  }

  Widget _barisCapai({
    required String label,
    required Color warna,
    required String actualText,
    String? targetText,
    double? persentase,
    String? benefitText,
  }) {
    final gayaTarget = TextStyle(
      fontSize: 13,
      color: Colors.grey.shade600,
      fontWeight: FontWeight.w500,
    );
    const gayaIsi = TextStyle(
      fontSize: 13,
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
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  if (targetText != null) ...[
                    const SizedBox(height: 1),
                    _barisUang('Target', targetText, gayaTarget),
                  ],
                  const SizedBox(height: 1),
                  _barisUang('Actual', actualText, gayaIsi),
                  if (benefitText != null) ...[
                    const SizedBox(height: 1),
                    _barisUang('Benefit', benefitText, gayaIsi),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (persentase != null) ...[
          const SizedBox(width: 4),
          _cincin(persentase: persentase, warna: warna),
        ],
      ],
    );
  }

  Widget _cincin({required double persentase, required Color warna}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(40, 40),
                painter: _CincinPainter(percentage: persentase, color: warna),
              ),
              Text(
                '${(persentase * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: persentase >= 1 ? 9 : 10,
                  fontWeight: FontWeight.bold,
                  color: warna,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Actual',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
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
