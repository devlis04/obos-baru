import 'dart:convert';

import 'package:obos_core/obos_core.dart';
import '../uang.dart';
import 'barang.dart';

class HargaBerubah {
  const HargaBerubah({
    required this.id,
    required this.nama,
    required this.hargaLama,
    required this.hargaBaru,
    required this.strataBerubah,
  });

  final String id;
  final String nama;
  final int hargaLama;
  final int hargaBaru;
  final bool strataBerubah;
}

class KatalogBerubah {
  const KatalogBerubah({
    required this.baru,
    required this.harga,
    required this.hapus,
  });

  final List<Barang> baru;
  final List<HargaBerubah> harga;
  final List<Barang> hapus;

  static const kosong = KatalogBerubah(baru: [], harga: [], hapus: []);

  bool get ada => baru.isNotEmpty || harga.isNotEmpty || hapus.isNotEmpty;

  static KatalogBerubah bandingkan({
    required List<Barang> lokal,
    required List<Barang> server,
  }) {
    if (lokal.isEmpty) return kosong;

    final mapLokal = {
      for (final item in lokal)
        if (item.id.isNotEmpty) item.id: item,
    };
    final mapServer = {
      for (final item in server)
        if (item.id.isNotEmpty) item.id: item,
    };

    final baru = <Barang>[];
    final harga = <HargaBerubah>[];
    for (final item in server) {
      final lama = mapLokal[item.id];
      if (lama == null) {
        baru.add(item);
        continue;
      }
      if (_hargaAtauStrata(lama, item)) {
        harga.add(
          HargaBerubah(
            id: item.id,
            nama: item.nama,
            hargaLama: lama.hargaJual,
            hargaBaru: item.hargaJual,
            strataBerubah: _strata(lama, item),
          ),
        );
      }
    }

    final hapus = [
      for (final item in lokal)
        if (!mapServer.containsKey(item.id)) item,
    ];

    return KatalogBerubah(baru: baru, harga: harga, hapus: hapus);
  }

  static bool _strata(Barang a, Barang b) {
    return a.minStrat1 != b.minStrat1 ||
        a.jualStrat1 != b.jualStrat1 ||
        a.minStrat2 != b.minStrat2 ||
        a.jualStrat2 != b.jualStrat2 ||
        a.minStrat3 != b.minStrat3 ||
        a.jualStrat3 != b.jualStrat3 ||
        a.minStrat4 != b.minStrat4 ||
        a.jualStrat4 != b.jualStrat4 ||
        a.minStrat5 != b.minStrat5 ||
        a.jualStrat5 != b.jualStrat5;
  }

  static bool _hargaAtauStrata(Barang a, Barang b) {
    return a.hargaJual != b.hargaJual || _strata(a, b);
  }
}

String ringkasHarga(HargaBerubah item) {
  if (item.hargaLama != item.hargaBaru) {
    return '${item.nama}: ${Uang.rp(item.hargaLama)} → ${Uang.rp(item.hargaBaru)}';
  }
  return '${item.nama}: strata grosir diperbarui';
}

class PesanKatalog {
  const PesanKatalog({
    required this.id,
    required this.jenis,
    required this.judul,
    required this.isi,
    required this.dibuatPada,
    this.sudahDibaca = false,
  });

  final String id;
  final String jenis;
  final String judul;
  final String isi;
  final int dibuatPada;
  final bool sudahDibaca;

  PesanKatalog salin({bool? sudahDibaca}) {
    return PesanKatalog(
      id: id,
      jenis: jenis,
      judul: judul,
      isi: isi,
      dibuatPada: dibuatPada,
      sudahDibaca: sudahDibaca ?? this.sudahDibaca,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jenis': jenis,
        'judul': judul,
        'isi': isi,
        'dibuat_pada': dibuatPada,
        'sudah_dibaca': sudahDibaca,
      };

  factory PesanKatalog.fromJson(Map<String, dynamic> json) {
    return PesanKatalog(
      id: json['id']?.toString() ?? '',
      jenis: json['jenis']?.toString() ?? '',
      judul: json['judul']?.toString() ?? '',
      isi: json['isi']?.toString() ?? '',
      dibuatPada: (json['dibuat_pada'] as num?)?.toInt() ?? 0,
      sudahDibaca: json['sudah_dibaca'] == true,
    );
  }
}

class PesanKatalogStore {
  static const _kunci = 'pesan_katalog_json';
  static const _batas = 80;

  static Future<List<PesanKatalog>> semua() async {
    final raw = await PrefsHp.getString(_kunci);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = decoded
          .whereType<Map>()
          .map((e) => PesanKatalog.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      list.sort((a, b) {
        if (a.sudahDibaca != b.sudahDibaca) {
          return a.sudahDibaca ? 1 : -1;
        }
        return b.dibuatPada.compareTo(a.dibuatPada);
      });
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _tulis(List<PesanKatalog> daftar) async {
    await PrefsHp.setString(
      _kunci,
      jsonEncode(daftar.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> simpanDari(KatalogBerubah notice) async {
    if (!notice.ada) return;
    final list = await semua();
    final existing = {for (final e in list) e.id};
    final now = DateTime.now().millisecondsSinceEpoch;

    void tambah(PesanKatalog pesan) {
      if (existing.contains(pesan.id)) return;
      list.add(pesan);
      existing.add(pesan.id);
    }

    for (final item in notice.baru) {
      tambah(
        PesanKatalog(
          id: 'baru|${item.id}',
          jenis: 'baru',
          judul: 'Barang baru',
          isi: '${item.nama} (${item.id})',
          dibuatPada: now,
        ),
      );
    }
    for (final item in notice.harga) {
      tambah(
        PesanKatalog(
          id:
              'harga|${item.id}|${item.hargaLama}|${item.hargaBaru}|${item.strataBerubah}',
          jenis: 'harga',
          judul: 'Harga / strata berubah',
          isi: ringkasHarga(item),
          dibuatPada: now,
        ),
      );
    }
    for (final item in notice.hapus) {
      tambah(
        PesanKatalog(
          id: 'hapus|${item.id}',
          jenis: 'hapus',
          judul: 'Tidak lagi di katalog',
          isi: '${item.nama} (${item.id})',
          dibuatPada: now,
        ),
      );
    }

    list.sort((a, b) => a.dibuatPada.compareTo(b.dibuatPada));
    final dipotong =
        list.length > _batas ? list.sublist(list.length - _batas) : list;
    await _tulis(dipotong);
  }

  static Future<void> tandaiDibaca(String id) async {
    final list = await semua();
    var ubah = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id != id || list[i].sudahDibaca) continue;
      list[i] = list[i].salin(sudahDibaca: true);
      ubah = true;
    }
    if (!ubah) return;
    await _tulis(list);
  }

  static Future<void> tandaiSemua() async {
    final list = (await semua())
        .map((e) => e.sudahDibaca ? e : e.salin(sudahDibaca: true))
        .toList();
    await _tulis(list);
  }

  static Future<void> kosongkan() async {
    await PrefsHp.hapus(_kunci);
  }
}
