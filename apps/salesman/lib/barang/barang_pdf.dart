import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'barang.dart';

class BarangPdf {
  static const _headerTabel = pw.BoxDecoration(color: PdfColors.blueGrey800);
  static const _barisGenap = pw.BoxDecoration(color: PdfColors.white);
  static const _barisGanjil = pw.BoxDecoration(color: PdfColors.blueGrey50);
  static final _garisTabel = pw.TableBorder.all(
    color: PdfColors.blueGrey200,
    width: 0.4,
  );

  static Future<void> bagikanHarga(List<Barang> daftar) async {
    final bytes = await _dokumenHarga(daftar);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'daftar_harga_barang_${_stempel(DateTime.now())}.pdf',
    );
  }

  static Future<void> bagikanStok(List<Barang> daftar) async {
    final bytes = await _dokumenStok(daftar);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'daftar_stok_barang_${_stempel(DateTime.now())}.pdf',
    );
  }

  static Future<Uint8List> _dokumenHarga(List<Barang> daftar) async {
    final dokumen = pw.Document();
    final urut = List<Barang>.from(daftar)
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    final header = [
      'Id grup',
      'Nama barang',
      'Harga jual',
      'Min 1',
      'Jual 1',
      'Min 2',
      'Jual 2',
      'Min 3',
      'Jual 3',
      'Min 4',
      'Jual 4',
      'Min 5',
      'Jual 5',
    ];
    final rows = urut.map((item) {
      return [
        item.idGrup,
        item.nama,
        _angka(item.hargaJual),
        _strataMin(item.minStrat1),
        _strataJual(item.minStrat1, item.jualStrat1),
        _strataMin(item.minStrat2),
        _strataJual(item.minStrat2, item.jualStrat2),
        _strataMin(item.minStrat3),
        _strataJual(item.minStrat3, item.jualStrat3),
        _strataMin(item.minStrat4),
        _strataJual(item.minStrat4, item.jualStrat4),
        _strataMin(item.minStrat5),
        _strataJual(item.minStrat5, item.jualStrat5),
      ];
    }).toList();

    dokumen.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Daftar harga barang',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Dicetak ${_cetak(DateTime.now())} • ${urut.length} item',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: header,
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: _headerTabel,
            oddRowDecoration: _barisGanjil,
            rowDecoration: _barisGenap,
            border: _garisTabel,
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 3,
            ),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
              10: pw.Alignment.centerRight,
              11: pw.Alignment.centerRight,
              12: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(1.1),
              1: const pw.FlexColumnWidth(2.8),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(0.7),
              4: const pw.FlexColumnWidth(1.0),
              5: const pw.FlexColumnWidth(0.7),
              6: const pw.FlexColumnWidth(1.0),
              7: const pw.FlexColumnWidth(0.7),
              8: const pw.FlexColumnWidth(1.0),
              9: const pw.FlexColumnWidth(0.7),
              10: const pw.FlexColumnWidth(1.0),
              11: const pw.FlexColumnWidth(0.7),
              12: const pw.FlexColumnWidth(1.0),
            },
          ),
        ],
      ),
    );
    return dokumen.save();
  }

  static Future<Uint8List> _dokumenStok(List<Barang> daftar) async {
    final dokumen = pw.Document();
    final urut = List<Barang>.from(daftar)
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    final rows = urut.map((item) => [item.nama, _qty(item.stok)]).toList();

    dokumen.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Daftar stok barang',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Dicetak ${_cetak(DateTime.now())} • ${urut.length} item',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Nama barang', 'Stok'],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: _headerTabel,
            oddRowDecoration: _barisGanjil,
            rowDecoration: _barisGenap,
            border: _garisTabel,
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 3,
            ),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(4.2),
              1: const pw.FlexColumnWidth(1.0),
            },
          ),
        ],
      ),
    );
    return dokumen.save();
  }

  static String _qty(num n) {
    if (n == n.roundToDouble()) return '${n.round()}';
    return n
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  static String _angka(int nilai) {
    return nilai.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  static String _strataMin(int min) => min > 0 ? '$min' : '-';

  static String _strataJual(int min, int jual) {
    if (min <= 0 || jual <= 0) return '-';
    return _angka(jual);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _stempel(DateTime w) {
    return '${w.year}${_pad(w.month)}${_pad(w.day)}_${_pad(w.hour)}${_pad(w.minute)}';
  }

  static String _cetak(DateTime w) {
    return '${w.day}/${_pad(w.month)}/${w.year} ${_pad(w.hour)}:${_pad(w.minute)}';
  }
}
