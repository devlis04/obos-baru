import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';

int _n(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString().replaceAll('.', '') ?? '') ?? 0;
}

num _q(dynamic v) {
  if (v is num) return v;
  return num.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

class ChipSupplier {
  const ChipSupplier({
    required this.id,
    required this.nama,
    this.sku = 0,
    this.nilai = 0,
    this.ongkir = 0,
  });

  final int id;
  final String nama;
  final int sku;
  final int nilai;
  final int ongkir;

  @override
  bool operator ==(Object other) =>
      other is ChipSupplier &&
      other.id == id &&
      other.nama == nama &&
      other.sku == sku &&
      other.nilai == nilai &&
      other.ongkir == ongkir;

  @override
  int get hashCode => Object.hash(id, nama, sku, nilai, ongkir);
}

class RingkasMasuk {
  const RingkasMasuk({
    required this.adaBuku,
    this.idSetoranBuku,
    this.tanggal,
    this.sku = 0,
    this.nilai = 0,
    this.ongkir = 0,
    this.supplier = const [],
  });

  static const kosong = RingkasMasuk(adaBuku: false);

  final bool adaBuku;
  final int? idSetoranBuku;
  final DateTime? tanggal;
  final int sku;
  final int nilai;
  final int ongkir;
  final List<ChipSupplier> supplier;

  @override
  bool operator ==(Object other) =>
      other is RingkasMasuk &&
      other.adaBuku == adaBuku &&
      other.idSetoranBuku == idSetoranBuku &&
      other.tanggal == tanggal &&
      other.sku == sku &&
      other.nilai == nilai &&
      other.ongkir == ongkir &&
      _samaSupplier(other.supplier, supplier);

  @override
  int get hashCode => Object.hash(
        adaBuku,
        idSetoranBuku,
        tanggal,
        sku,
        nilai,
        ongkir,
        Object.hashAll(supplier),
      );

  factory RingkasMasuk.dari(Map<String, dynamic> m) {
    DateTime? tgl;
    final raw = m['tanggal']?.toString();
    if (raw != null && raw.isNotEmpty) tgl = DateTime.tryParse(raw);
    final supplier = _chipDari(m['supplier']);
    final nilaiRpc = _n(m['nilai']);
    final ongkirRpc = _n(m['ongkir']);
    final jumNilai = supplier.fold<int>(0, (a, s) => a + s.nilai);
    final jumOngkir = supplier.fold<int>(0, (a, s) => a + s.ongkir);
    return RingkasMasuk(
      adaBuku: m['ada_buku'] == true,
      idSetoranBuku: (m['id_setoran_buku'] as num?)?.toInt(),
      tanggal: tgl,
      sku: _n(m['sku']),
      nilai: jumNilai > nilaiRpc ? jumNilai : nilaiRpc,
      ongkir: jumOngkir > ongkirRpc ? jumOngkir : ongkirRpc,
      supplier: supplier,
    );
  }
}

bool _samaSupplier(List<ChipSupplier> a, List<ChipSupplier> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<ChipSupplier> _chipDari(dynamic raw) {
  var data = raw;
  if (data is String && data.isNotEmpty) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return const [];
    }
  }
  if (data is! List) return const [];
  return data.whereType<Map>().map((e) {
    final m = Map<String, dynamic>.from(e);
    return ChipSupplier(
      id: _n(m['id'] ?? m['id_supplier']),
      nama: ((m['nama'] ?? m['nama_supplier'])?.toString() ?? '').trim(),
      sku: _n(m['sku']),
      nilai: _n(m['nilai']),
      ongkir: _n(m['ongkir']),
    );
  }).where((s) => s.id > 0).map((s) {
    if (s.nama.isNotEmpty) return s;
    return ChipSupplier(
      id: s.id,
      nama: 'Supplier ${s.id}',
      sku: s.sku,
      nilai: s.nilai,
      ongkir: s.ongkir,
    );
  }).toList();
}

class Supplier {
  const Supplier({required this.id, required this.nama});
  final int id;
  final String nama;
}

class BarisMasuk {
  const BarisMasuk({
    required this.idBarang,
    required this.nama,
    required this.qty,
    required this.nilai,
    required this.hargaBeli,
  });

  final String idBarang;
  final String nama;
  final num qty;
  final int nilai;
  final int hargaBeli;
}

class CariBarang {
  const CariBarang({
    required this.idBarang,
    required this.nama,
    required this.hargaBeli,
  });

  final String idBarang;
  final String nama;
  final int hargaBeli;
}

