import 'package:supabase_flutter/supabase_flutter.dart';

import '../barang/barang.dart';
import '../jaringan.dart';
import '../pelanggan/pelanggan.dart';
import 'nota.dart';
import 'transaksi_cache.dart';
import 'transaksi_helper.dart';

class HasilSimpan {
  const HasilSimpan({
    required this.ok,
    required this.terunggah,
    required this.pesan,
  });

  final bool ok;
  final bool terunggah;
  final String pesan;
}

class TargetSales {
  const TargetSales({required this.omset, required this.persenLaba});

  final int omset;
  final double persenLaba;

  static const kosong = TargetSales(omset: 0, persenLaba: 0);
}

class TransaksiRepo {
  TransaksiRepo(this._sb);
  final SupabaseClient _sb;

  static const _kolomItem =
      'id_barang, id_grup, nama_barang, qty_order, harga_jual, harga_beli, '
      'qty_packed, qty_actual, '
      'subtotal_beli_order, '
      'min_strat_1, jual_strat_1, min_strat_2, jual_strat_2, '
      'min_strat_3, jual_strat_3, min_strat_4, jual_strat_4, '
      'min_strat_5, jual_strat_5';

  static const _kolom =
      'id_transaksi, id_pelanggan, nama_pelanggan, rute, status, '
      'waktu_order, waktu_packed, waktu_actual, pending, '
      'transaksi_items($_kolomItem)';

  static const _kolomCapaian =
      'id_transaksi, id_pelanggan, nama_pelanggan, rute, status, '
      'waktu_order, waktu_packed, waktu_actual, pending, '
      'transaksi_items($_kolomItem)';

  List<Map<String, dynamic>> _itemsKeranjang({
    required Map<String, int> keranjang,
    required List<Barang> daftar,
  }) {
    final items = <Map<String, dynamic>>[];
    keranjang.forEach((idBarang, qty) {
      if (qty <= 0) return;
      for (final b in daftar) {
        if (b.id != idBarang) continue;
        items.add({
          'id_barang': b.id,
          'nama_barang': b.nama,
          'qty': qty,
          'harga_jual': TransaksiHelper.hargaJual(
            barang: b,
            keranjang: keranjang,
            daftar: daftar,
          ),
        });
        break;
      }
    });
    return items;
  }

  Future<HasilSimpan> simpan({
    required String idPelanggan,
    required String namaPelanggan,
    required Map<String, int> keranjang,
    required List<Barang> daftar,
    String? idTransaksi,
  }) async {
    final id = idPelanggan.trim();
    if (id.isEmpty || id.startsWith('TMP')) {
      return const HasilSimpan(
        ok: false,
        terunggah: false,
        pesan:
            'Toko baru belum punya id cloud. Sambungkan internet, unduh rute, lalu simpan lagi.',
      );
    }

    final items = _itemsKeranjang(keranjang: keranjang, daftar: daftar);
    if (items.isEmpty) {
      return const HasilSimpan(
        ok: false,
        terunggah: false,
        pesan:
            'Belum ada barang di keranjang. Tambahkan barang dulu, lalu simpan.',
      );
    }

    final idNota = (idTransaksi ?? '').trim().isNotEmpty
        ? idTransaksi!.trim()
        : 'ORD-$id-${DateTime.now().millisecondsSinceEpoch}';
    final ubah = (idTransaksi ?? '').trim().isNotEmpty;

    final nota = NotaAntri(
      idTransaksi: idNota,
      idPelanggan: id,
      namaPelanggan: namaPelanggan.trim().toUpperCase(),
      items: items,
      aksi: ubah ? 'ubah' : 'simpan',
    );

    if (ubah) {
      final antri = await TransaksiCache.cari(idNota);
      if (antri != null && antri.aksi == 'simpan') {
        final antriBaru = NotaAntri(
          idTransaksi: idNota,
          idPelanggan: id,
          namaPelanggan: nota.namaPelanggan,
          items: items,
          aksi: 'simpan',
        );
        await TransaksiCache.antre(antriBaru);
        try {
          await _rpcSimpan(antriBaru);
          if (await _rpcUbah(antriBaru.copyAksi('ubah'))) {
            await TransaksiCache.hapus(idNota);
            return const HasilSimpan(
              ok: true,
              terunggah: true,
              pesan: 'Perubahan nota tersimpan.',
            );
          }
        } catch (_) {}
        return const HasilSimpan(
          ok: true,
          terunggah: false,
          pesan: 'Perubahan tersimpan di HP. Akan diunggah saat ada internet.',
        );
      }
    }

    try {
      if (await _kirimSatu(nota)) {
        await TransaksiCache.hapus(idNota);
        return HasilSimpan(
          ok: true,
          terunggah: true,
          pesan: ubah ? 'Perubahan nota tersimpan.' : 'Nota tersimpan.',
        );
      }
      if (ubah) {
        return const HasilSimpan(
          ok: false,
          terunggah: false,
          pesan:
              'Nota sudah tidak bisa diubah. Muat ulang riwayat, lalu coba lagi.',
        );
      }
    } catch (_) {}

    await TransaksiCache.antre(nota);
    return HasilSimpan(
      ok: true,
      terunggah: false,
      pesan: ubah
          ? 'Perubahan tersimpan di HP. Akan diunggah saat ada internet.'
          : 'Nota tersimpan di HP. Akan diunggah saat ada internet.',
    );
  }

