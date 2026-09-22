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

  String _kunci(DateTime? tanggal, String rute, {int? idBuku}) {
    if (idBuku != null) return 'b$idBuku|$rute';
    final tgl = tanggal == null ? '' : Uang.isoHari(tanggal);
    return '$tgl|$rute';
  }

  IsiTunaiAdmin ambil(DateTime? tanggal, String rute, {int? idBuku}) {
    if (idBuku != null) {
      return _isi[_kunci(tanggal, rute, idBuku: idBuku)] ??
          const IsiTunaiAdmin();
    }
    return _isi[_kunci(tanggal, rute)] ?? const IsiTunaiAdmin();
  }

  static bool _berisi(IsiTunaiAdmin? v) {
    if (v == null) return false;
    if (v.tunai > 0) return true;
    for (final n in v.pecahan) {
      if (n > 0) return true;
    }
    return false;
  }

  int nilai({
    required DateTime? tanggal,
    required String rute,
    List<String> semuaRute = const [],
    int? idBuku,
  }) {
    if (rute == 'Jumlah') {
      return semuaRute.fold<int>(
        0,
        (n, r) =>
            n + ambil(tanggal, r, idBuku: idBuku).tunai,
      );
    }
    return ambil(tanggal, rute, idBuku: idBuku).tunai;
  }

  List<int> pecahanJumlah(
    DateTime? tanggal,
    List<String> semuaRute, {
    int? idBuku,
  }) {
    final out = List<int>.filled(pecahanTunaiAdmin.length, 0);
    for (final r in semuaRute) {
      final p = ambil(tanggal, r, idBuku: idBuku).pecahanLengkap;
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
    int? idBuku,
  }) {
    _isi[_kunci(tanggal, rute, idBuku: idBuku)] = IsiTunaiAdmin(
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

  Map<String, dynamic> keJson({int? idBuku}) {
    final prefix = idBuku == null ? null : 'b$idBuku|';
    return {
      for (final e in _isi.entries)
        if (prefix == null || e.key.startsWith(prefix))
          e.key: {
            'tunai': e.value.tunai,
            'pecahan': e.value.pecahan,
          },
    };
  }

  IsiTunaiAdmin? _dariMap(Object? v) {
    if (v is! Map) return null;
    final pecahan = <int>[];
    final p = v['pecahan'];
    if (p is List) {
      for (final x in p) {
        pecahan.add(int.tryParse(x.toString()) ?? 0);
      }
    }
    return IsiTunaiAdmin(
      tunai: int.tryParse('${v['tunai']}') ?? 0,
      pecahan: pecahan,
    );
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
      final isi = _dariMap(e.value);
      if (isi == null) continue;
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
      if (_berisi(_isi[k]) && !_berisi(isi)) continue;
      _isi[k] = isi;
      ubah = true;
    }
    if (!ubah) return;
    _tulis();
    notifyListeners();
  }
}
