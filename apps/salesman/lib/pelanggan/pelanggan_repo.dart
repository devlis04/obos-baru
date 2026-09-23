import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import 'pelanggan.dart';
import 'pelanggan_cache.dart';

class PelangganRepo {
  PelangganRepo(this._sb);
  final SupabaseClient _sb;

  static const _kolom =
      'id_pelanggan, nama_pelanggan, rute, visit, urutan, latitude, longitude';

  Future<List<Pelanggan>> unduhRute(String rute, {Duration? batas}) async {
    final tunggu = batas ?? Jaringan.lambat;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    const ukuran = 200;
    while (from < 800) {
      final to = from + ukuran - 1;
      final page = await _sb
          .from('pelanggan')
          .select(_kolom)
          .eq('rute', rute)
          .order('urutan', ascending: true)
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

    final kunjungan = await _kunjunganMingguIni(rute);
    final daftar = rows.map((row) {
      final id = row['id_pelanggan']?.toString() ?? '';
      final k = kunjungan[id];
      return Pelanggan.fromJson({
        ...row,
        'waktu_masuk': k?.$1?.toIso8601String(),
        'waktu_keluar': k?.$2?.toIso8601String(),
      });
    }).toList();

    await PelangganCache.gabungCloud(daftar);
    return daftar;
  }

  Future<List<Pelanggan>> tokoRute(String rute) async {
    final kode = rute.trim();
    if (kode.isEmpty) return [];
    try {
      return await unduhRute(kode, batas: Jaringan.cepat);
    } catch (_) {}
    return (await PelangganCache.semua())
        .where((t) => t.rute == kode && !t.id.startsWith('TMP'))
        .toList();
  }

  Future<Set<String>> idKunjunganJadwal({
    required String rute,
    required DateTime dari,
    required DateTime sampai,
    required Map<String, String> visitToko,
  }) async {
    final kode = rute.trim();
    if (kode.isEmpty) return {};
    final hasil = <String>{};
    var from = 0;
    const ukuran = 200;
    while (from < 2000) {
      final to = from + ukuran - 1;
      final page = await _sb
          .from('kunjungan_sales')
          .select('id_pelanggan, tanggal')
          .eq('rute', kode)
          .gte('tanggal', MingguKunjungan.iso(dari))
          .lte('tanggal', MingguKunjungan.iso(sampai))
          .range(from, to)
          .timeout(Jaringan.lambat);
      final list = (page as List).whereType<Map>().toList();
      for (final row in list) {
        final id = row['id_pelanggan']?.toString() ?? '';
        if (id.isEmpty) continue;
        final tgl = row['tanggal']?.toString() ?? '';
        final p = tgl.split('-');
        if (p.length < 3) continue;
        final hari = DateTime(
          int.tryParse(p[0]) ?? 0,
          int.tryParse(p[1]) ?? 0,
          int.tryParse(p[2]) ?? 0,
        );
        if (visitToko[id] == MingguKunjungan.namaHari(hari)) hasil.add(id);
      }
      if (list.length < ukuran) break;
      from += ukuran;
    }
    return hasil;
  }

  Future<Set<String>> idKunjunganRentang({
    required String rute,
    required DateTime dari,
    required DateTime sampai,
  }) async {
    final kode = rute.trim();
    if (kode.isEmpty) return {};
    final hasil = <String>{};
    var from = 0;
    const ukuran = 200;
    while (from < 2000) {
      final to = from + ukuran - 1;
      final page = await _sb
          .from('kunjungan_sales')
          .select('id_pelanggan')
          .eq('rute', kode)
          .gte('tanggal', MingguKunjungan.iso(dari))
          .lte('tanggal', MingguKunjungan.iso(sampai))
          .range(from, to)
          .timeout(Jaringan.lambat);
      final list = (page as List).whereType<Map>().toList();
      for (final row in list) {
        final id = row['id_pelanggan']?.toString() ?? '';
        if (id.isNotEmpty) hasil.add(id);
      }
      if (list.length < ukuran) break;
      from += ukuran;
    }
    return hasil;
  }

  Future<Map<String, (DateTime?, DateTime?)>> _kunjunganMingguIni(
    String rute,
  ) async {
    final hasil = <String, (DateTime?, DateTime?)>{};
    try {
      final page = await _sb
          .from('kunjungan_sales')
          .select('id_pelanggan, waktu_masuk, waktu_keluar')
          .eq('rute', rute)
          .gte('tanggal', MingguKunjungan.iso(MingguKunjungan.senin()))
          .lte('tanggal', MingguKunjungan.iso(MingguKunjungan.minggu()))
          .timeout(Jaringan.lambat);
      for (final row in page as List) {
        if (row is! Map) continue;
        final id = row['id_pelanggan']?.toString() ?? '';
        if (id.isEmpty) continue;
        hasil[id] = (
          Pelanggan.parseWaktu(row['waktu_masuk']),
          Pelanggan.parseWaktu(row['waktu_keluar']),
        );
      }
    } catch (_) {}
    return hasil;
  }

  Future<DateTime> waktuServer() async {
    final hasil = await _sb.rpc('sales_waktu_sekarang').timeout(Jaringan.cepat);
    final waktu = Pelanggan.parseWaktu(hasil);
    if (waktu == null) throw Exception('waktu');
    return waktu;
  }

  Future<DateTime> scanKunjungan({
    required String id,
    required bool keluar,
    required double latitude,
    required double longitude,
    required DateTime waktu,
  }) async {
    final hasil = await _sb
        .rpc(
          'sales_scan_kunjungan',
          params: {
            'p_id_pelanggan': id,
            'p_keluar': keluar,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_waktu': waktu.toUtc().toIso8601String(),
          },
        )
        .timeout(Jaringan.lambat);
    final tersimpan = Pelanggan.parseWaktu(hasil);
    if (tersimpan == null) throw Exception('gagal_scan');
    return tersimpan;
  }

  Future<bool> kirimUrutan({
    required String visit,
    required List<String> id,
  }) async {
    try {
      final ok = await _sb
          .rpc(
            'sales_set_urutan',
            params: {'p_visit': visit, 'p_id': id},
          )
          .timeout(Jaringan.lambat);
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> insertPelanggan({
    required String nama,
    required double latitude,
    required double longitude,
    required String visit,
    required int urutan,
  }) async {
    try {
      final hasil = await _sb
          .rpc(
            'sales_insert_pelanggan',
            params: {
              'p_nama': nama,
              'p_latitude': latitude,
              'p_longitude': longitude,
              'p_visit': visit,
              'p_urutan': urutan,
            },
          )
          .timeout(Jaringan.lambat);
      return _idSbgo(hasil);
    } catch (_) {
      return null;
    }
  }

  static String? _idSbgo(dynamic hasil) {
    if (hasil == null) return null;
    if (hasil is String) {
      final s = hasil.trim();
      return s.startsWith('SBGO') ? s : null;
    }
    if (hasil is List && hasil.isNotEmpty) return _idSbgo(hasil.first);
    if (hasil is Map) {
      return _idSbgo(
        hasil['sales_insert_pelanggan'] ??
            hasil['id_pelanggan'] ??
            hasil['id'],
      );
    }
    final s = hasil.toString().trim();
    return s.startsWith('SBGO') ? s : null;
  }
}
