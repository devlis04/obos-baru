import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:obos_core/obos_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'barang/barang.dart';
import 'nota/transaksi_helper.dart';
import 'umpan.dart';

class PrinterThermal {
  static const _macKey = 'thermal_printer_mac';
  static const _namaPerusahaan = 'Alhan Berkah Makmur';
  static const _telepon = '081394223303';

  static img.Image? _kopBitmap;

  static bool get bisaCetakPerangkat {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<String?> _macTersimpan() async {
    final mac = (await PrefsHp.getString(_macKey))?.trim() ?? '';
    return mac.isEmpty ? null : mac;
  }

  static Future<void> cetakUlangUi({
    required BuildContext context,
    required String namaToko,
    required String namaSales,
    DateTime? tanggalNota,
    required Map<String, int> keranjangQty,
    required List<Barang> daftarBarang,
  }) async {
    if (!bisaCetakPerangkat) {
      umpan(context, 'Cetak thermal hanya di HP Android.');
      return;
    }
    final printerOk = await pastikanTerhubung(context);
    if (!printerOk || !context.mounted) return;
    final cetak = await cetakNota(
      namaToko: namaToko,
      namaSales: namaSales,
      tanggalNota: tanggalNota,
      keranjangQty: keranjangQty,
      daftarBarang: daftarBarang,
    );
    if (!context.mounted) return;
    umpan(
      context,
      cetak
          ? 'Nota dicetak.'
          : 'Cetak gagal. Periksa printer, lalu coba lagi.',
    );
  }

  static Future<void> _simpanMac(String mac) async {
    await PrefsHp.setString(_macKey, mac);
  }

  static Future<bool> _mintaIzin() async {
    if (!bisaCetakPerangkat) return false;
    if (!Platform.isAndroid) return true;
    final connect = await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    if (connect.isGranted) return true;
    return PrintBluetoothThermal.isPermissionBluetoothGranted;
  }

  static Future<String?> _pilihPrinter(BuildContext context) async {
    final daftar = await PrintBluetoothThermal.pairedBluetooths;
    if (!context.mounted) return null;
    if (daftar.isEmpty) {
      umpan(
        context,
        'Belum ada printer Bluetooth yang terhubung. Pairing dulu di pengaturan HP, lalu coba lagi.',
      );
      return null;
    }

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Pilih printer thermal',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Pilih perangkat yang sudah di-pairing.'),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: daftar.length,
                    itemBuilder: (context, i) {
                      final p = daftar[i];
                      return ListTile(
                        leading: const Icon(Icons.print_outlined),
                        title: Text(
                          p.name.trim().isEmpty ? 'Printer' : p.name,
                        ),
                        subtitle: Text(p.macAdress),
                        onTap: () => Navigator.pop(ctx, p.macAdress),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<bool> pastikanTerhubung(BuildContext context) async {
    if (!bisaCetakPerangkat) {
      umpan(context, 'Cetak nota hanya tersedia di HP Android.');
      return false;
    }

    final izin = await _mintaIzin();
    if (!izin) {
      if (context.mounted) {
        umpan(
          context,
          'Izin Bluetooth belum diberikan. Buka pengaturan aplikasi, lalu izinkan Bluetooth.',
        );
      }
      return false;
    }

    final nyala = await PrintBluetoothThermal.bluetoothEnabled;
    if (!nyala) {
      if (context.mounted) {
        umpan(
          context,
          'Bluetooth HP masih mati. Nyalakan dulu, lalu coba lagi.',
        );
      }
      return false;
    }

    final sudah = await PrintBluetoothThermal.connectionStatus;
    if (sudah) return true;

    var mac = await _macTersimpan();
    if (mac == null) {
      if (!context.mounted) return false;
      mac = await _pilihPrinter(context);
      if (mac == null || mac.isEmpty) return false;
      await _simpanMac(mac);
    }

    var ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (ok) return true;

    if (!context.mounted) return false;
    umpan(
      context,
      'Printer tersimpan tidak terhubung. Pilih printer lain.',
    );
    final lain = await _pilihPrinter(context);
    if (lain == null || lain.isEmpty) return false;
    await _simpanMac(lain);
    ok = await PrintBluetoothThermal.connect(macPrinterAddress: lain);
    if (!ok && context.mounted) {
      umpan(
        context,
        'Gagal terhubung ke printer. Periksa daya dan pairing.',
      );
    }
    return ok;
  }

  static Future<img.Image?> _kopStruk() async {
    if (_kopBitmap != null) return _kopBitmap;
    try {
      final data = await rootBundle.load('assets/logo.jpg');
      final decoded = img.decodeImage(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (decoded == null) return null;
      _kopBitmap = img.copyResize(decoded, width: 570, height: 135);
      return _kopBitmap;
    } catch (_) {
      return null;
    }
  }

  static String _angka(int nominal) {
    return nominal.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }

  static String _tgl(DateTime? w) {
    final d = (w ?? DateTime.now()).toLocal();
    final h = d.day.toString().padLeft(2, '0');
    final b = d.month.toString().padLeft(2, '0');
    return '$h-$b-${d.year}';
  }

  static const _hurufBiasa = PosStyles(
    height: PosTextSize.size1,
    width: PosTextSize.size1,
  );
  static const _hurufTebal = PosStyles(
    bold: true,
    height: PosTextSize.size1,
    width: PosTextSize.size1,
  );
  static const _hurufTokoTotal = PosStyles(
    bold: true,
    height: PosTextSize.size2,
    width: PosTextSize.size2,
  );

  static Future<bool> cetakNota({
    required String namaToko,
    required String namaSales,
    DateTime? tanggalNota,
    required Map<String, int> keranjangQty,
    required List<Barang> daftarBarang,
  }) async {
    if (!bisaCetakPerangkat) return false;
    final terhubung = await PrintBluetoothThermal.connectionStatus;
    if (!terhubung) return false;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    final List<int> bytes = [];
    bytes.addAll(generator.reset());

    final tgl = _tgl(tanggalNota);
    final toko = namaToko.trim();
    final sales = namaSales.trim().isEmpty ? '-' : namaSales.trim();

    final kop = await _kopStruk();
    if (kop != null) {
      bytes.addAll(generator.image(kop, align: PosAlign.center));
    } else {
      bytes.addAll(generator.text(_namaPerusahaan, styles: _hurufTebal));
      bytes.addAll(generator.text('Phone : $_telepon', styles: _hurufBiasa));
    }
    bytes.addAll(generator.text('------------------------------------------------'));
    bytes.addAll(
      generator.row([
        PosColumn(
          text: sales,
          width: 6,
          styles: const PosStyles(
            align: PosAlign.left,
            bold: true,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
        ),
        PosColumn(
          text: tgl,
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
        ),
      ]),
    );
    bytes.addAll(generator.text('------------------------------------------------'));
    bytes.addAll(generator.text(toko, styles: _hurufTokoTotal));
    bytes.addAll(generator.text('------------------------------------------------'));
    bytes.addAll(generator.feed(1));

    final barisCetak = daftarBarang.where((b) {
      return (keranjangQty[b.id] ?? 0) > 0;
    }).toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));

    for (final barang in barisCetak) {
      final qty = keranjangQty[barang.id] ?? 0;
      final harga = TransaksiHelper.hargaJual(
        barang: barang,
        keranjang: keranjangQty,
        daftar: daftarBarang,
      );
      final sub = harga * qty;
      bytes.addAll(generator.text(barang.nama, styles: _hurufBiasa));
      bytes.addAll(
        generator.row([
          PosColumn(
            text: '$qty',
            width: 1,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: 'x',
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: 'Rp',
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: _angka(harga),
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: 'Rp',
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: _angka(sub),
            width: 3,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
      bytes.addAll(generator.feed(1));
    }

    bytes.addAll(generator.text('------------------------------------------------'));
    final total = TransaksiHelper.totalNota(
      keranjang: keranjangQty,
      daftar: daftarBarang,
    );
    bytes.addAll(
      generator.text(
        'Total: Rp ${_angka(total)}',
        styles: _hurufTokoTotal,
      ),
    );
    bytes.addAll(generator.text('------------------------------------------------'));
    bytes.addAll(generator.feed(2));

    return PrintBluetoothThermal.writeBytes(bytes);
  }
}
