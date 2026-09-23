import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';

int _n(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

class IsiMutasi {
  const IsiMutasi({
    required this.id,
    this.tanggalMutasi,
    required this.jumlah,
    this.berita = '',
    this.rekening = '',
    this.rute = '',
    this.status = '',
  });

  final int id;
  final String? tanggalMutasi;
  final int jumlah;
  final String berita;
  final String rekening;
  final String rute;
  final String status;

  bool get terikat =>
      (status == 'cocok' || status == 'manual') && rute.isNotEmpty;

  factory IsiMutasi.dari(Map<String, dynamic> m) {
    final tgl = m['tanggal_mutasi']?.toString();
    return IsiMutasi(
      id: _n(m['id']),
      tanggalMutasi: (tgl == null || tgl.isEmpty || tgl == 'null') ? null : tgl,
      jumlah: _n(m['jumlah']),
      berita: m['berita']?.toString() ?? '',
      rekening: m['rekening_alias']?.toString() ?? '',
      rute: m['rute_pengirim']?.toString() ?? '',
      status: m['status_cocok']?.toString() ?? '',
    );
  }
}

class MutasiRepo {
  MutasiRepo(this._sb);
  final SupabaseClient _sb;

  Future<List<IsiMutasi>> lihat({int? idBuku}) async {
    final hasil = await _sb
        .rpc(
          'admin_mutasi_lihat',
          params: {'p_id_setoran_buku': ?idBuku},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return const [];
    return [
      for (final e in hasil)
        if (e is Map) IsiMutasi.dari(Map<String, dynamic>.from(e)),
    ];
  }

  Future<int> unggah({
    required String namaBerkas,
    required List<Map<String, dynamic>> baris,
  }) async {
    final n = await _sb.rpc(
      'admin_mutasi_unggah',
      params: {
        'p_nama_berkas': namaBerkas,
        'p_baris': baris,
      },
    ).timeout(Jaringan.lambat);
    return _n(n);
  }

  Future<int> hapus({int? idBuku}) async {
    final n = await _sb
        .rpc(
          'admin_mutasi_hapus',
          params: {'p_id_setoran_buku': ?idBuku},
        )
        .timeout(Jaringan.lambat);
    return _n(n);
  }
}

class MutasiSetoran extends ChangeNotifier {
  MutasiSetoran._();
  static final MutasiSetoran instance = MutasiSetoran._();

  List<IsiMutasi> _daftar = const [];
  List<IsiMutasi> get daftar => _daftar;

  void pasang(List<IsiMutasi> daftar) {
    _daftar = daftar;
    notifyListeners();
  }

  int nilai({
    required String rute,
    List<String> semuaRute = const [],
  }) {
    if (rute == 'Jumlah') {
      return semuaRute.fold<int>(0, (n, r) => n + nilai(rute: r));
    }
    var n = 0;
    for (final m in _daftar) {
      if (m.terikat && m.rute == rute) n += m.jumlah;
    }
    return n;
  }
}
