import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';

class StatusAbsensi {
  const StatusAbsensi({
    required this.login,
    required this.masuk,
    this.idAbsensi,
    this.waktuMasuk,
  });

  final bool login;
  final bool masuk;
  final int? idAbsensi;
  final DateTime? waktuMasuk;

  static const kosong = StatusAbsensi(login: false, masuk: false);

  String jamMasuk() {
    final w = waktuMasuk;
    if (w == null) return '';
    final lokal = w.isUtc ? w.toLocal() : w;
    final jam = lokal.hour.toString().padLeft(2, '0');
    final menit = lokal.minute.toString().padLeft(2, '0');
    return '$jam:$menit';
  }
}

class HasilAbsensi {
  const HasilAbsensi({
    required this.idAbsensi,
    required this.keluar,
  });

  final int idAbsensi;
  final bool keluar;
}

class LokasiGudang {
  const LokasiGudang({this.nama, this.latitude, this.longitude});

  final String? nama;
  final double? latitude;
  final double? longitude;
}

class AbsensiRepo {
  AbsensiRepo(this._sb);
  final SupabaseClient _sb;

  Future<DateTime> waktuServer() async {
    final hasil = await _sb.rpc('gudang_waktu_sekarang').timeout(Jaringan.lambat);
    if (hasil is String) {
      return DateTime.parse(hasil.replaceFirst(' ', 'T'));
    }
    return DateTime.parse(hasil.toString());
  }

  Future<LokasiGudang> lokasiUtama() async {
    final hasil = await _sb.rpc('gudang_lokasi_utama').timeout(Jaringan.lambat);
    if (hasil is! Map) return const LokasiGudang();
    final map = Map<String, dynamic>.from(hasil);
    return LokasiGudang(
      nama: map['nama']?.toString(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  Future<StatusAbsensi> status() async {
    final hasil = await _sb.rpc('pengirim_status_lantai').timeout(Jaringan.lambat);
    if (hasil is! Map) return StatusAbsensi.kosong;
    final map = Map<String, dynamic>.from(hasil);
    DateTime? waktu;
    final raw = map['waktu_masuk']?.toString();
    if (raw != null && raw.isNotEmpty) {
      waktu = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }
    return StatusAbsensi(
      login: map['login'] == true,
      masuk: map['absensi_terbuka'] == true,
      idAbsensi: (map['id_absensi'] as num?)?.toInt(),
      waktuMasuk: waktu,
    );
  }

  Future<HasilAbsensi> scan({
    required bool keluar,
    required double latitude,
    required double longitude,
    required DateTime waktu,
  }) async {
    final hasil = await _sb
        .rpc(
          'pengirim_scan_absensi',
          params: {
            'p_keluar': keluar,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_waktu': waktu.toUtc().toIso8601String(),
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is! Map) {
      throw Exception('gagal_absensi');
    }
    final map = Map<String, dynamic>.from(hasil);
    return HasilAbsensi(
      idAbsensi: (map['id_absensi'] as num?)?.toInt() ?? 0,
      keluar: map['keluar'] == true,
    );
  }
}
