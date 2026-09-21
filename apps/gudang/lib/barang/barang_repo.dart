import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import 'barang.dart';
import 'barang_cache.dart';

class BarangRepo {
  BarangRepo(this._sb);
  final SupabaseClient _sb;

  Future<List<Barang>> katalog() async {
    try {
      final hasil =
          await _sb.rpc('gudang_barang_katalog').timeout(Jaringan.lambat);
      if (hasil is! List) return [];
      final daftar = hasil
          .whereType<Map>()
          .map((e) => Barang.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.id.isNotEmpty)
          .toList();
      await BarangCache.simpan(daftar);
      return daftar;
    } catch (e) {
      if (!Jaringan.mati(e)) rethrow;
      return BarangCache.semua();
    }
  }

  Future<List<Barang>> cari(String kata) async {
    try {
      final hasil = await _sb
          .rpc('gudang_barang_cari', params: {'p_kata': kata})
          .timeout(Jaringan.lambat);
      if (hasil is! List) return [];
      final daftar = hasil
          .whereType<Map>()
          .map((e) => Barang.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.id.isNotEmpty)
          .toList();
      await BarangCache.gabung(daftar);
      return daftar;
    } catch (e) {
      if (!Jaringan.mati(e)) rethrow;
      return BarangCache.saring(await BarangCache.semua(), kata);
    }
  }

  Future<List<Barang>> banyak(List<String> id) async {
    if (id.isEmpty) return [];
    try {
      final hasil = await _sb
          .rpc('gudang_barang_banyak', params: {'p_id': id})
          .timeout(Jaringan.lambat);
      if (hasil is! List) return [];
      final daftar = hasil
          .whereType<Map>()
          .map((e) => Barang.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.id.isNotEmpty)
          .toList();
      await BarangCache.gabung(daftar);
      return daftar;
    } catch (e) {
      if (!Jaringan.mati(e)) rethrow;
      final mau = id.toSet();
      return (await BarangCache.semua()).where((b) => mau.contains(b.id)).toList();
    }
  }
}
