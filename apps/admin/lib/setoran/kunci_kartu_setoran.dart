import '../uang.dart';

/// Kunci chip setoran: `b{id}|…` atau `YYYY-MM-DD|…`.
String? kunciKartuBuku(
  String k, {
  int? idBuku,
  DateTime? tanggal,
}) {
  if (idBuku == null) return k;
  if (k.startsWith('b$idBuku|')) return k;
  if (RegExp(r'^b\d+\|').hasMatch(k)) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}\|').hasMatch(k)) {
    final tgl = tanggal == null ? null : Uang.isoHari(tanggal);
    if (tgl != null && !k.startsWith('$tgl|')) return null;
    return 'b$idBuku|${k.substring(11)}';
  }
  return 'b$idBuku|$k';
}

bool flagKartu(Object? v) {
  if (v == true || v == 1) return true;
  final s = v?.toString().toLowerCase().trim();
  return s == 'true' || s == 't' || s == '1';
}
