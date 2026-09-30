/// Kunci chip setoran: `b{id}|…` atau `YYYY-MM-DD|…`.
String? kunciKartuBuku(String k, {int? idBuku}) {
  if (idBuku == null) return k;
  if (k.startsWith('b$idBuku|')) return k;
  if (RegExp(r'^b\d+\|').hasMatch(k)) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}\|').hasMatch(k)) {
    return 'b$idBuku|${k.substring(11)}';
  }
  return k;
}
