import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/buku_hari.dart';
import '../beranda/kartu_toko.dart';
import '../beranda/ringkas_hari.dart';
import '../beranda/setoran_pengirim.dart';
import '../jaringan.dart';
import '../uang.dart';
import 'retur_toko.dart';

class TokoRepo {
  TokoRepo(this._sb);
  final SupabaseClient _sb;

  Future<DateTime> waktuServer() async {
    final hasil = await _sb.rpc('gudang_waktu_sekarang').timeout(Jaringan.lambat);
    if (hasil is String) {
      return DateTime.parse(hasil.replaceFirst(' ', 'T'));
    }
    return DateTime.parse(hasil.toString());
  }

  Future<List<String>> ruteSales() async {
    final hasil =
        await _sb.rpc('pengirim_rute_sales').timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  Future<BukuHari?> bukuHari([DateTime? tanggal]) async {
    final hasil = await _sb
        .rpc(
          'setoran_buku_untuk_hari',
          params: {
            if (tanggal != null) 'p_tanggal': Uang.isoHari(tanggal),
          },
        )
        .timeout(Jaringan.lambat);
    return BukuHari.dari(hasil);
  }

  Future<RingkasHari> ringkasHari(
    DateTime tanggal, {
    List<KartuToko> kartu = const [],
  }) async {
    final cadangan = RingkasHari.dariKartu(kartu);
    try {
      final hasil = await _sb
          .rpc(
            'pengirim_ringkas_hari',
            params: {'p_tanggal': Uang.isoHari(tanggal)},
          )
          .timeout(Jaringan.lambat);
      Map<String, dynamic>? row;
      if (hasil is Map) {
        row = Map<String, dynamic>.from(hasil);
      } else if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
        row = Map<String, dynamic>.from(hasil.first as Map);
      }
      if (row == null) return cadangan;
      return RingkasHari.fromJson(row);
    } catch (_) {
      return cadangan;
    }
  }

  Future<List<KartuToko>> kartu(DateTime tanggal) async {
    final hasil = await _sb
        .rpc(
          'pengirim_kartu_toko',
          params: {'p_tanggal': Uang.isoHari(tanggal)},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => KartuToko.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.idPelanggan.isNotEmpty)
        .toList();
  }

