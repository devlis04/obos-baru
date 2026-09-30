class SetoranPengirim {
  const SetoranPengirim({
    required this.transfer,
    required this.tunai,
    required this.bop,
    required this.kasbonSupir,
    required this.kasbonKenek,
    required this.sudahAda,
    required this.bisaUbah,
    this.dicatatOleh = '',
    this.dicatatRute = '',
    this.bopMaks = 170000,
  });

  static const kosong = SetoranPengirim(
    transfer: 0,
    tunai: 0,
    bop: 0,
    kasbonSupir: 0,
    kasbonKenek: 0,
    sudahAda: false,
    bisaUbah: false,
  );

  final int transfer;
  final int tunai;
  final int bop;
  final int kasbonSupir;
  final int kasbonKenek;
  final bool sudahAda;
  final bool bisaUbah;
  final String dicatatOleh;
  final String dicatatRute;
  final int bopMaks;

  factory SetoranPengirim.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    bool b(dynamic v) => v == true;

    return SetoranPengirim(
      transfer: n(json['jumlah_transfer']),
      tunai: n(json['jumlah_tunai']),
      bop: n(json['jumlah_bop']),
      kasbonSupir: n(json['kasbon_supir']),
      kasbonKenek: n(json['kasbon_kenek']),
      sudahAda: b(json['sudah_ada']),
      bisaUbah: b(json['bisa_ubah']),
      dicatatOleh: json['dicatat_oleh']?.toString().trim() ?? '',
      dicatatRute: json['dicatat_rute']?.toString().trim() ?? '',
      bopMaks: json.containsKey('bop_maks') ? n(json['bop_maks']) : 170000,
    );
  }
}
