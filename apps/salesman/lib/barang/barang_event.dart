abstract class BarangEvent {}

class MuatBarang extends BarangEvent {
  MuatBarang({this.paksa = false});
  final bool paksa;
}

class TandaiPesan extends BarangEvent {
  TandaiPesan(this.id);
  final String id;
}

class TandaiSemuaPesan extends BarangEvent {}
