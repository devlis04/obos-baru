class Uang {
  static int dari(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String angka(int nominal) {
    return nominal.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  static String rp(int nominal) => angka(nominal);

  static String rasio({required int omset, required int laba}) {
    final modal = omset - laba;
    if (omset <= 0 || modal <= 0) return '0.00%';
    return '${((laba / modal) * 100).toStringAsFixed(2)}%';
  }

  static String tanggal(DateTime d) {
    final h = d.day.toString().padLeft(2, '0');
    final b = d.month.toString().padLeft(2, '0');
    return '$h/$b/${d.year}';
  }

  static String isoHari(DateTime d) {
    final h = d.day.toString().padLeft(2, '0');
    final b = d.month.toString().padLeft(2, '0');
    return '${d.year}-$b-$h';
  }
}
