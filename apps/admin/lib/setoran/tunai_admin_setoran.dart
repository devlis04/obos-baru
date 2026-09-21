import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../uang.dart';

const pecahanTunaiAdmin = [
  (nilai: 100000, jenis: 'Lembar', label: '100.000'),
  (nilai: 50000, jenis: 'Lembar', label: '50.000'),
  (nilai: 20000, jenis: 'Lembar', label: '20.000'),
  (nilai: 10000, jenis: 'Lembar', label: '10.000'),
  (nilai: 5000, jenis: 'Lembar', label: '5.000'),
  (nilai: 2000, jenis: 'Lembar', label: '2.000'),
  (nilai: 1000, jenis: 'Lembar', label: '1.000'),
  (nilai: 1000, jenis: 'Koin', label: '1.000'),
  (nilai: 500, jenis: 'Koin', label: '500'),
];

class IsiTunaiAdmin {
  const IsiTunaiAdmin({this.tunai = 0, this.pecahan = const []});

  final int tunai;
  final List<int> pecahan;

  List<int> get pecahanLengkap {
    final n = pecahanTunaiAdmin.length;
    if (pecahan.length >= n) return pecahan.sublist(0, n);
    return [...pecahan, ...List<int>.filled(n - pecahan.length, 0)];
  }
}

class TunaiAdminSetoran extends ChangeNotifier {
  TunaiAdminSetoran._() {
    _muat();
  }

  static final TunaiAdminSetoran instance = TunaiAdminSetoran._();
  static const _kunciLs = 'obos_admin_tunai_admin';

  final Map<String, IsiTunaiAdmin> _isi = {};

  String _kunci(DateTime? tanggal, String rute) {
    final tgl = tanggal == null ? '' : Uang.isoHari(tanggal);
    return '$tgl|$rute';
  }

  IsiTunaiAdmin ambil(DateTime? tanggal, String rute) {
    return _isi[_kunci(tanggal, rute)] ?? const IsiTunaiAdmin();
  }

  int nilai({
    required DateTime? tanggal,
    required String rute,
    List<String> semuaRute = const [],
  }) {
    if (rute == 'Jumlah') {
      return semuaRute.fold<int>(
        0,
        (n, r) => n + ambil(tanggal, r).tunai,
      );
    }
    return ambil(tanggal, rute).tunai;
  }

  List<int> pecahanJumlah(DateTime? tanggal, List<String> semuaRute) {
    final out = List<int>.filled(pecahanTunaiAdmin.length, 0);
    for (final r in semuaRute) {
      final p = ambil(tanggal, r).pecahanLengkap;
      for (var i = 0; i < out.length && i < p.length; i++) {
        out[i] += p[i];
      }
    }
    return out;
  }

  void simpan({
    required DateTime? tanggal,
    required String rute,
    required int tunai,
    required List<int> pecahan,
  }) {
    _isi[_kunci(tanggal, rute)] = IsiTunaiAdmin(
      tunai: tunai,
      pecahan: pecahan,
    );
    _tulis();
    notifyListeners();
  }

  void _muat() {
    try {
      final raw = web.window.localStorage.getItem(_kunciLs);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      for (final e in m.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final pecahan = <int>[];
        final p = v['pecahan'];
        if (p is List) {
          for (final x in p) {
            pecahan.add(int.tryParse(x.toString()) ?? 0);
          }
        }
        _isi[e.key.toString()] = IsiTunaiAdmin(
          tunai: int.tryParse('${v['tunai']}') ?? 0,
          pecahan: pecahan,
        );
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
        for (final e in _isi.entries)
          e.key: {
            'tunai': e.value.tunai,
            'pecahan': e.value.pecahan,
          },
      };

  void gabungJson(Object? raw) {
    if (raw is! Map) return;
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final pecahan = <int>[];
      final p = v['pecahan'];
      if (p is List) {
        for (final x in p) {
          pecahan.add(int.tryParse(x.toString()) ?? 0);
        }
      }
      _isi[e.key.toString()] = IsiTunaiAdmin(
        tunai: int.tryParse('${v['tunai']}') ?? 0,
        pecahan: pecahan,
      );
    }
    _tulis();
    notifyListeners();
  }
}
