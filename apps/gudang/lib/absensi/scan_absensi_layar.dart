import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pesan.dart';
import 'absensi_repo.dart';

class ScanAbsensiLayar extends StatefulWidget {
  const ScanAbsensiLayar({super.key, required this.keluar});

  final bool keluar;

  @override
  State<ScanAbsensiLayar> createState() => _ScanAbsensiLayarState();
}

class _ScanAbsensiLayarState extends State<ScanAbsensiLayar> {
  static const _kodeGudang = 'OBOS-GUDANG';
  static const _batasMeter = 20.0;
  static const _toleransiJam = Duration(minutes: 3);

  final _kamera = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final _repo = AbsensiRepo(Supabase.instance.client);

  StreamSubscription<Position>? _gps;
  bool _netSiap = false;
  bool _busy = false;
  bool _peringatPalsu = false;
  Position? _pos;
  String? _kodeTahan;
  LokasiGudang? _lokasi;
  String _status = 'Menyambung internet…';

  static const _pesanLokasiPalsu =
      'Lokasi HP terdeteksi tidak wajar. Matikan aplikasi lokasi palsu, lalu scan lagi.';

  @override
  void initState() {
    super.initState();
    unawaited(_siapkan());
  }

  @override
  void dispose() {
    unawaited(_gps?.cancel());
    _kamera.dispose();
    super.dispose();
  }

  Future<void> _siapkan() async {
    try {
      await _repo.waktuServer();
      final lokasi = await _repo.lokasiUtama();
      if (!mounted) return;
      _lokasi = lokasi;
    } catch (_) {
      if (!mounted) return;
      _tutup('Tidak ada internet. Sambungkan internet, lalu scan lagi.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _netSiap = true;
      _status = 'Mencari lokasi…';
    });
    await _hidupkanKamera();
    await _hidupkanGps();
  }

  void _tutup(String pesan) {
    final messenger = ScaffoldMessenger.of(context);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    tampilPesanDi(messenger, pesan);
  }

  Future<void> _hidupkanKamera() async {
    try {
      await _kamera.start();
    } catch (_) {}
  }

