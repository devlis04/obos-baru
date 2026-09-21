import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';

class OrangAbsensi {
  const OrangAbsensi({
    required this.nama,
    required this.peran,
    this.diDalam = false,
    this.pulang = false,
  });

  final String nama;
  final String peran;
  final bool diDalam;
  final bool pulang;

  bool get oranye => diDalam;
  bool get hijau => pulang && !diDalam;

  Color get warnaTitik {
    if (oranye) return Colors.orange.shade800;
    if (hijau) return Colors.green.shade700;
    return Colors.grey.shade400;
  }

  Color get warnaNama {
    if (oranye) return Colors.orange.shade800;
    if (hijau) return Colors.black;
    return Colors.grey.shade600;
  }

  String get keterangan {
    if (oranye) return 'Sudah scan masuk';
    if (hijau) return 'Sudah scan keluar';
    return 'Belum scan masuk';
  }

  factory OrangAbsensi.dari(Map<String, dynamic> m) {
    final nama = (m['nama']?.toString() ?? '').trim();
    final kunci = (m['nama_kunci']?.toString() ?? '').trim();
    return OrangAbsensi(
      nama: nama.isEmpty ? kunci : nama,
      peran: (m['peran']?.toString() ?? '').trim().toLowerCase(),
      diDalam: m['di_dalam'] == true,
      pulang: m['pulang'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OrangAbsensi &&
      other.nama == nama &&
      other.peran == peran &&
      other.diDalam == diDalam &&
      other.pulang == pulang;

  @override
  int get hashCode => Object.hash(nama, peran, diDalam, pulang);
}

class AbsensiRepo {
  AbsensiRepo(this._sb);
  final SupabaseClient _sb;

  Future<({List<OrangAbsensi> pengirim, List<OrangAbsensi> gudang})>
      lihat({int? idBuku}) async {
    final hasil = await _sb
        .rpc(
          'admin_absensi_buku',
          params: {'p_id_setoran_buku': ?idBuku},
        )
        .timeout(Jaringan.lambat);
    final isi = <OrangAbsensi>[
      if (hasil is List)
        for (final e in hasil)
          if (e is Map) OrangAbsensi.dari(Map<String, dynamic>.from(e)),
    ];
    return (
      pengirim: [for (final o in isi) if (o.peran == 'pengirim') o],
      gudang: [for (final o in isi) if (o.peran == 'gudang') o],
    );
  }
}
