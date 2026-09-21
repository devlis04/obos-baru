import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../uang.dart';
import 'buku_hari.dart';
import 'ringkas_rute.dart';

class KartuRepo {
  KartuRepo(this._sb);
  final SupabaseClient _sb;

  Future<BukuHari?> bukuHari([DateTime? tanggal]) async {
    final hasil = await _sb
        .rpc(
          'setoran_buku_untuk_hari',
          params: {
            if (tanggal != null) 'p_tanggal': Uang.isoHari(tanggal),
          },
        )
        .timeout(Jaringan.lambat);
    return BukuHari.dari(hasil);
  }

  Future<List<RingkasRute>> untukTanggal(DateTime tanggal) async {
    final hasil = await _sb
        .rpc(
          'gudang_kartu_rute',
          params: {'p_tanggal': Uang.isoHari(tanggal)},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => RingkasRute.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.rute.isNotEmpty)
        .toList();
  }
}