  Future<HasilSimpan> batal(Nota nota) async {
    final id = nota.id.trim();
    if (id.isEmpty) {
      return const HasilSimpan(
        ok: false,
        terunggah: false,
        pesan: 'Nota ini belum bisa dibatalkan. Muat ulang, lalu coba lagi.',
      );
    }

    final antri = await TransaksiCache.cari(id);
    if (antri != null && antri.aksi == 'simpan') {
      await TransaksiCache.hapus(id);
      return const HasilSimpan(
        ok: true,
        terunggah: true,
        pesan: 'Nota dibatalkan.',
      );
    }

    try {
      if (await _rpcBatal(id)) {
        await TransaksiCache.hapus(id);
        return const HasilSimpan(
          ok: true,
          terunggah: true,
          pesan: 'Nota dibatalkan.',
        );
      }
      return const HasilSimpan(
        ok: false,
        terunggah: false,
        pesan:
            'Nota sudah tidak bisa dibatalkan. Muat ulang riwayat, lalu coba lagi.',
      );
    } catch (_) {}

    await TransaksiCache.antre(
      NotaAntri(
        idTransaksi: id,
        idPelanggan: nota.idPelanggan,
        namaPelanggan: nota.namaPelanggan,
        items: antri?.items ?? const [],
        aksi: 'batal',
      ),
    );
    return const HasilSimpan(
      ok: true,
      terunggah: false,
      pesan: 'Pembatalan tersimpan di HP. Akan diunggah saat ada internet.',
    );
  }

  Future<int> kirimTertunda() async {
    final antrian = await TransaksiCache.semua();
    if (antrian.isEmpty) return 0;
    var n = 0;
    for (final nota in antrian) {
      if (nota.idPelanggan.startsWith('TMP')) continue;
      try {
        if (await _kirimSatu(nota)) {
          await TransaksiCache.hapus(nota.idTransaksi);
          n++;
        }
      } catch (e) {
        if (Jaringan.mati(e)) return n;
      }
    }
    return n;
  }

  Future<List<Nota>> untukToko(String idPelanggan) async {
    final id = idPelanggan.trim();
    final cloud = <Nota>[];
    try {
      cloud.addAll(await _unduh(idPelanggan: id, batas: Jaringan.cepat));
      final ids = {for (final n in cloud) n.id};
      for (final antri in await TransaksiCache.untukToko(id)) {
        if (antri.aksi == 'simpan' && ids.contains(antri.idTransaksi)) {
          await TransaksiCache.hapus(antri.idTransaksi);
        }
      }
    } catch (_) {}
    return _gabung(cloud, await TransaksiCache.untukToko(id));
  }

