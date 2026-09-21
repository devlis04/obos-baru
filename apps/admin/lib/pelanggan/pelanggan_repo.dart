import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import 'pelanggan.dart';
import 'pelanggan_csv.dart';

class PelangganRepo {
  PelangganRepo(this._sb);
  final SupabaseClient _sb;

  List<Pelanggan> _baca(dynamic hasil) {
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => Pelanggan.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  Future<List<Pelanggan>> katalog(String kata) async {
    final list = await semua();
    final q = kata.trim().toLowerCase();
    var keluar = list;
    if (q.isNotEmpty) {
      keluar = list
          .where(
            (p) =>
                p.nama.toLowerCase().contains(q) ||
                p.id.toLowerCase().contains(q) ||
                p.rute.toLowerCase().contains(q) ||
                p.visit.toLowerCase().contains(q),
          )
          .toList();
    }
    keluar.sort((a, b) {
      if (a.aktif != b.aktif) return a.aktif ? -1 : 1;
      final n = a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
      if (n != 0) return n;
      return a.id.toLowerCase().compareTo(b.id.toLowerCase());
    });
    return keluar;
  }

  Future<List<({String rute, String nama})>> ruteSales() async {
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc('admin_rute_sales').timeout(Jaringan.lambat),
    );
    final out = <({String rute, String nama})>[];
    if (hasil is! List) return out;
    for (final e in hasil) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final rute = (m['rute']?.toString() ?? '').trim();
      if (rute.isEmpty) continue;
      out.add((
        rute: rute,
        nama: (m['nama']?.toString() ?? '').trim(),
      ));
    }
    return out;
  }

  Future<Pelanggan> simpan(Pelanggan toko) async {
    final hasil = await _sb
        .rpc('admin_pelanggan_simpan', params: {'p_toko': toko.keSimpan()})
        .timeout(Jaringan.lambat);
    final list = _baca(hasil);
    if (list.isEmpty) {
      throw Exception('Pelanggan belum tersimpan.');
    }
    return list.first;
  }

  Future<List<Pelanggan>> semua() async {
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc('admin_pelanggan_semua').timeout(const Duration(seconds: 120)),
    );
    return _baca(hasil);
  }

  Future<List<BarisCsvPelanggan>> unggah(List<Map<String, dynamic>> baris) async {
    final hasil = await _sb
        .rpc('admin_pelanggan_csv', params: {'p_baris': baris})
        .timeout(const Duration(seconds: 120));
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => BarisCsvPelanggan.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
