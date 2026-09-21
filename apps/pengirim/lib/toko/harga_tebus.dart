import '../beranda/kartu_toko.dart';

String kunciGrupTebus(ItemNota item) {
  final grup = item.idGrup.trim();
  return grup.isEmpty ? item.idBarang : grup;
}

int qtyGrupTebus({
  required ItemNota item,
  required List<ItemNota> semua,
  required Map<String, int> qty,
}) {
  final kunci = kunciGrupTebus(item);
  var n = 0;
  for (final x in semua) {
    if (kunciGrupTebus(x) != kunci) continue;
    final q = qty[x.idBarang] ?? 0;
    if (q > 0) n += q;
  }
  return n;
}

int hargaJualTebus({
  required ItemNota item,
  required List<ItemNota> semua,
  required Map<String, int> qty,
}) {
  final total = qtyGrupTebus(item: item, semua: semua, qty: qty);
  var harga = item.hargaJual;
  if (harga <= 0) {
    harga =
        item.hargaJualOrder > 0 ? item.hargaJualOrder : item.hargaJualPacked;
  }
  var maxMin = 0;
  for (final s in item.strataAktif) {
    if (total >= s.minimal && s.minimal > maxMin) {
      maxMin = s.minimal;
      harga = s.jual;
    }
  }
  return harga;
}

int omsetTebus(List<ItemNota> semua, Map<String, int> qty) {
  var n = 0;
  for (final it in semua) {
    final q = qty[it.idBarang] ?? 0;
    if (q <= 0) continue;
    n += q * hargaJualTebus(item: it, semua: semua, qty: qty);
  }
  return n;
}

int modalDariQty(List<ItemNota> semua, Map<String, int> qty) {
  var n = 0;
  for (final it in semua) {
    final q = qty[it.idBarang] ?? 0;
    if (q <= 0) continue;
    n += q * it.hargaBeli;
  }
  return n;
}
