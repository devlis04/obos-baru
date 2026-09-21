class RingkasRute {
  const RingkasRute({
    required this.rute,
    required this.namaSales,
    required this.jumlahNota,
    required this.sudahSiap,
    required this.omsetOrder,
    required this.omsetPacked,
    required this.omsetActual,
    required this.labaOrder,
    required this.labaPacked,
    required this.labaActual,
  });

  final String rute;
  final String namaSales;
  final int jumlahNota;
  final int sudahSiap;
  final int omsetOrder;
  final int omsetPacked;
  final int omsetActual;
  final int labaOrder;
  final int labaPacked;
  final int labaActual;

  factory RingkasRute.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return RingkasRute(
      rute: json['rute']?.toString() ?? '',
      namaSales: json['nama_sales']?.toString() ?? '',
      jumlahNota: n(json['jumlah_nota']),
      sudahSiap: n(json['sudah_siap']),
      omsetOrder: n(json['omset_order']),
      omsetPacked: n(json['omset_packed']),
      omsetActual: n(json['omset_actual']),
      labaOrder: n(json['laba_order']),
      labaPacked: n(json['laba_packed']),
      labaActual: n(json['laba_actual']),
    );
  }
}
