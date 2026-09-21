import 'dart:convert';

import 'package:obos_core/obos_core.dart';

class NotaAntri {
  const NotaAntri({
    required this.idTransaksi,
    required this.idPelanggan,
    required this.namaPelanggan,
    required this.items,
    this.aksi = 'simpan',
  });

  final String idTransaksi;
  final String idPelanggan;
  final String namaPelanggan;
  final List<Map<String, dynamic>> items;

  /// simpan | ubah | batal
  final String aksi;

  Map<String, dynamic> toJson() => {
        'id_transaksi': idTransaksi,
        'id_pelanggan': idPelanggan,
        'nama_pelanggan': namaPelanggan,
        'items': items,
        'aksi': aksi,
      };

  factory NotaAntri.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) items.add(Map<String, dynamic>.from(e));
      }
    }
    final aksi = json['aksi']?.toString() ?? 'simpan';
    return NotaAntri(
      idTransaksi: json['id_transaksi']?.toString() ?? '',
      idPelanggan: json['id_pelanggan']?.toString() ?? '',
      namaPelanggan: json['nama_pelanggan']?.toString() ?? '',
      items: items,
      aksi: aksi == 'ubah' || aksi == 'batal' ? aksi : 'simpan',
    );
  }
}

class TransaksiCache {
  static const _kunci = 'nota_antri_json';

  static Future<List<NotaAntri>> semua() async {
    final raw = await PrefsHp.getString(_kunci);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => NotaAntri.fromJson(Map<String, dynamic>.from(e)))
          .where((n) => n.idTransaksi.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<NotaAntri>> untukToko(String idPelanggan) async {
    final id = idPelanggan.trim();
    return (await semua()).where((n) => n.idPelanggan == id).toList();
  }

  static Future<int> jumlahSiapKirim() async {
    var n = 0;
    for (final nota in await semua()) {
      if (nota.idPelanggan.startsWith('TMP')) continue;
      n++;
    }
    return n;
  }

  static Future<void> _tulis(List<NotaAntri> daftar) async {
    await PrefsHp.setString(
      _kunci,
      jsonEncode(daftar.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> antre(NotaAntri nota) async {
    final daftar = await semua();
    final tanpa = daftar.where((n) => n.idTransaksi != nota.idTransaksi).toList();
    await _tulis([...tanpa, nota]);
  }

  static Future<void> hapus(String idTransaksi) async {
    final daftar = await semua();
    await _tulis(daftar.where((n) => n.idTransaksi != idTransaksi).toList());
  }

  static Future<NotaAntri?> cari(String idTransaksi) async {
    final daftar = await semua();
    for (final n in daftar) {
      if (n.idTransaksi == idTransaksi) return n;
    }
    return null;
  }
}