class BarangKatalog {
  const BarangKatalog({
    required this.idBarang,
    required this.namaBarang,
    required this.kategori,
    required this.hargaBeli,
  });

  final String idBarang;
  final String namaBarang;
  final String kategori;
  final int hargaBeli;
}

class MasukanRepo {
  MasukanRepo(this._sb);
  final SupabaseClient _sb;

  Future<RingkasMasuk> ringkas({int? idBuku}) async {
    final hasil = await _sb
        .rpc(
          'admin_barang_masuk_ringkas',
          params: {'p_id_setoran_buku': ?idBuku},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! Map) return RingkasMasuk.kosong;
    return RingkasMasuk.dari(Map<String, dynamic>.from(hasil));
  }

  Future<List<Supplier>> supplier() async {
    final hasil = await _sb.rpc('admin_supplier_daftar').timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return Supplier(
        id: (m['id'] as num?)?.toInt() ?? 0,
        nama: m['nama']?.toString() ?? '',
      );
    }).where((s) => s.id > 0).toList();
  }

  Future<int> tambahSupplier(String nama) async {
    final hasil = await _sb
        .rpc('admin_supplier_tambah', params: {'p_nama': nama})
        .timeout(Jaringan.lambat);
    if (hasil is num) return hasil.toInt();
    return int.tryParse(hasil.toString()) ?? 0;
  }

  Future<List<CariBarang>> cari(String q) async {
    final hasil = await _sb
        .rpc('admin_barang_cari', params: {'p_q': q})
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return CariBarang(
        idBarang: m['id_barang']?.toString() ?? '',
        nama: m['nama_barang']?.toString() ?? '',
        hargaBeli: _n(m['harga_beli']),
      );
    }).where((b) => b.idBarang.isNotEmpty).toList();
  }

  Future<List<BarangKatalog>> katalogCsv() async {
    final hasil =
        await _sb.rpc('admin_barang_masuk_csv').timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return BarangKatalog(
        idBarang: m['id_barang']?.toString() ?? '',
        namaBarang: m['nama_barang']?.toString() ?? '',
        kategori: m['kategori']?.toString() ?? '',
        hargaBeli: _n(m['harga_beli']),
      );
    }).where((b) => b.idBarang.isNotEmpty).toList();
  }

  Future<List<BarisMasuk>> lihat(int idSupplier, {int? idBuku}) async {
    final hasil = await _sb
        .rpc(
          'admin_barang_masuk_lihat',
          params: {
            'p_id_supplier': idSupplier,
            'p_id_setoran_buku': ?idBuku,
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return BarisMasuk(
        idBarang: m['id_barang']?.toString() ?? '',
        nama: m['nama_barang']?.toString() ?? '',
        qty: _q(m['qty']),
        nilai: _n(m['nilai']),
        hargaBeli: _n(m['harga_beli']),
      );
    }).toList();
  }

  Future<int> ongkirSupplier(int idSupplier, {int? idBuku}) async {
    final hasil = await _sb
        .rpc(
          'admin_ongkir_lihat_supplier',
          params: {
            'p_id_supplier': idSupplier,
            'p_id_setoran_buku': ?idBuku,
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is num) return hasil.toInt();
    return int.tryParse(hasil.toString()) ?? 0;
  }

  Future<int> simpan({
    required int idSupplier,
    required List<Map<String, dynamic>> baris,
    int? ongkir,
  }) async {
    final hasil = await _sb
        .rpc(
          'admin_barang_masuk_simpan',
          params: {
            'p_id_supplier': idSupplier,
            'p_baris': baris,
            'p_ongkir': ongkir,
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is num) return hasil.toInt();
    return int.tryParse(hasil.toString()) ?? 0;
  }

  Future<void> ubah({
    required int idSupplier,
    required String idBarang,
    required num qty,
    required num hargaBeli,
  }) {
    return _sb
        .rpc(
          'admin_barang_masuk_ubah',
          params: {
            'p_id_supplier': idSupplier,
            'p_id_barang': idBarang,
            'p_qty': qty,
            'p_harga_beli': hargaBeli,
          },
        )
        .timeout(Jaringan.lambat);
  }

  Future<void> hapus({required int idSupplier, required String idBarang}) {
    return _sb
        .rpc(
          'admin_barang_masuk_hapus',
          params: {
            'p_id_supplier': idSupplier,
            'p_id_barang': idBarang,
          },
        )
        .timeout(Jaringan.lambat);
  }
}
