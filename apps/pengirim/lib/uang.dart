class Uang {
  static String angka(int nominal) {
    return nominal.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  static String rp(int nominal) => 'Rp ${angka(nominal)}';

  static String rasioOmset({required int omset, required int modal}) {
    if (modal <= 0) return '-';
    return '${(((omset - modal) / modal) * 100).toStringAsFixed(1)}%';
  }

  static String rasioItem({required int hargaJual, required int hargaBeli}) {
    if (hargaBeli <= 0) return '-';
    return '${(((hargaJual - hargaBeli) / hargaBeli) * 100).toStringAsFixed(1)}%';
  }

  static String rasioLaba({required int omset, int? laba}) {
    if (laba == null) return '-';
    return rasioOmset(omset: omset, modal: omset - laba);
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

  static String jam(DateTime d) {
    final lokal = d.isUtc ? d.toLocal() : d;
    final jam = lokal.hour.toString().padLeft(2, '0');
    final menit = lokal.minute.toString().padLeft(2, '0');
    return '$jam:$menit';
  }

  static String tanggalJam(DateTime? d) {
    if (d == null) return '';
    return '${tanggal(d.isUtc ? d.toLocal() : d)} ${jam(d)}';
  }

  static String ruteGrup(String rute) {
    final t = rute.trim().toUpperCase();
    if (t.length > 1 && (t.endsWith('D') || t.endsWith('H'))) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }
}
