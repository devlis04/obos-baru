class BarisNota {
  const BarisNota({
    required this.idBarang,
    required this.nama,
    this.idGrup = '',
    required this.qtyOrder,
    required this.hargaJualOrder,
    required this.hargaBeliOrder,
    this.hargaJual = 0,
    this.qtyPacked,
    this.hargaJualPacked,
    this.hargaBeliPacked,
    this.qtyActual,
    this.hargaJualActual,
    this.hargaBeliActual,
    this.subtotalOrder,
    this.subtotalBeliOrder,
    this.subtotalPacked,
    this.subtotalActual,
    this.minStrat1 = 0,
    this.jualStrat1 = 0,
    this.minStrat2 = 0,
    this.jualStrat2 = 0,
    this.minStrat3 = 0,
    this.jualStrat3 = 0,
    this.minStrat4 = 0,
    this.jualStrat4 = 0,
    this.minStrat5 = 0,
    this.jualStrat5 = 0,
  });

  final String idBarang;
  final String nama;
  final String idGrup;
  final int qtyOrder;
  final int hargaJualOrder;
  final int hargaBeliOrder;
  final int hargaJual;
  final int? qtyPacked;
  final int? hargaJualPacked;
  final int? hargaBeliPacked;
  final int? qtyActual;
  final int? hargaJualActual;
  final int? hargaBeliActual;
  final int? subtotalOrder;
  final int? subtotalBeliOrder;
  final int? subtotalPacked;
  final int? subtotalActual;
  final int minStrat1;
  final int jualStrat1;
  final int minStrat2;
  final int jualStrat2;
  final int minStrat3;
  final int jualStrat3;
  final int minStrat4;
  final int jualStrat4;
  final int minStrat5;
  final int jualStrat5;

  String get kunciGrup {
    final g = idGrup.trim();
    return g.isEmpty ? idBarang : g;
  }

  int hargaDariQty(int qtyGrup) {
    var harga = hargaJual > 0 ? hargaJual : hargaJualOrder;
    var maxMin = 0;
    void cek(int min, int jual) {
      if (min > 0 && jual > 0 && qtyGrup >= min && min > maxMin) {
        maxMin = min;
        harga = jual;
      }
    }

    cek(minStrat1, jualStrat1);
    cek(minStrat2, jualStrat2);
    cek(minStrat3, jualStrat3);
    cek(minStrat4, jualStrat4);
    cek(minStrat5, jualStrat5);
    return harga;
  }

  int get omsetOrder => subtotalOrder ?? (qtyOrder * hargaJualOrder);
  int get modalOrder => subtotalBeliOrder ?? (qtyOrder * hargaBeliOrder);

  int get omsetPacked {
    if (qtyPacked == null) return 0;
    return subtotalPacked ?? (qtyPacked! * (hargaJualPacked ?? 0));
  }

  int get modalPacked {
    if (qtyPacked == null) return 0;
    return qtyPacked! * (hargaBeliPacked ?? 0);
  }

  int get omsetActual {
    if (qtyActual == null) return 0;
    return subtotalActual ?? (qtyActual! * (hargaJualActual ?? 0));
  }

  int get modalActual {
    if (qtyActual == null) return 0;
    return qtyActual! * (hargaBeliActual ?? 0);
  }

  factory BarisNota.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    int? nNull(dynamic v) => v == null ? null : n(v);
    return BarisNota(
      idBarang: json['id_barang']?.toString() ?? '',
      nama: json['nama_barang']?.toString() ?? '',
      idGrup: json['id_grup']?.toString() ?? '',
      qtyOrder: n(json['qty_order'] ?? json['qty']),
      hargaJual: n(json['harga_jual']),
      hargaJualOrder: n(json['harga_jual_order'] ?? json['harga_jual']),
      hargaBeliOrder: n(json['harga_beli'] ?? json['harga_beli_order']),
      qtyPacked: nNull(json['qty_packed']),
      hargaJualPacked: nNull(json['harga_jual_packed']),
      hargaBeliPacked: nNull(json['harga_beli_packed']) ??
          (json['qty_packed'] == null
              ? null
              : n(json['harga_beli'] ?? json['harga_beli_order'])),
      qtyActual: nNull(json['qty_actual']),
      hargaJualActual: nNull(json['harga_jual_actual']),
      hargaBeliActual: nNull(json['harga_beli_actual']) ??
          (json['qty_actual'] == null
              ? null
              : n(json['harga_beli'] ?? json['harga_beli_order'])),
      subtotalOrder: nNull(json['subtotal_jual_order'] ?? json['subtotal_order']),
      subtotalBeliOrder: nNull(json['subtotal_beli_order']),
      subtotalPacked: nNull(json['subtotal_jual_packed'] ?? json['subtotal_packed']),
      subtotalActual: nNull(json['subtotal_jual_actual'] ?? json['subtotal_actual']),
      minStrat1: n(json['min_strat_1']),
      jualStrat1: n(json['jual_strat_1']),
      minStrat2: n(json['min_strat_2']),
      jualStrat2: n(json['jual_strat_2']),
      minStrat3: n(json['min_strat_3']),
      jualStrat3: n(json['jual_strat_3']),
      minStrat4: n(json['min_strat_4']),
      jualStrat4: n(json['jual_strat_4']),
      minStrat5: n(json['min_strat_5']),
      jualStrat5: n(json['jual_strat_5']),
    );
  }

  static List<BarisNota> isiHargaStrata(List<BarisNota> items) {
    final qtyOrderGrup = <String, int>{};
    final qtyPackedGrup = <String, int>{};
    final qtyActualGrup = <String, int>{};
    for (final it in items) {
      final k = it.kunciGrup;
      qtyOrderGrup[k] = (qtyOrderGrup[k] ?? 0) + it.qtyOrder;
      if (it.qtyPacked != null) {
        qtyPackedGrup[k] = (qtyPackedGrup[k] ?? 0) + it.qtyPacked!;
      }
      if (it.qtyActual != null) {
        qtyActualGrup[k] = (qtyActualGrup[k] ?? 0) + it.qtyActual!;
      }
    }
    return [
      for (final it in items)
        BarisNota(
          idBarang: it.idBarang,
          nama: it.nama,
          idGrup: it.idGrup,
          qtyOrder: it.qtyOrder,
          hargaJual: it.hargaJual,
          hargaJualOrder: it.hargaDariQty(qtyOrderGrup[it.kunciGrup] ?? 0),
          hargaBeliOrder: it.hargaBeliOrder,
          qtyPacked: it.qtyPacked,
          hargaJualPacked: it.qtyPacked == null
              ? null
              : it.hargaDariQty(qtyPackedGrup[it.kunciGrup] ?? 0),
          hargaBeliPacked: it.hargaBeliPacked,
          qtyActual: it.qtyActual,
          hargaJualActual: it.qtyActual == null
              ? null
              : it.hargaDariQty(qtyActualGrup[it.kunciGrup] ?? 0),
          hargaBeliActual: it.hargaBeliActual,
          subtotalOrder: it.qtyOrder *
              it.hargaDariQty(qtyOrderGrup[it.kunciGrup] ?? 0),
          subtotalBeliOrder: it.subtotalBeliOrder,
          subtotalPacked: it.qtyPacked == null
              ? null
              : it.qtyPacked! *
                  it.hargaDariQty(qtyPackedGrup[it.kunciGrup] ?? 0),
          subtotalActual: it.qtyActual == null
              ? null
              : it.qtyActual! *
                  it.hargaDariQty(qtyActualGrup[it.kunciGrup] ?? 0),
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
        ),
    ];
  }
}

