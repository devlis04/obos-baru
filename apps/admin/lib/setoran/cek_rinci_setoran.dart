import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../uang.dart';
import 'setoran_repo.dart';

/// Centang cek admin per buku · jenis · rute. Chip hijau setelah semua toko
/// dicentang lalu dialog ditutup.
class CekRinciSetoran extends ChangeNotifier {
  CekRinciSetoran._() {
    _muat();
  }

  static final CekRinciSetoran instance = CekRinciSetoran._();
  static const _kunciLs = 'obos_admin_cek_rinci';

  final Map<String, Set<String>> _centang = {};
  final Map<String, bool> _hijau = {};

  static String kunciToko(TokoSetoranRinci t) =>
      '${t.idPelanggan}|${t.rutePengirim}';

  static String kunciBarang(
    TokoSetoranRinci t,
    NotaSetoranRinci n,
    SkuSetoranRinci s,
  ) =>
      '${t.idPelanggan}|${t.rutePengirim}|${n.id}|${s.idBarang}';

  static Set<String> kunciSemuaBarang(List<TokoSetoranRinci> toko) {
    return {
      for (final t in toko)
        for (final n in t.notaList)
          for (final s in n.sku) kunciBarang(t, n, s),
    };
  }

  static String kunciNota(TokoSetoranRinci t, NotaSetoranRinci n) =>
      '${t.idPelanggan}|${t.rutePengirim}|${n.id}';

  static Set<String> kunciSemuaNota(List<TokoSetoranRinci> toko) {
    return {
      for (final t in toko)
        for (final n in t.notaList) kunciNota(t, n),
    };
  }

  String _kunci(DateTime? tanggal, String jenis, String? rute) {
    final tgl = tanggal == null ? '' : Uang.isoHari(tanggal);
    return '$tgl|$jenis|${rute ?? ''}';
  }

  Set<String> centang({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
  }) {
    final k = _kunci(tanggal, jenis, rute);
    final sini = _centang[k];
    if (sini != null && sini.isNotEmpty) return Set.of(sini);
    final akhir = '|$jenis|${rute ?? ''}';
    for (final e in _centang.entries) {
      if (e.key == k || !e.key.endsWith(akhir) || e.value.isEmpty) continue;
      _centang[k] = Set.of(e.value);
      if (_hijau[e.key] == true) _hijau[k] = true;
      _tulis();
      return Set.of(e.value);
    }
    return Set.of(sini ?? const {});
  }

  bool hijau({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
  }) {
    final k = _kunci(tanggal, jenis, rute);
    if (_hijau[k] == true) return true;
    final akhir = '|$jenis|${rute ?? ''}';
    for (final e in _hijau.entries) {
      if (e.key == k || !e.key.endsWith(akhir) || e.value != true) continue;
      _hijau[k] = true;
      return true;
    }
    return false;
  }

  void simpanTutup({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
    required List<TokoSetoranRinci> toko,
    required Set<String> centang,
    Set<String>? wajib,
  }) {
    final k = _kunci(tanggal, jenis, rute);
    _centang[k] = Set.of(centang);
    final target = wajib ?? {for (final t in toko) kunciToko(t)};
    _hijau[k] = target.isNotEmpty && target.every(_centang[k]!.contains);
    _tulis();
    notifyListeners();
  }

  void gabungBarang({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
    required Set<String> kunciNota,
    required Set<String> centangNota,
    required Set<String> wajib,
  }) {
    final k = _kunci(tanggal, jenis, rute);
    final s = Set<String>.of(_centang[k] ?? const {});
    s.removeAll(kunciNota);
    s.addAll(centangNota);
    _centang[k] = s;
    _hijau[k] = wajib.isNotEmpty && wajib.every(s.contains);
    _tulis();
    notifyListeners();
  }

  void _muat() {
    try {
      final raw = web.window.localStorage.getItem(_kunciLs);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      final c = m['centang'];
      if (c is Map) {
        for (final e in c.entries) {
          final v = e.value;
          if (v is List) {
            _centang[e.key.toString()] = {
              for (final x in v) x.toString(),
            };
          }
        }
      }
      final h = m['hijau'];
      if (h is Map) {
        for (final e in h.entries) {
          _hijau[e.key.toString()] = e.value == true;
        }
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
        'centang': {
          for (final e in _centang.entries) e.key: e.value.toList(),
        },
        'hijau': _hijau,
      };

  void gabungJson(Object? raw) {
    if (raw is! Map) return;
    var ubah = false;
    final c = raw['centang'];
    if (c is Map) {
      for (final e in c.entries) {
        final v = e.value;
        if (v is! List) continue;
        final masuk = {for (final x in v) x.toString()};
        if (masuk.isEmpty) continue;
        final k = e.key.toString();
        final lama = _centang[k] ?? {};
        _centang[k] = {...lama, ...masuk};
        ubah = true;
      }
    }
    final h = raw['hijau'];
    if (h is Map) {
      for (final e in h.entries) {
        if (e.value != true) continue;
        _hijau[e.key.toString()] = true;
        ubah = true;
      }
    }
    if (!ubah) return;
    _tulis();
    notifyListeners();
  }
}
