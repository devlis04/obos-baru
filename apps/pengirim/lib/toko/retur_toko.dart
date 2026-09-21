class BarisReturToko {
  const BarisReturToko({
    required this.kode,
    required this.nama,
    required this.qty,
    required this.harga,
    required this.nilai,
    required this.dikunci,
  });

  final String kode;
  final String nama;
  final int qty;
  final int harga;
  final int nilai;
  final bool dikunci;

  factory BarisReturToko.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return BarisReturToko(
      kode: json['kode_barang']?.toString() ?? '',
      nama: json['nama_barang']?.toString() ?? '',
      qty: n(json['qty']),
      harga: n(json['harga_jual']),
      nilai: n(json['nilai']),
      dikunci: json['dikunci'] == true,
    );
  }
}

class SaranBarang {
  const SaranBarang({
    required this.kode,
    required this.nama,
    required this.harga,
  });

  final String kode;
  final String nama;
  final int harga;
}

class BarisReturRute {
  const BarisReturRute({
    required this.idPelanggan,
    required this.namaToko,
    required this.kode,
    required this.nama,
    required this.qty,
    required this.nilai,
  });

  final String idPelanggan;
  final String namaToko;
  final String kode;
  final String nama;
  final int qty;
  final int nilai;

  factory BarisReturRute.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return BarisReturRute(
      idPelanggan: json['id_pelanggan']?.toString() ?? '',
      namaToko: json['nama_toko']?.toString() ?? '',
      kode: json['kode_barang']?.toString() ?? '',
      nama: json['nama_barang']?.toString() ?? '',
      qty: n(json['qty']),
      nilai: n(json['nilai']),
    );
  }
}

