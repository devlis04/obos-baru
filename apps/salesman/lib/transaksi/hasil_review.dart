class HasilReview {
  const HasilReview({
    required this.keranjang,
    required this.selesai,
    this.pesan,
  });

  final Map<String, int> keranjang;
  final bool selesai;
  final String? pesan;
}
