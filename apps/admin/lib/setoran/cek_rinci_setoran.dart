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

  String _kunci(DateTime? tanggal, String jenis, String? rute, {int? idBuku}) {
    final tgl = tanggal == null ? '' : Uang.isoHari(tanggal);
    final kepala = idBuku != null ? 'b$idBuku' : tgl;
    return '$kepala|$jenis|${rute ?? ''}';
  }

  Set<String> centang({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
    int? idBuku,
  }) {
    final sini = _centang[_kunci(tanggal, jenis, rute, idBuku: idBuku)];
    if (sini == null || sini.isEmpty) return {};
    return Set.of(sini);
  }

  bool hijau({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
    int? idBuku,
  }) {
    return _hijau[_kunci(tanggal, jenis, rute, idBuku: idBuku)] == true;
  }

  void simpanTutup({
    required DateTime? tanggal,
    required String jenis,
    String? rute,
    required List<TokoSetoranRinci> toko,
    required Set<String> centang,
    Set<String>? wajib,
    int? idBuku,
  }) {
    final k = _kunci(tanggal, jenis, rute, idBuku: idBuku);
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
    int? idBuku,
  }) {
    final k = _kunci(tanggal, jenis, rute, idBuku: idBuku);
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

  Map<String, dynamic> keJson({int? idBuku}) {
    final prefix = idBuku == null ? null : 'b$idBuku|';
    return {
      'centang': {
        for (final e in _centang.entries)
          if (prefix == null || e.key.startsWith(prefix)) e.key: e.value.toList(),
      },
      'hijau': {
        for (final e in _hijau.entries)
          if (e.value && (prefix == null || e.key.startsWith(prefix)))
            e.key: true,
      },
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

    String? kunciMasuk(String k) {
      if (idBuku == null) return k;
      if (k.startsWith('b$idBuku|')) return k;
      if (bukuTutup &&
          iso != null &&
          k.startsWith('$iso|') &&
          !k.startsWith('b')) {
        return 'b$idBuku|${k.substring(iso.length + 1)}';
      }
      return null;
    }

    final c = raw['centang'];
    if (c is Map) {
      for (final e in c.entries) {
        final v = e.value;
        if (v is! List) continue;
        final masuk = {for (final x in v) x.toString()};
        if (masuk.isEmpty) continue;
        final k = kunciMasuk(e.key.toString());
        if (k == null) continue;
        final lama = _centang[k] ?? {};
        _centang[k] = {...lama, ...masuk};
        ubah = true;
      }
    }
    final h = raw['hijau'];
    if (h is Map) {
      for (final e in h.entries) {
        if (e.value != true) continue;
        final k = kunciMasuk(e.key.toString());
        if (k == null) continue;
        _hijau[k] = true;
        ubah = true;
      }
    }
    if (!ubah) return;
    _tulis();
    notifyListeners();
  }
}