  Future<List<Nota>> untukRentang({
    required DateTime dari,
    required DateTime sampai,
    bool ringkas = false,
  }) async {
    final awal = dari.isUtc ? dari : dari.toUtc();
    final akhir = sampai.isUtc ? sampai : sampai.toUtc();
    var cloud = <Nota>[];
    try {
      cloud = await _unduh(
        dari: awal,
        sampai: akhir,
        kolom: ringkas ? _kolomCapaian : _kolom,
        batas: Jaringan.cepat,
      );
    } catch (_) {}
    final list = _gabung(cloud, await TransaksiCache.semua());
    return [
      for (final n in list)
        if (_diRentang(n.waktuOrder, dari, sampai)) n,
    ];
  }

  Future<TargetSales> targetSaya() async {
    final row = await _sb
        .from('target_sales')
        .select('target_omset, target_persen_laba')
        .maybeSingle()
        .timeout(Jaringan.lambat);
    if (row == null) return TargetSales.kosong;
    return TargetSales(
      omset: (row['target_omset'] as num?)?.round() ?? 0,
      persenLaba: (row['target_persen_laba'] as num?)?.toDouble() ?? 0,
    );
  }

  bool _diRentang(DateTime? waktu, DateTime dari, DateTime sampai) {
    if (waktu == null) return false;
    final lokal = waktu.isUtc ? waktu.toLocal() : waktu;
    final awal = DateTime(dari.year, dari.month, dari.day);
    final akhir = DateTime(sampai.year, sampai.month, sampai.day, 23, 59, 59, 999);
    return !lokal.isBefore(awal) && !lokal.isAfter(akhir);
  }

  Future<List<Nota>> potensiToko(String idPelanggan) async {
    final id = idPelanggan.trim();
    if (id.isEmpty) return [];
    final awal = MingguKunjungan.seninSepuluhMinggu();
    final akhir = MingguKunjungan.minggu();
    return _unduh(
      idPelanggan: id,
      dari: DateTime(awal.year, awal.month, awal.day).toUtc(),
      sampai: DateTime(akhir.year, akhir.month, akhir.day, 23, 59, 59).toUtc(),
      batas: Jaringan.cepat,
    );
  }