class Nota {
  const Nota({
    required this.id,
    required this.idPelanggan,
    required this.namaPelanggan,
    required this.rute,
    required this.status,
    required this.pending,
    required this.items,
    this.waktuOrder,
    this.waktuPacked,
    this.waktuActual,
    this.lokal = false,
  });

  final String id;
  final String idPelanggan;
  final String namaPelanggan;
  final String rute;
  final String status;
  final bool pending;
  final DateTime? waktuOrder;
  final DateTime? waktuPacked;
  final DateTime? waktuActual;
  final List<BarisNota> items;
  final bool lokal;

  bool get bisaDiubah => status == 'diproses' && waktuPacked == null;

  bool get batalSales => status == 'batal' && waktuPacked == null;

  bool get batalGudang {
    if (status != 'batal' || waktuPacked == null) return false;
    return !items.any((i) => (i.qtyPacked ?? 0) > 0);
  }

  bool get batalPengirim {
    if (status != 'batal' || waktuPacked == null) return false;
    return items.any((i) => (i.qtyPacked ?? 0) > 0);
  }

  bool get punyaPacked =>
      waktuPacked != null || items.any((i) => i.qtyPacked != null);

  bool get punyaActual =>
      waktuActual != null || items.any((i) => i.qtyActual != null);

  bool get pendingKirim => pending && status == 'dikirim';

