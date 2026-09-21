import 'pelanggan.dart';

abstract class PelangganState {}

class PelangganAwal extends PelangganState {}

class PelangganMemuat extends PelangganState {
  PelangganMemuat(this.hari);
  final String hari;
}

class PelangganSiap extends PelangganState {
  PelangganSiap({
    required this.hari,
    required this.rute,
    required this.daftar,
    this.dariCache = false,
  });
  final String hari;
  final String rute;
  final List<Pelanggan> daftar;
  final bool dariCache;
}

class PelangganKosongNet extends PelangganState {
  PelangganKosongNet(this.hari, this.rute);
  final String hari;
  final String rute;
}

class PelangganGagal extends PelangganState {
  PelangganGagal(this.pesan, this.hari);
  final String pesan;
  final String hari;
}

extension PelangganHariDaftar on PelangganState {
  String? get hariDaftar {
    if (this is PelangganMemuat) return (this as PelangganMemuat).hari;
    if (this is PelangganSiap) return (this as PelangganSiap).hari;
    if (this is PelangganKosongNet) return (this as PelangganKosongNet).hari;
    if (this is PelangganGagal) return (this as PelangganGagal).hari;
    return null;
  }
}
