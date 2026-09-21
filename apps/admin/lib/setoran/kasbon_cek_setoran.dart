import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../uang.dart';
import 'setoran_repo.dart';

/// Centang kasbon admin per buku · rute · peran. Chip hijau jika semua klaim dicek.
class KasbonCekSetoran extends ChangeNotifier {
  KasbonCekSetoran._() {
    _muat();
  }

  static final KasbonCekSetoran instance = KasbonCekSetoran._();
  static const _kunciLs = 'obos_admin_kasbon_cek';

  final Map<String, bool> _centang = {};

  String _kunci(DateTime? tanggal, String rute, String peran) {
    final tgl = tanggal == null ? '' : Uang.isoHari(tanggal);
    return '$tgl|$rute|$peran';
  }

  bool centang({
    required DateTime? tanggal,
    required String rute,
    required String peran,
  }) {
    return _centang[_kunci(tanggal, rute, peran)] ?? false;
  }

  void setCentang({
    required DateTime? tanggal,
    required String rute,
    required String peran,
    required bool nilai,
  }) {
    final k = _kunci(tanggal, rute, peran);
    if (nilai) {
      _centang[k] = true;
    } else {
      _centang.remove(k);
    }
    _tulis();
    notifyListeners();
  }

  bool hijau({
    required DateTime? tanggal,
    required String rute,
    required List<BarisSetoranRute> semua,
  }) {
    final daftar = rute == 'Jumlah'
        ? semua
        : semua.where((b) => b.rute == rute).toList();
    var ada = false;
    for (final b in daftar) {
      for (final o in b.orangKasbon) {
        if (o.klaim <= 0) continue;
        ada = true;
        if (!centang(tanggal: tanggal, rute: b.rute, peran: o.peran)) {
          return false;
        }
      }
    }
    return ada;
  }

  void _muat() {
    try {
      final raw = web.window.localStorage.getItem(_kunciLs);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      for (final e in m.entries) {
        if (e.value == true) _centang[e.key.toString()] = true;
      }
    } catch (_) {}
  }

  void _tulis() {
    try {
      web.window.localStorage.setItem(
        _kunciLs,
        jsonEncode(keJson()),
      );
    } catch (_) {}
  }

  Map<String, dynamic> keJson() => {
        for (final e in _centang.entries)
          if (e.value) e.key: true,
      };

  void gabungJson(Object? raw) {
    if (raw is! Map) return;
    for (final e in raw.entries) {
      if (e.value == true) _centang[e.key.toString()] = true;
    }
    _tulis();
    notifyListeners();
  }
}
