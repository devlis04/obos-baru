import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
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
  final _repo = GajiPengirimRepo(Supabase.instance.client);
  bool _muat = true;
  String? _gagal;
  late DateTime _hari;
  IsiGajiPengirim? _minggu;

  @override
  void initState() {
    super.initState();
    _hari = MingguGaji.hari(DateTime.now());
    _muatUlang();
  }

  bool get _mingguIni => MingguGaji.samaHari(
        MingguGaji.seninDari(_hari),
        MingguGaji.senin(),
      );

  String get _judulMinggu {
    final m = _minggu;
    if (m == null || _mingguIni) return 'Benefit Minggu Ini';
    return 'Benefit ${MingguGaji.tampilPendek(m.senin)} - ${MingguGaji.tampil(m.sabtu)}';
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
                : 'Benefit belum bisa dimuat. Jalankan SQL 128.';
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
    setState(() => _hari = MingguGaji.hari(picked));
    await _muatUlang();
  }

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
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
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
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 6, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  onPressed: _muat ? null : _pilihTanggal,
                                  visualDensity: VisualDensity.compact,
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
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '${minggu.rute} · ${minggu.nama}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const Divider(height: 4),
                            _barisCapai(
                              label: 'Net',
                              warna: Colors.green,
                              targetText: Uang.rp(minggu.netTarget),
                              actualText: Uang.rp(minggu.netActual),
                              persentase: minggu.pctNet,
                            ),
                            const Divider(height: 2),
                            _barisCapai(
                              label: 'Total omset',
                              warna: theme.colorScheme.primary,
                              targetText: Uang.rp(minggu.omsetTarget),
                              actualText: Uang.rp(minggu.omsetActual),
                              persentase: minggu.pctOmset,
                            ),
                            const Divider(height: 2),
                            _barisCapai(
                              label: 'Hari hadir',
                              warna: Colors.orangeAccent,
                              targetText: '${minggu.hariTarget} hari',
                              actualText: '${minggu.hari} hari',
                              persentase: minggu.pctHari,
                            ),
                            const Divider(height: 2),
                            _barisCapai(
                              label: 'BOP pengirim',
                              warna: Colors.blueGrey,
                              targetText: Uang.rp(minggu.bopTarget),
                              actualText: Uang.rp(minggu.bopActual),
                              persentase: minggu.pctBop,
                            ),
                            const Divider(height: 2),
                            _barisCapai(
                              label: 'Benefit total',
                              warna: Colors.black87,
                              actualText: Uang.rp(minggu.gaji),
                            ),
                            const Divider(height: 2),
                            _barisCapai(
                              label: 'Kasbon',
                              warna: Colors.grey,
                              actualText: Uang.rp(minggu.kasbon),
                            ),
                            const Divider(height: 2),
                            _barisCapai(
                              label: 'Terima',
                              warna: Tema.seed,
                              actualText: Uang.rp(minggu.terima),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Perkiraan benefit Senin–Sabtu. Bisa berubah sampai '
                              'packing, kirim, retur, absen, dan BOP selesai. '
                              'Kasbon hanya dibaca; ubah di admin.',
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
                ],
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

  Widget _barisCapai({
    required String label,
    required Color warna,
    required String actualText,
    String? targetText,
    double? persentase,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
                    if (targetText != null) ...[
                      const SizedBox(height: 1),
                      _barisUang('Target', targetText, gayaTarget),
                    ],
                    const SizedBox(height: 1),
                    _barisUang('Actual', actualText, gayaIsi),
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
      ),
    );
  }

  Widget _cincin({required double persentase, required Color warna}) {
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
          'Actual',
          style: TextStyle(
            fontSize: 7,
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
