import 'barang.dart';
import 'pesan_katalog.dart';

abstract class BarangState {}

class BarangAwal extends BarangState {}

class BarangMemuat extends BarangState {}

class BarangSiap extends BarangState {
  BarangSiap(
    this.daftar, {
    this.dariCache = false,
    this.notices = const [],
  });

  final List<Barang> daftar;
  final bool dariCache;
  final List<PesanKatalog> notices;

  int get belumDibaca => notices.where((e) => !e.sudahDibaca).length;
}

class BarangKosongNet extends BarangState {}

class BarangGagal extends BarangState {
  BarangGagal(this.pesan);
  final String pesan;
}
