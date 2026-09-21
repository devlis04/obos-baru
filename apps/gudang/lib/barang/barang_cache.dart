import 'dart:convert';

import 'package:obos_core/obos_core.dart';

import 'barang.dart';

class BarangCache {
  static const _kunci = 'gudang_barang_json';

  static Future<List<Barang>> semua() async {
    final raw = await PrefsHp.getString(_kunci);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Barang.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> simpan(List<Barang> daftar) async {
    await PrefsHp.setString(
      _kunci,
      jsonEncode(daftar.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> gabung(List<Barang> daftar) async {
    if (daftar.isEmpty) return;
    final map = {for (final b in await semua()) b.id: b};
    for (final b in daftar) {
      map[b.id] = b;
    }
    await simpan(map.values.toList());
  }

  static List<Barang> saring(List<Barang> daftar, String kata) {
    final q = kata.trim().toLowerCase();
    if (q.isEmpty) {
      final out = [...daftar];
      out.sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
      return out.take(80).toList();
    }
    return daftar
        .where(
          (b) =>
              b.nama.toLowerCase().contains(q) ||
              b.id.toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
  }
}
