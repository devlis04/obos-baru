import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';

num _q(dynamic v) {
  if (v is num) return v;
  return num.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

int _n(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

class RingkasOpname {
  const RingkasOpname({
    required this.adaBuku,
    this.idSetoranBuku,
    this.tanggal,
    this.ditutup = false,
    this.skuTotal = 0,
    this.skuFisik = 0,
    this.skuSelisih = 0,
    this.nilaiSelisih = 0,
    this.skuMinusBelum = 0,
    this.nilaiKasbon = 0,
    this.nilaiBeban = 0,
    this.nilaiMarginPlus = 0,
  });

  static const kosong = RingkasOpname(adaBuku: false);

  final bool adaBuku;
  final int? idSetoranBuku;
  final DateTime? tanggal;
  final bool ditutup;
  final int skuTotal;
  final int skuFisik;
  final int skuSelisih;
  final int nilaiSelisih;
  final int skuMinusBelum;
  final int nilaiKasbon;
  final int nilaiBeban;
  final int nilaiMarginPlus;

  @override
  bool operator ==(Object other) =>
      other is RingkasOpname &&
      other.adaBuku == adaBuku &&
      other.idSetoranBuku == idSetoranBuku &&
      other.tanggal == tanggal &&
      other.ditutup == ditutup &&
      other.skuTotal == skuTotal &&
      other.skuFisik == skuFisik &&
      other.skuSelisih == skuSelisih &&
      other.nilaiSelisih == nilaiSelisih &&
      other.skuMinusBelum == skuMinusBelum &&
      other.nilaiKasbon == nilaiKasbon &&
      other.nilaiBeban == nilaiBeban &&
      other.nilaiMarginPlus == nilaiMarginPlus;

  @override
  int get hashCode => Object.hash(
        adaBuku,
        idSetoranBuku,
        tanggal,
        ditutup,
        skuTotal,
        skuFisik,
        skuSelisih,
        nilaiSelisih,
        skuMinusBelum,
        nilaiKasbon,
        nilaiBeban,
        nilaiMarginPlus,
      );

  factory RingkasOpname.dari(Map<String, dynamic> m) {
    DateTime? tgl;
    final raw = m['tanggal']?.toString();
    if (raw != null && raw.isNotEmpty) {
      tgl = DateTime.tryParse(raw);
    }
    return RingkasOpname(
      adaBuku: m['ada_buku'] == true,
      idSetoranBuku: (m['id_setoran_buku'] as num?)?.toInt(),
      tanggal: tgl,
      ditutup: m['ditutup'] == true,
      skuTotal: _n(m['sku_total']),
      skuFisik: _n(m['sku_fisik']),
      skuSelisih: _n(m['sku_selisih']),
      nilaiSelisih: _n(m['nilai_selisih']),
      skuMinusBelum: _n(m['sku_minus_belum']),
      nilaiKasbon: _n(m['nilai_kasbon']),
      nilaiBeban: _n(m['nilai_beban']),
      nilaiMarginPlus: _n(m['nilai_margin_plus']),
    );
  }
}

class BarisSelisihOpname {
  const BarisSelisihOpname({
    required this.idBarang,
    required this.nama,
    required this.stokHitung,
    required this.stokFisik,
    required this.selisih,
    required this.nilaiSelisih,
    required this.dicekOleh,
    this.putusan = '',
    this.kasbonEmail = '',
    this.kasbonNama = '',
    this.nilaiPutusan = 0,
    this.tokoPacked = const [],
  });

  final String idBarang;
  final String nama;
  final num stokHitung;
  final num stokFisik;
  final num selisih;
  final int nilaiSelisih;
  final String dicekOleh;
  final String putusan;
  final String kasbonEmail;
  final String kasbonNama;
  final int nilaiPutusan;
  final List<TokoPacked> tokoPacked;

  factory BarisSelisihOpname.dari(Map<String, dynamic> m) {
    final rawToko = m['toko_packed'];
    final toko = <TokoPacked>[];
    var daftar = rawToko;
    if (daftar is String && daftar.isNotEmpty) {
      daftar = jsonDecode(daftar);
    }
    if (daftar is List) {
      for (final e in daftar) {
        if (e is Map) {
          toko.add(TokoPacked.dari(Map<String, dynamic>.from(e)));
        }
      }
    }
    return BarisSelisihOpname(
      idBarang: m['id_barang']?.toString() ?? '',
      nama: m['nama_barang']?.toString() ?? '',
      stokHitung: _q(m['stok_hitung']),
      stokFisik: _q(m['stok_fisik']),
      selisih: _q(m['selisih']),
      nilaiSelisih: _n(m['nilai_selisih']),
      dicekOleh: m['dicek_stok_oleh']?.toString() ?? '',
      putusan: m['putusan']?.toString() ?? '',
      kasbonEmail: m['kasbon_email']?.toString() ?? '',
      kasbonNama: m['kasbon_nama']?.toString() ?? '',
      nilaiPutusan: _n(m['nilai_putusan']),
      tokoPacked: toko,
    );
  }
}

class TokoPacked {
  const TokoPacked({
    required this.idPelanggan,
    required this.nama,
    required this.qty,
  });

  final String idPelanggan;
  final String nama;
  final num qty;

  factory TokoPacked.dari(Map<String, dynamic> m) {
    return TokoPacked(
      idPelanggan: m['id_pelanggan']?.toString() ?? '',
      nama: m['nama']?.toString() ?? '',
      qty: _q(m['qty']),
    );
  }
}

class UserKasbon {
  const UserKasbon({
    required this.email,
    required this.nama,
    required this.peran,
  });

  final String email;
  final String nama;
  final String peran;

  factory UserKasbon.dari(Map<String, dynamic> m) {
    return UserKasbon(
      email: m['email']?.toString() ?? '',
      nama: m['nama']?.toString() ?? '',
      peran: m['peran']?.toString() ?? '',
    );
  }
}

class OpnameRepo {
  OpnameRepo(this._sb);
  final SupabaseClient _sb;

  Future<RingkasOpname> ringkas({int? idBuku}) async {
    final hasil = await _sb
        .rpc(
          'admin_opname_ringkas',
          params: {'p_id_setoran_buku': ?idBuku},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! Map) return RingkasOpname.kosong;
    return RingkasOpname.dari(Map<String, dynamic>.from(hasil));
  }

  Future<List<BarisSelisihOpname>> selisih(int idBuku) async {
    final hasil = await _sb
        .rpc('admin_opname_lihat', params: {'p_id_setoran_buku': idBuku})
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => BarisSelisihOpname.dari(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> konfirmasi(int idBuku) {
    return _sb
        .rpc('admin_konfirmasi_opname', params: {'p_id_setoran_buku': idBuku})
        .timeout(Jaringan.lambat);
  }

  Future<void> tutupBuku() {
    return _sb.rpc('admin_tutup_setoran_buku').timeout(Jaringan.lambat);
  }

  Future<List<UserKasbon>> usersKasbon() async {
    final hasil = await _sb.rpc('admin_users_kasbon').timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => UserKasbon.dari(Map<String, dynamic>.from(e)))
        .where((u) => u.email.isNotEmpty)
        .toList();
  }

  Future<void> putusan({
    required int idBuku,
    required String idBarang,
    required String jenis,
    String? email,
  }) {
    return _sb
        .rpc(
          'admin_opname_putusan',
          params: {
            'p_id_setoran_buku': idBuku,
            'p_id_barang': idBarang,
            'p_jenis': jenis,
            'p_email': email,
          },
        )
        .timeout(Jaringan.lambat);
  }
}