  Future<List<RingkasNota>> notaToko(DateTime tanggal, String idPelanggan) async {
    final hasil = await _sb
        .rpc(
          'pengirim_nota_toko',
          params: {
            'p_tanggal': Uang.isoHari(tanggal),
            'p_id_pelanggan': idPelanggan,
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => RingkasNota.fromJson(Map<String, dynamic>.from(e)))
        .where((n) => n.idTransaksi.isNotEmpty)
        .toList();
  }

  Future<List<ItemNota>> item(String idTransaksi) async {
    final hasil = await _sb
        .rpc(
          'pengirim_nota_item',
          params: {'p_id_transaksi': idTransaksi},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return hasil
        .whereType<Map>()
        .map((e) => ItemNota.fromJson(Map<String, dynamic>.from(e)))
        .where((i) => i.idBarang.isNotEmpty)
        .toList();
  }

  Future<void> pendingNota(String idTransaksi) {
    return _sb
        .rpc('pengirim_pending_nota', params: {'p_id_transaksi': idTransaksi})
        .timeout(Jaringan.lambat);
  }

  Future<void> batalNota(String idTransaksi) {
    return Jaringan.denganUlang(
      () => _sb
          .rpc('pengirim_batal_nota', params: {'p_id_transaksi': idTransaksi})
          .timeout(Jaringan.lambat),
    );
  }

  Future<void> kunciNota({
    required String idTransaksi,
    required List<Map<String, dynamic>> baris,
  }) {
    return Jaringan.denganUlang(
      () => _sb
          .rpc(
            'pengirim_kunci_nota',
            params: {
              'p_id_transaksi': idTransaksi,
              'p_baris': baris,
            },
          )
          .timeout(Jaringan.lambat),
    );
  }

  Future<void> bukaKunciNota(String idTransaksi) {
    return _sb
        .rpc(
          'pengirim_buka_kunci_nota',
          params: {'p_id_transaksi': idTransaksi},
        )
        .timeout(Jaringan.lambat);
  }

  Future<SetoranPengirim> setoranLihat() async {
    final hasil =
        await _sb.rpc('pengirim_setoran_lihat').timeout(Jaringan.lambat);
    Map<String, dynamic>? row;
    if (hasil is Map) {
      row = Map<String, dynamic>.from(hasil);
    } else if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      row = Map<String, dynamic>.from(hasil.first as Map);
    }
    if (row == null) return SetoranPengirim.kosong;
    return SetoranPengirim.fromJson(row);
  }

  Future<bool> setoranSimpan(SetoranPengirim data) async {
    final ok = await Jaringan.denganUlang(
      () => _sb
          .rpc(
            'pengirim_setoran_simpan',
            params: {
              'p_jumlah_transfer': data.transfer,
              'p_jumlah_tunai': data.tunai,
              'p_jumlah_bop': data.bop,
              'p_kasbon_supir': data.kasbonSupir,
              'p_kasbon_kenek': data.kasbonKenek,
            },
          )
          .timeout(Jaringan.lambat),
    );
    return ok == true;
  }

  Future<DateTime> scanKunjungan({
    required String idPelanggan,
    required bool keluar,
    required double latitude,
    required double longitude,
    required DateTime waktu,
  }) async {
    final hasil = await _sb
        .rpc(
          'pengirim_scan_kunjungan',
          params: {
            'p_id_pelanggan': idPelanggan,
            'p_keluar': keluar,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_waktu': waktu.toUtc().toIso8601String(),
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is DateTime) return hasil;
    if (hasil is String) {
      return DateTime.parse(hasil.replaceFirst(' ', 'T'));
    }
    return DateTime.parse(hasil.toString());
  }

  int _n(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<List<BarisReturToko>> returTokoLihat(
    DateTime tanggal,
    String idPelanggan,
  ) async {
    final hasil = await _sb
        .rpc(
          'pengirim_retur_toko_lihat',
          params: {
            'p_tanggal': Uang.isoHari(tanggal),
            'p_id_pelanggan': idPelanggan,
          },
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return [
      for (final e in hasil)
        if (e is Map) BarisReturToko.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<List<BarisReturRute>> returRuteLihat(DateTime tanggal) async {
    final hasil = await _sb
        .rpc(
          'pengirim_retur_rute_lihat',
          params: {'p_tanggal': Uang.isoHari(tanggal)},
        )
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return [
      for (final e in hasil)
        if (e is Map) BarisReturRute.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<List<SaranBarang>> barangCari(String cari) async {
    final hasil = await _sb
        .rpc('pengirim_barang_cari', params: {'p_cari': cari})
        .timeout(Jaringan.lambat);
    if (hasil is! List) return [];
    return [
      for (final e in hasil)
        if (e is Map)
          SaranBarang(
            kode: e['kode_barang']?.toString() ?? '',
            nama: e['nama_barang']?.toString() ?? '',
            harga: _n(e['harga_jual']),
          ),
    ];
  }

  Future<bool> returTokoSimpan({
    required DateTime tanggal,
    required String idPelanggan,
    required List<Map<String, dynamic>> baris,
  }) async {
    final ok = await Jaringan.denganUlang(
      () => _sb
          .rpc(
            'pengirim_retur_toko_simpan',
            params: {
              'p_tanggal': Uang.isoHari(tanggal),
              'p_id_pelanggan': idPelanggan,
              'p_baris': baris,
            },
          )
          .timeout(Jaringan.lambat),
    );
    return ok == true;
  }

  Future<bool> returDikunci(DateTime tanggal) async {
    final ok = await _sb
        .rpc(
          'pengirim_retur_dikunci',
          params: {'p_tanggal': Uang.isoHari(tanggal)},
        )
        .timeout(Jaringan.lambat);
    return ok == true;
  }
}
