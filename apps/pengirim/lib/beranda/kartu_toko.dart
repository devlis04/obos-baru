class KartuToko {
  const KartuToko({
    required this.idPelanggan,
    required this.namaPelanggan,
    required this.ruteSales,
    this.latitude,
    this.longitude,
    required this.jumlahNota,
    required this.omsetOrder,
    required this.omsetPacked,
    required this.omsetActual,
    required this.omsetBatal,
    this.omsetRetur = 0,
    required this.wajibKunci,
    required this.adaDikirim,
    required this.adaPending,
    required this.adaBatal,
    required this.adaTerkirim,
    this.waktuMasuk,
    this.waktuKeluar,
  });

  final String idPelanggan;
  final String namaPelanggan;
  final String ruteSales;
  final double? latitude;
  final double? longitude;
  final int jumlahNota;
  final int omsetOrder;
  final int omsetPacked;
  final int omsetActual;
  final int omsetBatal;
  final int omsetRetur;
  final int wajibKunci;
  final bool adaDikirim;
  final bool adaPending;
  final bool adaBatal;
  final bool adaTerkirim;
  final DateTime? waktuMasuk;
  final DateTime? waktuKeluar;

  String get nama => namaPelanggan;

  bool get scanKeluar => waktuMasuk != null && waktuKeluar == null;

  bool get sudahDikunjungi => waktuKeluar != null;

  String get labelStatus {
    if (adaDikirim) return 'Sedang dikirim';
    if (adaTerkirim) return 'Terkirim';
    if (adaBatal && !adaPending) return 'Batal';
    if (adaPending) return 'Pending';
    return 'Sedang dikirim';
  }

  factory KartuToko.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    double? d(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    DateTime? t(dynamic v) {
      final raw = v?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }

    return KartuToko(
      idPelanggan: json['id_pelanggan']?.toString() ?? '',
      namaPelanggan: json['nama_pelanggan']?.toString() ?? '',
      ruteSales: json['rute_sales']?.toString() ?? '',
      latitude: d(json['latitude']),
      longitude: d(json['longitude']),
      jumlahNota: n(json['jumlah_nota']),
      omsetOrder: n(json['omset_order']),
      omsetPacked: n(json['omset_packed']),
      omsetActual: n(json['omset_actual']),
      omsetBatal: n(json['omset_batal']),
      omsetRetur: n(json['omset_retur']),
      wajibKunci: n(json['wajib_kunci']),
      adaDikirim: json['ada_dikirim'] == true,
      adaPending: json['ada_pending'] == true,
      adaBatal: json['ada_batal'] == true,
      adaTerkirim: json['ada_terkirim'] == true,
      waktuMasuk: t(json['waktu_masuk']),
      waktuKeluar: t(json['waktu_keluar']),
    );
  }
}

class RingkasNota {
  const RingkasNota({
    required this.idTransaksi,
    required this.status,
    required this.pending,
    this.waktuOrder,
    this.waktuPacked,
    this.waktuActual,
    required this.omsetOrder,
    required this.omsetPacked,
    required this.omsetActual,
    this.labaOrder,
    this.labaPacked,
    this.labaActual,
  });

  final String idTransaksi;
  final String status;
  final bool pending;
  final DateTime? waktuOrder;
  final DateTime? waktuPacked;
  final DateTime? waktuActual;
  final int omsetOrder;
  final int omsetPacked;
  final int omsetActual;
  final int? labaOrder;
  final int? labaPacked;
  final int? labaActual;

  bool get bisaPending => status == 'dikirim' && !pending;

  bool get sudahPack => waktuPacked != null || status == 'dikirim';

  RingkasNota salinDikirim() {
    return RingkasNota(
      idTransaksi: idTransaksi,
      status: 'dikirim',
      pending: false,
      waktuOrder: waktuOrder,
      waktuPacked: waktuPacked,
      waktuActual: null,
      omsetOrder: omsetOrder,
      omsetPacked: omsetPacked,
      omsetActual: 0,
      labaOrder: labaOrder,
      labaPacked: labaPacked,
      labaActual: 0,
    );
  }

  String get labelStatus {
    if (status == 'batal') return 'Batal';
    if (status == 'terkirim') return 'Terkirim';
    if (status == 'dikirim') return 'Sedang dikirim';
    return status;
  }

  factory RingkasNota.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    int? nNull(dynamic v) {
      if (v == null) return null;
      return n(v);
    }

    DateTime? t(dynamic v) {
      final raw = v?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }

    return RingkasNota(
      idTransaksi: json['id_transaksi']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      pending: json['pending'] == true,
      waktuOrder: t(json['waktu_order']),
      waktuPacked: t(json['waktu_packed']),
      waktuActual: t(json['waktu_actual']),
      omsetOrder: n(json['omset_order']),
      omsetPacked: n(json['omset_packed']),
      omsetActual: n(json['omset_actual']),
      labaOrder: nNull(json['laba_order']),
      labaPacked: nNull(json['laba_packed']),
      labaActual: nNull(json['laba_actual']),
    );
  }
}

class ItemNota {
  const ItemNota({
    required this.idBarang,
    required this.nama,
    required this.idGrup,
    required this.qtyOrder,
    required this.qtyPacked,
    this.qtyActual,
    this.hargaJual = 0,
    this.hargaBeli = 0,
    required this.hargaJualOrder,
    required this.hargaJualPacked,
    this.hargaJualActual,
    required this.subtotalOrder,
    required     this.subtotalPacked,
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
  final int qtyPacked;
  final int? qtyActual;
  final int hargaJual;
  final int hargaBeli;
  final int hargaJualOrder;
  final int hargaJualPacked;
  final int? hargaJualActual;
  final int subtotalOrder;
  final int subtotalPacked;
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

  List<({int minimal, int jual})> get strataAktif {
    final strata = <({int minimal, int jual})>[];
    void add(int min, int jual) {
      if (min > 0 && jual > 0) {
        strata.add((minimal: min, jual: jual));
      }
    }

    add(minStrat1, jualStrat1);
    add(minStrat2, jualStrat2);
    add(minStrat3, jualStrat3);
    add(minStrat4, jualStrat4);
    add(minStrat5, jualStrat5);
    strata.sort((a, b) => a.minimal.compareTo(b.minimal));
    return strata;
  }

  factory ItemNota.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    int? nNull(dynamic v) {
      if (v == null) return null;
      return n(v);
    }

    return ItemNota(
      idBarang: json['id_barang']?.toString() ?? '',
      nama: json['nama_barang']?.toString() ?? '',
      idGrup: json['id_grup']?.toString() ?? '',
      qtyOrder: n(json['qty_order']),
      qtyPacked: n(json['qty_packed']),
      qtyActual: nNull(json['qty_actual']),
      hargaJual: n(json['harga_jual']),
      hargaBeli: n(json['harga_beli']),
      hargaJualOrder: n(json['harga_jual_order']),
      hargaJualPacked: n(json['harga_jual_packed']),
      hargaJualActual: nNull(json['harga_jual_actual']),
      subtotalOrder: n(json['subtotal_order']),
      subtotalPacked: n(json['subtotal_packed']),
      subtotalActual: nNull(json['subtotal_actual']),
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
}