  bool get tampilPacked => punyaPacked;

  bool get tampilActual => punyaPacked;

  int get totalOrder => items.fold(0, (s, i) => s + i.omsetOrder);
  int get modalOrder => items.fold(0, (s, i) => s + i.modalOrder);
  int get totalPacked => items.fold(0, (s, i) => s + i.omsetPacked);
  int get modalPacked => items.fold(0, (s, i) => s + i.modalPacked);
  int get totalActual => items.fold(0, (s, i) => s + i.omsetActual);
  int get modalActual => items.fold(0, (s, i) => s + i.modalActual);

  int get nilaiBatal {
    if (!punyaPacked || !punyaActual) return 0;
    final n = totalPacked - totalActual;
    return n > 0 ? n : 0;
  }

  String get labelStatus {
    if (status == 'batal') return 'Batal';
    if (status == 'terkirim') return 'Terkirim';
    if (status == 'dikirim' || punyaPacked) return 'Sedang dikirim';
    return 'Sedang diproses';
  }

  Map<String, int> get keranjang {
    final map = <String, int>{};
    for (final i in items) {
      if (i.idBarang.isEmpty || i.qtyOrder <= 0) continue;
      map[i.idBarang] = i.qtyOrder;
    }
    return map;
  }

  static DateTime? parseWaktu(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  static String teksWaktu(DateTime? w) {
    if (w == null) return '';
    final lokal = w.isUtc ? w.toLocal() : w;
    final m = lokal.month.toString().padLeft(2, '0');
    final d = lokal.day.toString().padLeft(2, '0');
    final h = lokal.hour.toString().padLeft(2, '0');
    final min = lokal.minute.toString().padLeft(2, '0');
    return '$d/$m/${lokal.year} $h:$min';
  }

  factory Nota.fromJson(Map<String, dynamic> json) {
    final raw = json['transaksi_items'] ?? json['items'];
    final items = <BarisNota>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(BarisNota.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return Nota(
      id: json['id_transaksi']?.toString() ?? '',
      idPelanggan: json['id_pelanggan']?.toString() ?? '',
      namaPelanggan: (json['nama_pelanggan']?.toString() ?? '').toUpperCase(),
      rute: json['rute']?.toString() ?? '',
      status: json['status']?.toString() ?? 'diproses',
      pending: json['pending'] == true,
      waktuOrder: parseWaktu(json['waktu_order']),
      waktuPacked: parseWaktu(json['waktu_packed']),
      waktuActual: parseWaktu(json['waktu_actual']),
      items: BarisNota.isiHargaStrata(items),
    );
  }
}

class PotensiToko {
  const PotensiToko({
    required this.rataOrder,
    required this.rasio,
    required this.ada,
  });

  final int rataOrder;
  final double? rasio;
  final bool ada;

  static const kosong = PotensiToko(rataOrder: 0, rasio: null, ada: false);

  static PotensiToko dari(List<Nota> nota) {
    var bayar = 0;
    var laba = 0;
    var modal = 0;
    var jumlah = 0;
    for (final n in nota) {
      if (n.status == 'batal') continue;
      if (!n.punyaActual) continue;
      if (n.totalActual <= 0) continue;
      jumlah += 1;
      bayar += n.totalActual;
      modal += n.modalActual;
      laba += n.totalActual - n.modalActual;
    }
    if (jumlah == 0) return kosong;
    return PotensiToko(
      rataOrder: (bayar / 10).round(),
      rasio: modal > 0 ? (laba / modal) * 100 : null,
      ada: true,
    );
  }
}
