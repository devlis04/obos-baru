import '../barang/barang.dart';
import '../uang.dart';
import 'nota_repo.dart';

class TransaksiHelper {
  static int qtyGrup({
    required Barang barang,
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    final kunci = _kunciGrup(barang);
    var total = 0;
    keranjang.forEach((id, qty) {
      if (qty <= 0) return;
      for (final item in daftar) {
        if (item.id == id && _kunciGrup(item) == kunci) {
          total += qty;
          break;
        }
      }
    });
    return total;
  }

  static String _kunciGrup(Barang barang) {
    final grup = barang.idGrup.trim();
    return grup.isEmpty ? barang.id : grup;
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

  static Barang pakaiKunciNota(Barang dasar, ItemNota it) {
    return dasar.kunciNota(
      idGrup: it.idGrupKunci.trim().isNotEmpty ? it.idGrupKunci : dasar.idGrup,
      hargaJual: it.hargaDasarKunci > 0 ? it.hargaDasarKunci : dasar.hargaJual,
      minStrat1: it.minStrat1,
      jualStrat1: it.jualStrat1,
      minStrat2: it.minStrat2,
      jualStrat2: it.jualStrat2,
      minStrat3: it.minStrat3,
      jualStrat3: it.jualStrat3,
      minStrat4: it.minStrat4,
      jualStrat4: it.jualStrat4,
      minStrat5: it.minStrat5,
      jualStrat5: it.jualStrat5,
    );
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

  static num maksPack({
    required num sisaBuku,
    required int qtyTersimpan,
  }) {
    final batas = sisaBuku + qtyTersimpan;
    return batas > qtyTersimpan ? batas : qtyTersimpan;
  }

  static num sisaTampil({
    required num sisaBuku,
    required int qtyTersimpan,
    required int qtyKeranjang,
  }) {
    return sisaBuku + qtyTersimpan - qtyKeranjang;
  }
}
