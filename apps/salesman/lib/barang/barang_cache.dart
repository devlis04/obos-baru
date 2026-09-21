import 'dart:convert';

import 'package:obos_core/obos_core.dart';

import 'barang.dart';

class BarangCache {
  static const _kunci = 'barang_json';

  static Future<List<Barang>> semua() async {
    final raw = await PrefsHp.getString(_kunci);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Barang.fromJson(Map<String, dynamic>.from(e)))
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
}
