import 'dart:async';

import 'package:flutter/widgets.dart';

import 'transaksi/transaksi_cache.dart';

/// Coba kirim antrian saat app dibuka lagi dan setiap 25 detik.
class JagaAntrian with WidgetsBindingObserver {
  JagaAntrian();

  Future<int> Function()? _kirim;
  Future<void> Function(int terkirim, int sisa)? _setelah;
  Timer? _timer;
  bool _jalan = false;
  bool _pasang = false;
  bool _dariResume = false;
  int _sisaPeringat = 0;

  void mulai({
    required Future<int> Function() kirim,
    Future<void> Function(int terkirim, int sisa)? setelah,
  }) {
    _kirim = kirim;
    _setelah = setelah;
    if (!_pasang) {
      WidgetsBinding.instance.addObserver(this);
      _pasang = true;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => coba());
    coba();
  }

  void berhenti() {
    _timer?.cancel();
    _timer = null;
    if (_pasang) {
      WidgetsBinding.instance.removeObserver(this);
      _pasang = false;
    }
    _kirim = null;
    _setelah = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _dariResume = true;
      coba();
    }
  }

  Future<void> coba() async {
    if (_jalan) return;
    final kirim = _kirim;
    if (kirim == null) return;
    _jalan = true;
    try {
      var n = 0;
      try {
        n = await kirim();
      } catch (_) {}
      final setelah = _setelah;
      if (setelah == null) return;
      final sisa = await TransaksiCache.jumlahSiapKirim();
      if (sisa == 0) {
        _sisaPeringat = 0;
        _dariResume = false;
        return;
      }
      final resume = _dariResume;
      _dariResume = false;
      if (n == 0 && !resume && sisa == _sisaPeringat) return;
      _sisaPeringat = sisa;
      await setelah(n, sisa);
    } finally {
      _jalan = false;
    }
  }
}
