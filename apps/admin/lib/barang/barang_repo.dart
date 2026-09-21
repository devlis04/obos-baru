import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import 'barang.dart';
import 'barang_csv.dart';

class BarangRepo {
  BarangRepo(this._sb);
  final SupabaseClient _sb;

  List<Barang> _baca(dynamic hasil) {
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => Barang.fromJson(Map<String, dynamic>.from(e)))
        .where((b) => b.id.isNotEmpty)
        .toList();
  }

  Future<List<Barang>> katalog(String kata) async {
    final list = await semua();
    final q = kata.trim().toLowerCase();
    var keluar = list;
    if (q.isNotEmpty) {
      keluar = list
          .where(
            (b) =>
                b.nama.toLowerCase().contains(q) ||
                b.id.toLowerCase().contains(q) ||
                b.kategori.toLowerCase().contains(q),
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

  Future<List<({int id, String nama, int harga, bool utama})>> pemasok(
    String idBarang,
  ) async {
    final hasil = await Jaringan.denganUlang(
      () => _sb
          .rpc('admin_barang_pemasok_lihat', params: {'p_id_barang': idBarang})
          .timeout(Jaringan.lambat),
    );
    final out = <({int id, String nama, int harga, bool utama})>[];
    if (hasil is! List) return out;
    for (final e in hasil) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = (m['id_supplier'] as num?)?.toInt() ?? 0;
      final nama = (m['nama_supplier']?.toString() ?? '').trim();
      if (id <= 0 || nama.isEmpty) continue;
      out.add((
        id: id,
        nama: nama,
        harga: (m['harga_beli'] as num?)?.toInt() ?? 0,
        utama: m['utama'] == true,
      ));
    }
    return out;
  }

  Future<int?> pemasokUtama(String idBarang) async {
    final hasil = await Jaringan.denganUlang(
      () => _sb
          .rpc('admin_barang_utama_lihat', params: {'p_id_barang': idBarang})
          .timeout(Jaringan.lambat),
    );
    if (hasil is int) return hasil > 0 ? hasil : null;
    if (hasil is num) {
      final n = hasil.toInt();
      return n > 0 ? n : null;
    }
    return null;
  }

  Future<void> setPemasokUtama(String idBarang, int? idSupplier) async {
    final ok = await _sb.rpc(
      'admin_barang_utama_set',
      params: {
        'p_id_barang': idBarang,
        'p_id_supplier': idSupplier ?? 0,
      },
    ).timeout(Jaringan.lambat);
    if (ok != true) {
      throw Exception('Pemasok utama belum tersimpan.');
    }
  }

  Future<List<({int id, String nama})>> daftarSupplier() async {
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc('admin_supplier_daftar').timeout(Jaringan.lambat),
    );
    final out = <({int id, String nama})>[];
    if (hasil is! List) return out;
    for (final e in hasil) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = (m['id'] as num?)?.toInt() ?? 0;
      final nama = (m['nama']?.toString() ?? '').trim();
      if (id <= 0 || nama.isEmpty) continue;
      out.add((id: id, nama: nama));
    }
    return out;
  }

  Future<Barang> simpan(Barang barang) async {
    final hasil = await _sb
        .rpc('admin_barang_simpan', params: {'p_barang': barang.keSimpan()})
        .timeout(Jaringan.lambat);
    final list = _baca(hasil);
    if (list.isEmpty) {
      throw Exception('Barang belum tersimpan.');
    }
    return list.first;
  }

  Future<num> setStok(String id, num stok) async {
    final hasil = await _sb.rpc(
      'admin_barang_stok',
      params: {'p_id_barang': id, 'p_stok': stok},
    ).timeout(Jaringan.lambat);
    num baca(dynamic n) {
      if (n is num) return n;
      return num.tryParse(n?.toString() ?? '') ?? stok;
    }

    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return baca((hasil.first as Map)['stok']);
    }
    if (hasil is Map) {
      return baca(hasil['stok']);
    }
    return stok;
  }

  Future<List<Barang>> semua() async {
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc('admin_barang_semua').timeout(const Duration(seconds: 120)),
    );
    return _baca(hasil);
  }

  Future<List<BarisCsv>> unggahBarang(List<Map<String, dynamic>> baris) async {
    final hasil = await _sb
        .rpc('admin_barang_csv', params: {'p_baris': baris})
        .timeout(const Duration(seconds: 120));
    return _bacaCsv(hasil);
  }

  Future<List<BarisCsv>> unggahStok(List<Map<String, dynamic>> baris) async {
    final hasil = await _sb
        .rpc('admin_barang_stok_csv', params: {'p_baris': baris})
        .timeout(const Duration(seconds: 120));
    return _bacaCsv(hasil);
  }

  List<BarisCsv> _bacaCsv(dynamic hasil) {
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => BarisCsv.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
