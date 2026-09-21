import 'dart:convert';

import 'package:obos_core/obos_core.dart';

class OpnameDraf {
  static const _kunci = 'opname_draf_fisik';

  static Future<({int? buku, Map<String, String> isi})> baca() async {
    final raw = await PrefsHp.getString(_kunci);
    if (raw == null || raw.isEmpty) {
      return (buku: null, isi: <String, String>{});
    }
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return (buku: null, isi: <String, String>{});
      final buku = (j['buku'] as num?)?.toInt();
      final isi = <String, String>{};
      final m = j['isi'];
      if (m is Map) {
        m.forEach((k, v) {
          final id = k.toString();
          if (id.isEmpty) return;
          isi[id] = v?.toString() ?? '';
        });
      }
      return (buku: buku, isi: isi);
    } catch (_) {
      return (buku: null, isi: <String, String>{});
    }
  }

  static Future<void> simpan({
    required int buku,
    required Map<String, String> isi,
  }) async {
    await PrefsHp.setString(
      _kunci,
      jsonEncode({
        'buku': buku,
        'isi': isi,
      }),
    );
  }

  static Future<void> hapus() async {
    await PrefsHp.hapus(_kunci);
  }
}
