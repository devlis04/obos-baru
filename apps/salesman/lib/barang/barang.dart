class BarangStrata {
  const BarangStrata({required this.minimal, required this.jual});
  final int minimal;
  final int jual;
}

class Barang {
  const Barang({
    required this.id,
    required this.idGrup,
    required this.nama,
    required this.kategori,
    required this.stok,
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
  });

  final String id;
  final String idGrup;
  final String nama;
  final String kategori;
  final num stok;
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

  List<BarangStrata> get strataAktif {
    final strata = <BarangStrata>[];
    void add(int min, int jual) {
      if (min > 0 && jual > 0) {
        strata.add(BarangStrata(minimal: min, jual: jual));
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

  Map<String, dynamic> toJson() => {
        'id_barang': id,
        'id_grup': idGrup,
        'nama_barang': nama,
        'kategori': kategori,
        'stok': stok,
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
    );
  }
}
