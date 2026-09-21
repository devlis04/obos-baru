import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../rumus_sederhana.dart';

num _n(dynamic v) {
  if (v is num) return v;
  return num.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

class BarisBuku {
  BarisBuku({
    required this.idBarang,
    required this.nama,
    required this.stokAwal,
    required this.qtyPacked,
    required this.stokHitung,
    this.stokFisik,
    this.jumlahBagian = 1,
  }) : fisikCtrl = TextEditingController(
         text: stokFisik == null ? '' : teksQty(stokFisik),
       );

  factory BarisBuku.dari(Map<String, dynamic> r) {
    return BarisBuku(
      idBarang: r['id_barang']?.toString() ?? '',
      nama: r['nama_barang']?.toString() ?? '',
      stokAwal: _n(r['stok_awal']),
      qtyPacked: _n(r['qty_packed']),
      stokHitung: _n(r['stok_hitung']),
      stokFisik: r['stok_fisik'] == null ? null : _n(r['stok_fisik']),
      jumlahBagian: _i(r['jumlah_bagian']),
    );
  }

  final String idBarang;
  String nama;
  num stokAwal;
  num qtyPacked;
  num stokHitung;
  num? stokFisik;
  int jumlahBagian;
  bool kotor = false;
  final TextEditingController fisikCtrl;

  void ikutiBuku(BarisBuku s) {
    nama = s.nama;
    stokAwal = s.stokAwal;
    qtyPacked = s.qtyPacked;
    stokHitung = s.stokHitung;
    jumlahBagian = s.jumlahBagian;
    stokFisik = s.stokFisik;
    if (s.stokFisik == null) return;
    if (!kotor || !fisikTerisi) {
      fisikCtrl.text = teksQty(s.stokFisik!);
      kotor = false;
    }
  }

  bool get fisikTerisi => fisikCtrl.text.trim().isNotEmpty;

  num? get fisikAngka => nilaiDariRumus(fisikCtrl.text);

  bool get perluKirim {
    if (!fisikTerisi) return false;
    final n = fisikAngka;
    if (n == null) return false;
    if (stokFisik == null) return true;
    if (!kotor) return false;
    return (n - stokFisik!).abs() >= 0.00005;
  }

  bool get terhitungTerisi => fisikTerisi || stokFisik != null;

  num get selisihTampil {
    final f = fisikAngka;
    if (f == null) return 0;
    return f - stokHitung;
  }

  Map<String, dynamic> keKirim() => {
    'id_barang': idBarang,
    'stok_fisik': fisikAngka ?? 0,
  };

  void dispose() => fisikCtrl.dispose();
}

class BukuRepo {
  BukuRepo(this._sb);
  final SupabaseClient _sb;

  Future<List<BarisBuku>> isi() async {
    final hasil = await _sb.rpc('gudang_buku_isi').timeout(const Duration(seconds: 30));
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => BarisBuku.dari(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<HasilSimpanOpname> simpanOpname(List<Map<String, dynamic>> baris) async {
    final hasil = await Jaringan.denganUlang(
      () => _sb
          .rpc('gudang_simpan_opname', params: {'p_baris': baris})
          .timeout(const Duration(seconds: 60)),
    );
    return HasilSimpanOpname.dari(hasil);
  }
}

class HasilSimpanOpname {
  const HasilSimpanOpname({
    required this.ditutup,
    required this.ditulis,
    required this.terisi,
    required this.total,
    required this.kurang,
  });

  factory HasilSimpanOpname.dari(dynamic v) {
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      return HasilSimpanOpname(
        ditutup: m['ditutup'] == true,
        ditulis: _i(m['ditulis']),
        terisi: _i(m['terisi']),
        total: _i(m['total']),
        kurang: _i(m['kurang']),
      );
    }
    throw StateError('gudang_simpan_opname: hasil tidak dikenal.');
  }

  final bool ditutup;
  final int ditulis;
  final int terisi;
  final int total;
  final int kurang;
}
