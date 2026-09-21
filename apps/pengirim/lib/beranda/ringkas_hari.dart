import 'kartu_toko.dart';

class RingkasHari {
  const RingkasHari({
    required this.jumlahToko,
    required this.jumlahNota,
    required this.wajibKunci,
    required this.omsetOrder,
    required this.omsetPacked,
    required this.omsetActual,
    required this.omsetBatal,
    required this.omsetPending,
    required this.omsetRetur,
    this.labaOrder,
    this.labaPacked,
    this.labaActual,
  });

  final int jumlahToko;
  final int jumlahNota;
  final int wajibKunci;
  final int omsetOrder;
  final int omsetPacked;
  final int omsetActual;
  final int omsetBatal;
  final int omsetPending;
  final int omsetRetur;
  final int? labaOrder;
  final int? labaPacked;
  final int? labaActual;

  int get actualTampil {
    final s = omsetActual - omsetRetur;
    return s > 0 ? s : 0;
  }

  factory RingkasHari.dariKartu(List<KartuToko> toko) {
    return RingkasHari(
      jumlahToko: toko.length,
      jumlahNota: toko.fold(0, (n, t) => n + t.jumlahNota),
      wajibKunci: toko.fold(0, (n, t) => n + t.wajibKunci),
      omsetOrder: toko.fold(0, (n, t) => n + t.omsetOrder),
      omsetPacked: toko.fold(0, (n, t) => n + t.omsetPacked),
      omsetActual: toko.fold(0, (n, t) => n + t.omsetActual),
      omsetBatal: toko.fold(0, (n, t) => n + t.omsetBatal),
      omsetPending: 0,
      omsetRetur: toko.fold(0, (n, t) => n + t.omsetRetur),
    );
  }

  factory RingkasHari.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    int? nNull(dynamic v) {
      if (v == null) return null;
      return n(v);
    }

    return RingkasHari(
      jumlahToko: n(json['jumlah_toko']),
      jumlahNota: n(json['jumlah_nota']),
      wajibKunci: n(json['wajib_kunci']),
      omsetOrder: n(json['omset_order']),
      omsetPacked: n(json['omset_packed']),
      omsetActual: n(json['omset_actual']),
      omsetBatal: n(json['omset_batal']),
      omsetPending: n(json['omset_pending']),
      omsetRetur: n(json['omset_retur']),
      labaOrder: nNull(json['laba_order']),
      labaPacked: nNull(json['laba_packed']),
      labaActual: nNull(json['laba_actual']),
    );
  }
}
