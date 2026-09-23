import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../uang.dart';

int _n(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

class RingkasNota {
  const RingkasNota({
    required this.idTransaksi,
    required this.namaPelanggan,
    required this.status,
    required this.pending,
    required this.waktuOrder,
    required this.waktuPacked,
    required this.waktuActual,
    required this.omsetOrder,
    required this.omsetPacked,
    required this.omsetActual,
    required this.labaOrder,
    required this.labaPacked,
    required this.labaActual,
    this.extra = false,
  });

  final String idTransaksi;
  final String namaPelanggan;
  final String status;
  final bool pending;
  final DateTime? waktuOrder;
  final DateTime? waktuPacked;
  final DateTime? waktuActual;
  final int omsetOrder;
  final int omsetPacked;
  final int omsetActual;
  final int labaOrder;
  final int labaPacked;
  final int labaActual;
  final bool extra;

  factory RingkasNota.dari(Map<String, dynamic> r) {
    DateTime? w(dynamic v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return RingkasNota(
      idTransaksi: r['id_transaksi']?.toString() ?? '',
      namaPelanggan: r['nama_pelanggan']?.toString() ?? 'Toko',
      status: r['status']?.toString() ?? 'diproses',
      pending: r['pending'] == true,
      waktuOrder: w(r['waktu_order']),
      waktuPacked: w(r['waktu_packed']),
      waktuActual: w(r['waktu_actual']),
      omsetOrder: _n(r['omset_order']),
      omsetPacked: _n(r['omset_packed']),
      omsetActual: _n(r['omset_actual']),
      labaOrder: _n(r['laba_order']),
      labaPacked: _n(r['laba_packed']),
      labaActual: _n(r['laba_actual']),
      extra: r['extra'] == true,
    );
  }

  String get labelStatus {
    if (status == 'batal') return 'Batal';
    if (status == 'terkirim') return 'Terkirim';
    if (status == 'dikirim' || waktuPacked != null) return 'Sedang dikirim';
    return 'Sedang diproses';
  }

  bool get bisaPack =>
      status == 'diproses' || (status == 'dikirim' && waktuActual == null);

  bool get sudahPack => waktuPacked != null;

  bool _hariSama(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Sisa kiriman buku kemarin: sudah di truk, jangan packing ulang.
  bool sisaKirimanPada(DateTime tanggalBuku) {
    if (status != 'dikirim' || waktuActual != null) return false;
    final w = waktuOrder;
    if (w == null) return false;
    return !_hariSama(w.toLocal(), tanggalBuku);
  }

  bool bolehPackPada(DateTime tanggalBuku) {
    if (!bisaPack) return false;
    return !sisaKirimanPada(tanggalBuku);
  }
}

class ItemNota {
  ItemNota({
    required this.idBarang,
    required this.nama,
    required this.qtyOrder,
    required this.qtyPacked,
    required this.qtyActual,
    required this.hargaJualOrder,
    required this.hargaJualPacked,
    required this.subtotalOrder,
    required this.subtotalPacked,
    required this.subtotalActual,
    this.idGrupKunci = '',
    this.hargaJualKunci = 0,
    this.hargaBeli = 0,
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

  factory ItemNota.dari(Map<String, dynamic> r) {
    return ItemNota(
      idBarang: r['id_barang']?.toString() ?? '',
      nama: r['nama_barang']?.toString() ?? '',
      qtyOrder: _n(r['qty_order']),
      qtyPacked: r['qty_packed'] == null ? null : _n(r['qty_packed']),
      qtyActual: r['qty_actual'] == null ? null : _n(r['qty_actual']),
      hargaJualOrder: _n(r['harga_jual_order']),
      hargaJualPacked: r['harga_jual_packed'] == null
          ? null
          : _n(r['harga_jual_packed']),
      subtotalOrder: _n(r['subtotal_order']),
      subtotalPacked: r['subtotal_packed'] == null
          ? null
          : _n(r['subtotal_packed']),
      subtotalActual: r['subtotal_actual'] == null
          ? null
          : _n(r['subtotal_actual']),
      idGrupKunci: r['id_grup_kunci']?.toString() ?? '',
      hargaJualKunci: _n(r['harga_jual_kunci']),
      hargaBeli: _n(r['harga_beli_order'] ?? r['harga_beli']),
      minStrat1: _n(r['min_strat_1']),
      jualStrat1: _n(r['jual_strat_1']),
      minStrat2: _n(r['min_strat_2']),
      jualStrat2: _n(r['jual_strat_2']),
      minStrat3: _n(r['min_strat_3']),
      jualStrat3: _n(r['jual_strat_3']),
      minStrat4: _n(r['min_strat_4']),
      jualStrat4: _n(r['jual_strat_4']),
      minStrat5: _n(r['min_strat_5']),
      jualStrat5: _n(r['jual_strat_5']),
    );
  }

  final String idBarang;
  final String nama;
  final int qtyOrder;
  final int? qtyPacked;
  final int? qtyActual;
  final int hargaJualOrder;
  final int? hargaJualPacked;
  final int subtotalOrder;
  final int? subtotalPacked;
  final int? subtotalActual;
  final String idGrupKunci;
  final int hargaJualKunci;
  final int hargaBeli;
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

  int get hargaDasarKunci =>
      hargaJualKunci > 0 ? hargaJualKunci : hargaJualOrder;
}

class NotaRepo {
  NotaRepo(this._sb);
  final SupabaseClient _sb;

  Future<List<RingkasNota>> rute(DateTime tanggal, String rute) async {
    final hasil = await _sb
        .rpc(
          'gudang_nota_rute',
          params: {
            'p_tanggal': Uang.isoHari(tanggal),
            'p_rute': rute,
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => RingkasNota.dari(Map<String, dynamic>.from(e)))
        .where((n) => !(n.status == 'batal' && n.waktuPacked == null))
        .toList();
  }

  Future<List<ItemNota>> item(String idTransaksi) async {
    final hasil = await _sb
        .rpc('gudang_nota_item', params: {'p_id_transaksi': idTransaksi})
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => ItemNota.dari(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> pack(String idTransaksi, List<Map<String, dynamic>> baris) {
    return Jaringan.denganUlang(
      () => _sb
          .rpc(
            'gudang_pack_nota',
            params: {'p_id_transaksi': idTransaksi, 'p_baris': baris},
          )
          .timeout(Jaringan.lambat),
    );
  }
}
