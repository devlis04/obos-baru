import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../csv_unduh.dart';
import '../rumus_sederhana.dart';

export '../csv_unduh.dart' show unduhBerkasCsv;

class NamaPecah {
  const NamaPecah({
    required this.nama,
    required this.satuan,
    required this.rincian,
  });

  final String nama;
  final String satuan;
  final String rincian;
}

class BarisCsvMasuk {
  const BarisCsvMasuk({
    this.idBarang,
    required this.nama,
    this.satuan = '',
    this.rincian = '',
    this.kategori = '',
    required this.hargaBeli,
    this.qty,
  });

  final String? idBarang;
  final String nama;
  final String satuan;
  final String rincian;
  final String kategori;
  final num hargaBeli;
  final num? qty;
}

const csvJudulMasuk =
    'id_barang,nama,satuan,rincian,kategori,harga_beli,qty';

NamaPecah pecahNamaBarang(String namaBarang) {
  final s = namaBarang.trim();
  final i = s.indexOf(' /');
  if (i < 0) return NamaPecah(nama: s, satuan: '', rincian: '');
  final dasar = s.substring(0, i).trim();
  final sisa = s.substring(i + 2).trim();
  final j = sisa.indexOf('/');
  if (j < 0) return NamaPecah(nama: dasar, satuan: sisa, rincian: '');
  return NamaPecah(
    nama: dasar,
    satuan: sisa.substring(0, j).trim(),
    rincian: sisa.substring(j + 1).trim(),
  );
}

String csvDariBaris(List<BarisCsvMasuk> baris) {
  return csvTulis(
    csvJudulMasuk.split(','),
    [
      for (final b in baris)
        [
          b.idBarang ?? '',
          b.nama,
          b.satuan,
          b.rincian,
          b.kategori,
          _angka(b.hargaBeli),
          b.qty == null || b.qty! <= 0 ? '' : _angka(b.qty!),
        ],
    ],
  );
}

List<BarisCsvMasuk> barisDariCsv(String teks) {
  var s = teks.replaceFirst(RegExp(r'^\uFEFF'), '');
  final lines = s
      .split(RegExp(r'\r\n|\n|\r'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.toLowerCase().startsWith('sep='))
      .toList();
  if (lines.isEmpty) return const [];
  var sep = ',';
  var kepala = pecahCsv(lines.first, sep).map(_kunci).toList();
  var iId = _idx(kepala, const ['id_barang', 'kode', 'kode_barang']);
  var iQty = _idx(kepala, const ['qty', 'jumlah']);
  if (iId < 0 || iQty < 0) {
    final cadangan = pecahCsv(lines.first, ';').map(_kunci).toList();
    final idTitik = _idx(cadangan, const ['id_barang', 'kode', 'kode_barang']);
    final qtyTitik = _idx(cadangan, const ['qty', 'jumlah']);
    if (idTitik >= 0 && qtyTitik >= 0) {
      sep = ';';
      kepala = cadangan;
      iId = idTitik;
      iQty = qtyTitik;
    }
  }
  final iNama = _idx(kepala, const ['nama', 'nama_barang']);
  final iSatuan = _idx(kepala, const ['satuan']);
  final iRincian = _idx(kepala, const ['rincian']);
  final iKategori = _idx(kepala, const ['kategori']);
  final iHarga = _idx(kepala, const ['harga_beli', 'harga', 'modal']);
  if (iId < 0) {
    throw const FormatException('CSV wajib kolom id_barang.');
  }
  if (iQty < 0) {
    throw const FormatException('CSV wajib kolom qty.');
  }
  final mulai = _judul(kepala) ? 1 : 0;
  final out = <BarisCsvMasuk>[];
  for (var i = mulai; i < lines.length; i++) {
    final kol = pecahCsv(lines[i], sep);
    String ambil(int i) => i >= 0 && i < kol.length ? kol[i].trim() : '';
    final qtyTeks = ambil(iQty);
    final qty = qtyTeks.isEmpty ? null : nilaiDariRumus(qtyTeks);
    if (qty == null || qty <= 0) continue;
    final id = ambil(iId);
    if (id.isEmpty) continue;
    final hargaTeks = ambil(iHarga);
    final harga = hargaTeks.isEmpty ? 0 : (nilaiDariRumus(hargaTeks) ?? 0);
    out.add(
      BarisCsvMasuk(
        idBarang: id,
        nama: ambil(iNama),
        satuan: ambil(iSatuan),
        rincian: ambil(iRincian),
        kategori: ambil(iKategori),
        hargaBeli: harga,
        qty: qty,
      ),
    );
  }
  return out;
}

Future<String?> pilihBerkasCsv() {
  final selesai = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,text/csv'
    ..style.display = 'none';
  web.document.body?.appendChild(input);
  var tutup = false;
  void done(String? v) {
    if (tutup) return;
    tutup = true;
    input.remove();
    if (!selesai.isCompleted) selesai.complete(v);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final files = input.files;
      if (files == null || files.length < 1) {
        done(null);
        return;
      }
      final file = files.item(0);
      if (file == null) {
        done(null);
        return;
      }
      final baca = web.FileReader();
      baca.addEventListener(
        'load',
        (web.Event _) {
          final r = baca.result;
          if (r == null) {
            done(null);
            return;
          }
          done((r as JSString).toDart);
        }.toJS,
      );
      baca.addEventListener(
        'error',
        (web.Event _) {
          done(null);
        }.toJS,
      );
      baca.readAsText(file, 'UTF-8');
    }.toJS,
  );
  input.click();
  return selesai.future;
}

List<String> pecahCsv(String baris, String sep) {
  final out = <String>[];
  final buf = StringBuffer();
  var kutip = false;
  for (var i = 0; i < baris.length; i++) {
    final c = baris[i];
    if (kutip) {
      if (c == '"') {
        if (i + 1 < baris.length && baris[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          kutip = false;
        }
      } else {
        buf.write(c);
      }
    } else if (c == '"') {
      kutip = true;
    } else if (c == sep) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}

bool _judul(List<String> kepala) {
  return kepala.any(
    (k) =>
        k == 'id_barang' ||
        k == 'nama' ||
        k == 'qty' ||
        k == 'harga_beli',
  );
}

int _idx(List<String> kepala, List<String> nama) {
  for (final n in nama) {
    final i = kepala.indexOf(n);
    if (i >= 0) return i;
  }
  return -1;
}

String _kunci(String s) => s.trim().toLowerCase().replaceAll(' ', '_');

String _angka(num n) {
  if (n == n.roundToDouble()) return '${n.round()}';
  return n
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
