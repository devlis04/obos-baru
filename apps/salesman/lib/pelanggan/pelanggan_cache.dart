import 'dart:convert';

import 'package:obos_core/obos_core.dart';

import 'pelanggan.dart';

class PelangganCache {
  static const _kunci = 'pelanggan_json';

  static Future<List<Pelanggan>> semua() async {
    final raw = await PrefsHp.getString(_kunci);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Pelanggan.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> simpan(List<Pelanggan> daftar) async {
    await PrefsHp.setString(
      _kunci,
      jsonEncode(daftar.map((e) => e.toJson()).toList()),
    );
  }

  static List<Pelanggan> saring(List<Pelanggan> semua, String hari, String rute) {
    final list = semua
        .where((t) => t.visit == hari && t.rute == rute)
        .toList()
      ..sort((a, b) => (a.urutan ?? 0).compareTo(b.urutan ?? 0));
    return list;
  }

  static Future<void> timpaHari({
    required String hari,
    required String rute,
    required List<Pelanggan> daftar,
  }) async {
    final semua = await PelangganCache.semua();
    final lain = semua
        .where((t) => !(t.visit == hari && t.rute == rute))
        .toList();
    await simpan([...lain, ...daftar]);
  }

  static Future<void> tambah(Pelanggan toko) async {
    final semua = await PelangganCache.semua();
    await simpan([...semua, toko]);
  }

  static Future<void> gantiId(String lama, Pelanggan baru) async {
    final semua = await PelangganCache.semua();
    await simpan([
      for (final t in semua)
        if (t.id == lama) baru else t,
    ]);
  }

  static Future<void> gabungCloud(List<Pelanggan> cloud) async {
    final lokal = await PelangganCache.semua();
    final lama = {for (final t in lokal) t.id: t};
    final gabung = [
      for (final t in cloud)
        t.salin(
          waktuMasuk: t.waktuMasuk ?? lama[t.id]?.waktuMasuk,
          waktuKeluar: t.waktuKeluar ?? lama[t.id]?.waktuKeluar,
        ),
      ...lokal.where((t) => t.id.startsWith('TMP')),
    ];
    await simpan(gabung);
  }
}