  Future<List<BarisNota>> itemNota(String idTransaksi) async {
    final id = idTransaksi.trim();
    if (id.isEmpty) return [];
    final page = await _sb
        .from('transaksi_items')
        .select(_kolomItem)
        .eq('id_transaksi', id)
        .order('nama_barang', ascending: true)
        .range(0, 199)
        .timeout(Jaringan.lambat);
    final list = (page as List)
        .whereType<Map>()
        .map((e) => BarisNota.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.idBarang.isNotEmpty)
        .toList();
    final hitung = BarisNota.isiHargaStrata(list);
    hitung.sort(
      (a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
    );
    return hitung;
  }

  Future<List<Nota>> _unduh({
    String? idPelanggan,
    DateTime? dari,
    DateTime? sampai,
    String kolom = _kolom,
    Duration? batas,
  }) async {
    final tunggu = batas ?? Jaringan.lambat;
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    const ukuran = 200;
    while (from < 2000) {
      final to = from + ukuran - 1;
      var q = _sb.from('transaksi').select(kolom);
      final id = (idPelanggan ?? '').trim();
      if (id.isNotEmpty) {
        q = q.eq('id_pelanggan', id);
      }
      if (dari != null) {
        q = q.gte('waktu_order', dari.toIso8601String());
      }
      if (sampai != null) {
        q = q.lte('waktu_order', sampai.toIso8601String());
      }
      final page = await q
          .order('waktu_order', ascending: false)
          .range(from, to)
          .timeout(tunggu);
      final list = (page as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rows.addAll(list);
      if (list.length < ukuran) break;
      from += ukuran;
    }
    return rows
        .map(Nota.fromJson)
        .where((n) => n.id.isNotEmpty)
        .toList();
  }

  List<Nota> _gabung(List<Nota> cloud, List<NotaAntri> antrian) {
    final map = <String, Nota>{
      for (final n in cloud) n.id: n,
    };
    for (final a in antrian) {
      if (a.aksi == 'simpan' && !map.containsKey(a.idTransaksi)) {
        map[a.idTransaksi] = _dariAntri(a, status: 'diproses', lokal: true);
        continue;
      }
      final cloudNota = map[a.idTransaksi];
      if (cloudNota == null) continue;
      if (!cloudNota.bisaDiubah) continue;
      if (a.aksi == 'ubah') {
        map[a.idTransaksi] = _dariAntri(
          a,
          status: cloudNota.status,
          waktuOrder: cloudNota.waktuOrder,
          rute: cloudNota.rute,
        );
      } else if (a.aksi == 'batal') {
        map[a.idTransaksi] = Nota(
          id: cloudNota.id,
          idPelanggan: cloudNota.idPelanggan,
          namaPelanggan: cloudNota.namaPelanggan,
          rute: cloudNota.rute,
          status: 'batal',
          pending: false,
          waktuOrder: cloudNota.waktuOrder,
          waktuPacked: cloudNota.waktuPacked,
          waktuActual: cloudNota.waktuActual,
          items: cloudNota.items,
          lokal: true,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final aw = a.waktuOrder ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bw = b.waktuOrder ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bw.compareTo(aw);
      });
    return list;
  }

  Nota _dariAntri(
    NotaAntri a, {
    required String status,
    DateTime? waktuOrder,
    String rute = '',
    bool lokal = false,
  }) {
    DateTime? waktu = waktuOrder;
    if (waktu == null) {
      final bagian = a.idTransaksi.split('-');
      final ms = int.tryParse(bagian.isNotEmpty ? bagian.last : '');
      if (ms != null && ms > 0) {
        waktu = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return Nota(
      id: a.idTransaksi,
      idPelanggan: a.idPelanggan,
      namaPelanggan: a.namaPelanggan,
      rute: rute,
      status: status,
      pending: false,
      waktuOrder: waktu,
      items: BarisNota.isiHargaStrata([
        for (final e in a.items)
          BarisNota.fromJson({
            'id_barang': e['id_barang'],
            'nama_barang': e['nama_barang'] ?? e['id_barang'],
            'qty_order': e['qty'],
            'harga_jual': e['harga_jual'],
            'harga_jual_order': e['harga_jual'],
            'harga_beli_order': e['harga_beli'] ?? 0,
          }),
      ]),
      lokal: lokal,
    );
  }

  Future<bool> _kirimSatu(NotaAntri nota) async {
    switch (nota.aksi) {
      case 'ubah':
        return _rpcUbah(nota);
      case 'batal':
        return _rpcBatal(nota.idTransaksi);
      default:
        return _rpcSimpan(nota);
    }
  }

  Future<bool> _rpcSimpan(NotaAntri nota) async {
    final hasil = await _sb
        .rpc(
          'sales_simpan_transaksi',
          params: {
            'p_id_transaksi': nota.idTransaksi,
            'p_id_pelanggan': nota.idPelanggan,
            'p_nama_pelanggan': nota.namaPelanggan,
            'p_items': nota.items,
          },
        )
        .timeout(Jaringan.lambat);
    return hasil == true;
  }

  Future<bool> _rpcUbah(NotaAntri nota) async {
    final hasil = await _sb
        .rpc(
          'sales_ubah_transaksi',
          params: {
            'p_id_transaksi': nota.idTransaksi,
            'p_items': nota.items,
          },
        )
        .timeout(Jaringan.lambat);
    return hasil == true;
  }

  Future<bool> _rpcBatal(String id) async {
    final hasil = await _sb
        .rpc(
          'sales_batal_transaksi',
          params: {'p_id_transaksi': id},
        )
        .timeout(Jaringan.lambat);
    return hasil == true;
  }
}

extension on NotaAntri {
  NotaAntri copyAksi(String aksi) {
    return NotaAntri(
      idTransaksi: idTransaksi,
      idPelanggan: idPelanggan,
      namaPelanggan: namaPelanggan,
      items: items,
      aksi: aksi,
    );
  }
}
