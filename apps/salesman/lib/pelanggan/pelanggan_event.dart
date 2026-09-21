import 'dart:async';

abstract class PelangganEvent {}

class MuatHari extends PelangganEvent {
  MuatHari(this.hari, {this.paksa = false});
  final String hari;
  final bool paksa;
}

class GeserUrutan extends PelangganEvent {
  GeserUrutan({required this.lama, required this.baru});
  final int lama;
  final int baru;
}

class TambahPelanggan extends PelangganEvent {
  TambahPelanggan({
    required this.nama,
    required this.hari,
    required this.latitude,
    required this.longitude,
    required this.selesai,
  });
  final String nama;
  final String hari;
  final double latitude;
  final double longitude;
  final Completer<bool> selesai;
}

class CatatKunjungan extends PelangganEvent {
  CatatKunjungan({
    required this.id,
    this.waktuMasuk,
    this.waktuKeluar,
    Completer<void>? selesai,
  }) : selesai = selesai ?? Completer<void>();
  final String id;
  final DateTime? waktuMasuk;
  final DateTime? waktuKeluar;
  final Completer<void> selesai;
}
