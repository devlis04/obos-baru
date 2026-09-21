class Barang {
  const Barang({
    required this.id,
    required this.idGrup,
    required this.nama,
    required this.kategori,
    required this.stok,
    this.sisaBuku,
    required this.hargaBeli,
    required this.hargaJual,
    required this.minStrat1,
    required this.jualStrat1,
    required this.minStrat2,
    required this.jualStrat2,
    required this.minStrat3,
    required this.jualStrat3,
    required this.minStrat4,
    required this.jualStrat4,
    required this.minStrat5,
    required this.jualStrat5,
    required this.pengurangStrata,
    required this.aktif,
    this.idSupplierUtama = 0,
  });

  final String id;
  final String idGrup;
  final String nama;
  final String kategori;
  final num stok;
  final num? sisaBuku;
  num get sisaGudang => sisaBuku ?? stok;
  final int hargaBeli;
  final int hargaJual;
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
  final int pengurangStrata;
  final bool aktif;
  final int idSupplierUtama;

  bool samaIsi(Barang o) =>
      id == o.id &&
      idGrup == o.idGrup &&
      nama == o.nama &&
      kategori == o.kategori &&
      stok == o.stok &&
      sisaBuku == o.sisaBuku &&
      hargaBeli == o.hargaBeli &&
      hargaJual == o.hargaJual &&
      minStrat1 == o.minStrat1 &&
      minStrat2 == o.minStrat2 &&
      minStrat3 == o.minStrat3 &&
      minStrat4 == o.minStrat4 &&
      minStrat5 == o.minStrat5 &&
      pengurangStrata == o.pengurangStrata &&
      aktif == o.aktif &&
      idSupplierUtama == o.idSupplierUtama;

  static String gabungNama({
    required String nama,
    required String satuan,
    String rincian = '',
  }) {
    final n = nama.trim();
    final s = satuan.trim();
    final r = rincian.trim();
    if (s.isEmpty) return n;
    if (r.isEmpty) return '$n /$s';
    return '$n /$s/$r';
  }

  static ({String nama, String satuan, String rincian}) pecahNama(String mentah) {
    final t = mentah.trim();
    final i = t.indexOf(' /');
    if (i < 0) {
      return (nama: t, satuan: '', rincian: '');
    }
    final nama = t.substring(0, i).trim();
    final sisa = t.substring(i + 2);
    final slash = sisa.indexOf('/');
    if (slash < 0) {
      return (nama: nama, satuan: sisa.trim(), rincian: '');
    }
    return (
      nama: nama,
      satuan: sisa.substring(0, slash).trim(),
      rincian: sisa.substring(slash + 1).trim(),
    );
  }

  Map<String, dynamic> keSimpan() => {
        'id_barang': id,
        'id_grup': idGrup,
        'nama_barang': nama,
        'kategori': kategori,
        'harga_beli': hargaBeli,
        'harga_jual': hargaJual,
        'min_strat_1': minStrat1,
        'jual_strat_1': jualStrat1,
        'min_strat_2': minStrat2,
        'jual_strat_2': jualStrat2,
        'min_strat_3': minStrat3,
        'jual_strat_3': jualStrat3,
        'min_strat_4': minStrat4,
        'jual_strat_4': jualStrat4,
        'min_strat_5': minStrat5,
        'jual_strat_5': jualStrat5,
        'pengurang_strata': pengurangStrata,
        'aktif': aktif,
      };

  factory Barang.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;
    num q(dynamic v) {
      if (v is num) return v;
      return num.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
    }

    return Barang(
      id: json['id_barang']?.toString() ?? '',
      idGrup: json['id_grup']?.toString() ?? '',
      nama: json['nama_barang']?.toString() ?? '',
      kategori: json['kategori']?.toString() ?? '',
      stok: q(json['stok']),
      sisaBuku: json.containsKey('sisa_buku') ? q(json['sisa_buku']) : null,
      hargaBeli: n(json['harga_beli']),
      hargaJual: n(json['harga_jual']),
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
      pengurangStrata: n(json['pengurang_strata']),
      aktif: json['aktif'] != false,
      idSupplierUtama: n(json['id_supplier_utama']),
    );
  }
}
