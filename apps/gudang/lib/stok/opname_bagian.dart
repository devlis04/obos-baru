class PotonganOpname<T> {
  const PotonganOpname({
    required this.indeks,
    required this.baris,
    required this.namaAwal,
    required this.namaAkhir,
  });

  final int indeks;
  final List<T> baris;
  final String namaAwal;
  final String namaAkhir;

  String judulDari(int jumlah) {
    final n = jumlah < 1 ? 1 : jumlah;
    if (n <= 1) return 'Bagian 1';
    return 'Bagian ${indeks + 1} dari $n';
  }

  String get rentang {
    if (baris.isEmpty) return 'Tidak ada barang';
    if (namaAwal.toLowerCase() == namaAkhir.toLowerCase()) return namaAwal;
    return '$namaAwal – $namaAkhir';
  }
}

List<PotonganOpname<T>> bagiOpname<T>(
  List<T> semua, {
  required int jumlah,
  required String Function(T item) namaBarang,
}) {
  final n = jumlah < 1 ? 1 : jumlah;
  final urut = [...semua]
    ..sort(
      (a, b) =>
          namaBarang(a).toLowerCase().compareTo(namaBarang(b).toLowerCase()),
    );
  final total = urut.length;
  final dasar = total ~/ n;
  final sisa = total % n;
  var mulai = 0;
  return List<PotonganOpname<T>>.generate(n, (i) {
    final panjang = dasar + (i < sisa ? 1 : 0);
    final potong = urut.sublist(mulai, mulai + panjang);
    mulai += panjang;
    return PotonganOpname<T>(
      indeks: i,
      baris: potong,
      namaAwal: potong.isEmpty ? '' : namaBarang(potong.first).trim(),
      namaAkhir: potong.isEmpty ? '' : namaBarang(potong.last).trim(),
    );
  });
}
