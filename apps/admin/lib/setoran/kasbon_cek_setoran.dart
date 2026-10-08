import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../uang.dart';
import 'kunci_kartu_setoran.dart';
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

  bool _ada(DateTime? tanggal, String rute, String peran, {int? idBuku}) {
    return _centang[_kunci(tanggal, rute, peran, idBuku: idBuku)] == true ||
        (idBuku != null &&
            _centang[_kunci(tanggal, rute, peran)] == true);
  }

  bool centang({
    required DateTime? tanggal,
    required String rute,
    required String peran,
    int? idBuku,
  }) {
    if (_ada(tanggal, rute, peran, idBuku: idBuku)) return true;
    if (peran == 'kasbon') {
      return _ada(tanggal, rute, 'supir', idBuku: idBuku) ||
          _ada(tanggal, rute, 'kenek', idBuku: idBuku);
    }
    if (peran == 'supir' || peran == 'kenek') {
      return _ada(tanggal, rute, 'kasbon', idBuku: idBuku);
    }
    return false;
  }

  void setCentang({
    required DateTime? tanggal,
    required String rute,
    required String peran,
    required bool nilai,
    int? idBuku,
  }) {
    final k = _kunci(tanggal, rute, peran, idBuku: idBuku);
    _centang[k] = nilai;
    _tulis();
    notifyListeners();
    ChipSetoranPersist.instance.minta();
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
        if (flagKartu(e.value)) _centang[e.key.toString()] = true;
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

  Map<String, dynamic> keJson({int? idBuku, DateTime? tanggal}) {
    return {
      for (final e in _centang.entries)
        if (kunciKartuBuku(e.key, idBuku: idBuku, tanggal: tanggal) != null)
          kunciKartuBuku(e.key, idBuku: idBuku, tanggal: tanggal)!: e.value,
    };
  }

  void gabungJson(
    Object? raw, {
    int? idBuku,
    DateTime? tanggal,
    bool bukuTutup = false,
  }) {
    final peta = petaChip(raw);
    if (peta == null) return;
    var ubah = false;
    void taruh(String key, Object? val) {
      final k = kunciKartuBuku(key, idBuku: idBuku, tanggal: tanggal);
      if (k == null) return;
      final nyala = flagKartu(val);
      if (_centang[k] == nyala) return;
      _centang[k] = nyala;
      ubah = true;
    }

    for (final e in peta.entries) {
      final v = e.value;
      if (v is Map) {
        for (final p in v.entries) {
          taruh('${e.key}|${p.key}', p.value);
        }
      } else {
        taruh(e.key.toString(), v);
      }
    }
    if (!ubah) return;
    _tulis();
    notifyListeners();
  }

  void pulihkanDariKlaim({
    required DateTime? tanggal,
    required List<BarisSetoranRute> rute,
    int? idBuku,
  }) {
    var ubah = false;
    for (final b in rute) {
      for (final o in b.orangKasbon) {
        if (o.klaim <= 0) continue;
        if (_ada(tanggal, b.rute, o.peran, idBuku: idBuku)) continue;
        _centang[_kunci(tanggal, b.rute, o.peran, idBuku: idBuku)] = true;
        ubah = true;
      }
    }
    if (!ubah) return;
    _tulis();
    notifyListeners();
  }
}
