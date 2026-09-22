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

  String _kunci(DateTime? tanggal, String rute, String peran, {int? idBuku}) {
    if (idBuku != null) return 'b$idBuku|$rute|$peran';
    final tgl = tanggal == null ? '' : Uang.isoHari(tanggal);
    return '$tgl|$rute|$peran';
  }

  bool centang({
    required DateTime? tanggal,
    required String rute,
    required String peran,
    int? idBuku,
  }) {
    return _centang[_kunci(tanggal, rute, peran, idBuku: idBuku)] == true;
  }

  void setCentang({
    required DateTime? tanggal,
    required String rute,
    required String peran,
    required bool nilai,
    int? idBuku,
  }) {
    final k = _kunci(tanggal, rute, peran, idBuku: idBuku);
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
    int? idBuku,
  }) {
    final daftar = rute == 'Jumlah'
        ? semua
        : semua.where((b) => b.rute == rute).toList();
    var ada = false;
    for (final b in daftar) {
      for (final o in b.orangKasbon) {
        if (o.klaim <= 0) continue;
        ada = true;
        if (!centang(
          tanggal: tanggal,
          rute: b.rute,
          peran: o.peran,
          idBuku: idBuku,
        )) {
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

  Map<String, dynamic> keJson({int? idBuku}) {
    final prefix = idBuku == null ? null : 'b$idBuku|';
    return {
      for (final e in _centang.entries)
        if (e.value && (prefix == null || e.key.startsWith(prefix))) e.key: true,
    };
  }

  void gabungJson(
    Object? raw, {
    int? idBuku,
    DateTime? tanggal,
    bool bukuTutup = false,
  }) {
    if (raw is! Map) return;
    var ubah = false;
    final iso = tanggal == null ? null : Uang.isoHari(tanggal);
    for (final e in raw.entries) {
      if (e.value != true) continue;
      var k = e.key.toString();
      if (idBuku != null) {
        if (k.startsWith('b$idBuku|')) {
          // kunci buku ini
        } else if (bukuTutup &&
            iso != null &&
            k.startsWith('$iso|') &&
            !k.startsWith('b')) {
          k = 'b$idBuku|${k.substring(iso.length + 1)}';
        } else {
          continue;
        }
      }
      _centang[k] = true;
      ubah = true;
    }
    if (!ubah) return;
    _tulis();
    notifyListeners();
  }
}