  Future<void> _hidupkanGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _status = 'Nyalakan GPS HP…');
        return;
      }
      var izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }
      if (izin == LocationPermission.denied ||
          izin == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _status = 'Izinkan lokasi, lalu buka scan lagi.');
        }
        return;
      }
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          if (pos.isMocked) {
            _tolakLokasiPalsu();
            return;
          }
          _peringatPalsu = false;
          setState(() {
            _pos = pos;
            _status = _teksJarak(_jarakKeGudang(pos));
          });
          _lanjutkanKodeTahan();
        },
        onError: (_) {
          if (mounted) {
            setState(() => _status = 'GPS terganggu. Tunggu sebentar…');
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _status = 'Lokasi belum siap.');
    }
  }

  void _tolakLokasiPalsu() {
    if (!mounted) return;
    setState(() {
      _pos = null;
      _status = _pesanLokasiPalsu;
    });
    if (_peringatPalsu) return;
    _peringatPalsu = true;
    _pesan(_pesanLokasiPalsu);
  }

  bool _gpsGudangValid() {
    final lat = _lokasi?.latitude;
    final lng = _lokasi?.longitude;
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    if (lat.abs() > 90 || lng.abs() > 180) return false;
    return true;
  }

  double? _jarakKeGudang(Position pos) {
    if (!_gpsGudangValid()) return null;
    return _jarak(
      _lokasi!.latitude!,
      _lokasi!.longitude!,
      pos.latitude,
      pos.longitude,
    );
  }

  double _jarak(double lat1, double lon1, double lat2, double lon2) {
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _teksJarak(double? d) {
    if (!_gpsGudangValid()) {
      return 'Titik lokasi gudang belum diisi.';
    }
    if (d == null) return 'Mencari lokasi…';
    if (d > _batasMeter) {
      return '${d.toStringAsFixed(0)} m lagi. Dekati gudang.';
    }
    return 'Siap scan (${d.toStringAsFixed(0)} m). Arahkan QR.';
  }

  void _pesan(String teks) {
    tampilPesan(context, teks);
  }

  void _onKode(String kode) {
    if (_busy || !_netSiap) return;
    if (kode.trim().toUpperCase() != _kodeGudang) {
      _kodeTahan = null;
      _pesan(
        'QR ini bukan barcode gudang. Scan barcode yang terpasang di gudang.',
      );
      return;
    }
    final pos = _pos;
    if (pos == null || pos.isMocked) {
      _kodeTahan = kode.trim();
      if (_peringatPalsu || (pos?.isMocked ?? false)) {
        _pesan(_pesanLokasiPalsu);
      } else {
        _pesan('Menunggu lokasi…');
      }
      return;
    }
    _kodeTahan = null;
    final d = _jarakKeGudang(pos);
    if (d == null) {
      _pesan('Titik lokasi gudang belum diisi.');
      return;
    }
    if (d > _batasMeter) {
      _pesan('Dekati dulu (${d.toStringAsFixed(0)} m).');
      return;
    }
    unawaited(_kirim(pos));
  }

  void _lanjutkanKodeTahan() {
    final kode = _kodeTahan;
    if (kode == null || _pos == null) return;
    _onKode(kode);
  }

  Future<void> _kirim(Position pos) async {
    if (_busy) return;
    if (pos.isMocked) {
      _tolakLokasiPalsu();
      return;
    }
    _busy = true;
    if (mounted) setState(() {});
    await _kamera.stop();
    try {
      DateTime server;
      try {
        server = await _repo.waktuServer();
      } catch (_) {
        _pesan(
          'Tidak ada internet. Sambungkan internet, lalu scan lagi.',
        );
        await _hidupkanKamera();
        return;
      }
      final waktuHp = DateTime.now();
      final selisih = waktuHp.toUtc().difference(server.toUtc()).abs();
      if (selisih > _toleransiJam) {
        _pesan(
          'Jam HP tidak sesuai waktu Jakarta. Nyalakan waktu otomatis, lalu scan lagi.',
        );
        await _hidupkanKamera();
        return;
      }

      final hasil = await _repo.scan(
        keluar: widget.keluar,
        latitude: pos.latitude,
        longitude: pos.longitude,
        waktu: waktuHp,
      );
      if (!mounted) return;
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      tampilPesan(
        context,
        hasil.keluar ? 'Absensi pulang tercatat.' : 'Absensi masuk tercatat.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      if (Jaringan.mati(e)) {
        _pesan(
          'Tidak ada internet. Sambungkan internet, lalu scan lagi.',
        );
      } else {
        _pesan(_pesanGagal(e));
      }
      await _hidupkanKamera();
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  String _pesanGagal(Object error) {
    if (error is PostgrestException) {
      final m = error.message.trim();
      if (m.isNotEmpty) return m;
    }
    return 'Absensi belum tercatat. Tunggu sebentar, lalu scan lagi.';
  }

  @override
  Widget build(BuildContext context) {
    final keluar = widget.keluar;
    final warna = keluar ? const Color(0xFF2E7D32) : Tema.kuning;
    final teksApp = keluar ? Colors.white : Colors.black;
    final nama = _lokasi?.nama?.trim();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: warna,
        foregroundColor: teksApp,
        title: Text(keluar ? 'Scan pulang' : 'Scan masuk'),
      ),
      body: !_netSiap
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                MobileScanner(
                  controller: _kamera,
                  onDetect: (capture) {
                    final kode = capture.barcodes.first.rawValue ?? '';
                    if (kode.isEmpty) return;
                    _onKode(kode);
                  },
                  errorBuilder: (context, error) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Kamera belum bisa dibuka. Izinkan kamera, lalu buka scan lagi.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
                const IgnorePointer(child: _BingkaiScan()),
                Positioned(
                  top: 16,
                  left: 24,
                  right: 24,
                  child: Column(
                    children: [
                      Text(
                        (nama == null || nama.isEmpty) ? 'Gudang' : nama,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(Tema.pxSudut),
                        ),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

class _BingkaiScan extends StatelessWidget {
  const _BingkaiScan();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PelukisBingkai(Tema.seed),
      child: const SizedBox.expand(),
    );
  }
}

class _PelukisBingkai extends CustomPainter {
  _PelukisBingkai(this.warna);
  final Color warna;

  @override
  void paint(Canvas canvas, Size size) {
    final sisi = size.width * 0.7;
    final hole = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 24),
      width: sisi,
      height: sisi,
    );
    final bg = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(5)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bg, Paint()..color = Colors.black54);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(5)),
      Paint()
        ..color = warna
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
