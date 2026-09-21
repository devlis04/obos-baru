import '../barang/barang.dart';
import '../uang.dart';

class TransaksiHelper {
  static int qtyGrup({
    required Barang barang,
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    final grup = barang.idGrup.trim();
    if (grup.isEmpty) return keranjang[barang.id] ?? 0;
    var total = 0;
    keranjang.forEach((id, qty) {
      if (qty <= 0) return;
      for (final item in daftar) {
        if (item.id == id && item.idGrup == barang.idGrup) {
          total += qty;
          break;
        }
      }
    });
    return total;
  }

  static int hargaDariQtyGrup({
    required Barang barang,
    required int totalQtyGrup,
  }) {
    var harga = barang.hargaJual;
    var maxMin = 0;
    for (final strata in barang.strataAktif) {
      if (totalQtyGrup >= strata.minimal && strata.minimal > maxMin) {
        maxMin = strata.minimal;
        harga = strata.jual;
      }
    }
    return harga;
  }

  static int hargaJual({
    required Barang barang,
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    return hargaDariQtyGrup(
      barang: barang,
      totalQtyGrup: qtyGrup(barang: barang, keranjang: keranjang, daftar: daftar),
    );
  }

  static int totalNota({
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    var total = 0;
    keranjang.forEach((id, qty) {
      if (qty <= 0) return;
      for (final item in daftar) {
        if (item.id == id) {
          total += hargaJual(barang: item, keranjang: keranjang, daftar: daftar) * qty;
          break;
        }
      }
    });
    return total;
  }

  static int totalModal({
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    var total = 0;
    keranjang.forEach((id, qty) {
      if (qty <= 0) return;
      for (final item in daftar) {
        if (item.id == id) {
          total += item.hargaBeli * qty;
          break;
        }
      }
    });
    return total;
  }

  static String rasioKeranjang({
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    final modal = totalModal(keranjang: keranjang, daftar: daftar);
    if (modal <= 0) return '-';
    final omset = totalNota(keranjang: keranjang, daftar: daftar);
    return '${(((omset - modal) / modal) * 100).toStringAsFixed(1)}%';
  }

  static String rasioItem({required int hargaJual, required int hargaBeli}) {
    if (hargaBeli <= 0) return '-';
    return '${(((hargaJual - hargaBeli) / hargaBeli) * 100).toStringAsFixed(1)}%';
  }

  static String rasioOmset({required int omset, required int modal}) {
    if (modal <= 0) return '-';
    return '${(((omset - modal) / modal) * 100).toStringAsFixed(1)}%';
  }

  static String rp(int nominal) => Uang.rp(nominal);
}
