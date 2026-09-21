import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import 'barang.dart';
import 'barang_cache.dart';

class BarangRepo {
  BarangRepo(this._sb);
  final SupabaseClient _sb;

  static const _kolom =
      'id_barang, id_grup, nama_barang, kategori, stok, harga_beli, harga_jual, '
      'min_strat_1, jual_strat_1, min_strat_2, jual_strat_2, min_strat_3, jual_strat_3, '
      'min_strat_4, jual_strat_4, min_strat_5, jual_strat_5';

  Future<List<Barang>> unduh({Duration? batas}) async {
    final tunggu = batas ?? Jaringan.lambat;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    const ukuran = 200;
    while (from < 3000) {
      final to = from + ukuran - 1;
      final page = await _sb
          .from('barang')
          .select(_kolom)
          .order('nama_barang', ascending: true)
          .range(from, to)
          .timeout(tunggu);
      final list = (page as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rows.addAll(list);
      if (list.length < ukuran) break;
      from += ukuran;
    }
    final daftar = rows.map(Barang.fromJson).where((b) => b.id.isNotEmpty).toList();
    await BarangCache.simpan(daftar);
    return daftar;
  }
}
