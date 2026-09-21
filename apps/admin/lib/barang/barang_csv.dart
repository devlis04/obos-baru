import '../uang.dart';
import 'barang.dart';

class BarisCsv {
  const BarisCsv({
    required this.baris,
    required this.id,
    required this.aksi,
    required this.ok,
    required this.pesan,
  });

  final int baris;
  final String id;
  final String aksi;
  final bool ok;
  final String pesan;

  factory BarisCsv.fromJson(Map<String, dynamic> json) {
    return BarisCsv(
      baris: (json['baris'] as num?)?.toInt() ?? 0,
      id: json['id_barang']?.toString() ?? '',
      aksi: json['aksi']?.toString() ?? '',
      ok: json['ok'] == true,
      pesan: json['pesan']?.toString() ?? '',
    );
  }
}

class BarangCsv {
  static const pemisah = ';';

  static const kepalaBarang = [
    'id',
    'grup',
    'nama',
    'satuan',
    'rincian',
    'kategori',
    'id_supplier_utama',
    'harga_beli',
    'harga_jual',
    'pengurang',
    'min_1',
    'min_2',
    'min_3',
    'min_4',
    'min_5',
    'aktif',
    'hapus',
  ];

  static const kepalaStok = ['id', 'nama', 'stok'];

  static String templateBarang() {
    return _tulis(kepalaBarang, [
      [
        'BR001',
        '',
        'Nama contoh',
        'box',
        '10lbr',
        'Kategori',
        '',
        '100000',
        '109500',
        '1500',
        '12',
        '24',
        '',
        '',
        '',
        '1',
        '',
      ],
    ]);
  }

  static String templateStok() {
    return _tulis(kepalaStok, [
      ['BR001', 'Nama contoh /box/10lbr', '1.5'],
    ]);
  }

  static String dariBarang(List<Barang> daftar) {
    final isi = <List<String>>[];
    for (final b in daftar) {
      final pecah = Barang.pecahNama(b.nama);
      isi.add([
        b.id,
        b.idGrup,
        pecah.nama,
        pecah.satuan,
        pecah.rincian,
        b.kategori,
        b.idSupplierUtama == 0 ? '' : '${b.idSupplierUtama}',
        '${b.hargaBeli}',
        '${b.hargaJual}',
        b.pengurangStrata == 0 ? '' : '${b.pengurangStrata}',
        b.minStrat1 == 0 ? '' : '${b.minStrat1}',
        b.minStrat2 == 0 ? '' : '${b.minStrat2}',
        b.minStrat3 == 0 ? '' : '${b.minStrat3}',
        b.minStrat4 == 0 ? '' : '${b.minStrat4}',
        b.minStrat5 == 0 ? '' : '${b.minStrat5}',
        b.aktif ? '1' : '0',
        '',
      ]);
    }
    return _tulis(kepalaBarang, isi);
  }

  static String dariStok(List<Barang> daftar) {
    return _tulis(kepalaStok, [
      for (final b in daftar) [b.id, b.nama, Uang.qtyCsv(b.stok)],
    ]);
  }

  static List<Map<String, dynamic>> bacaBarang(String teks) {
    final tabel = _baca(teks);
    if (tabel.isEmpty) return [];
    final kepala = tabel.first.map(_kunci).toList();
    final keluar = <Map<String, dynamic>>[];
    for (var i = 1; i < tabel.length; i++) {
      final row = _peta(kepala, tabel[i]);
      final id = _isi(row, const ['id', 'id_barang']);
      if (id.isEmpty) continue;
      final hapus = _ya(row['hapus'] ?? '');
      final punyaUtama = kepala.contains('id_supplier_utama') ||
          kepala.contains('pemasok_utama') ||
          kepala.contains('supplier_utama');
      final utamaTeks = _isi(row, const [
        'id_supplier_utama',
        'pemasok_utama',
        'supplier_utama',
      ]);
      final aktifTeks = row['aktif']?.trim() ?? '';
      keluar.add({
        'id_barang': id,
        'id_grup': _isi(row, const ['grup', 'id_grup']),
        'nama': _isi(row, const ['nama', 'nama_barang']),
        'satuan': _isi(row, const ['satuan']),
        'rincian': _isi(row, const ['rincian']),
        'kategori': _isi(row, const ['kategori']),
        if (punyaUtama && utamaTeks.isNotEmpty)
          'id_supplier_utama': _angka(utamaTeks),
        'harga_beli': _angka(row['harga_beli'] ?? row['beli'] ?? ''),
        'harga_jual': _angka(row['harga_jual'] ?? row['jual'] ?? ''),
        'pengurang_strata': _angka(
          row['pengurang'] ?? row['pengurang_strata'] ?? '',
        ),
        'min_strat_1': _angka(row['min_1'] ?? row['min_strat_1'] ?? ''),
        'min_strat_2': _angka(row['min_2'] ?? row['min_strat_2'] ?? ''),
        'min_strat_3': _angka(row['min_3'] ?? row['min_strat_3'] ?? ''),
        'min_strat_4': _angka(row['min_4'] ?? row['min_strat_4'] ?? ''),
        'min_strat_5': _angka(row['min_5'] ?? row['min_strat_5'] ?? ''),
        if (aktifTeks.isNotEmpty) 'aktif': _ya(aktifTeks),
        'hapus': hapus,
      });
    }
    return keluar;
  }

  static List<Map<String, dynamic>> bacaStok(String teks) {
    final tabel = _baca(teks);
    if (tabel.isEmpty) return [];
    final kepala = tabel.first.map(_kunci).toList();
    final keluar = <Map<String, dynamic>>[];
    for (var i = 1; i < tabel.length; i++) {
      final row = _peta(kepala, tabel[i]);
      final id = _isi(row, const ['id', 'id_barang']);
      if (id.isEmpty) continue;
      keluar.add({
        'id_barang': id,
        'stok': _stokCsv(row['stok'] ?? ''),
      });
    }
    return keluar;
  }

  static String _tulis(List<String> kepala, List<List<String>> isi) {
    final buf = StringBuffer();
    buf.writeln(kepala.map(_sel).join(pemisah));
    for (final row in isi) {
      buf.writeln(row.map(_sel).join(pemisah));
    }
    return buf.toString();
  }

  static String _sel(String v) {
    if (v.contains(pemisah) || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static List<List<String>> _baca(String mentah) {
    var t = mentah;
    if (t.startsWith('\uFEFF')) t = t.substring(1);
    t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (t.trim().isEmpty) return [];
    final baris1 = t.split('\n').firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    final sep = _hitung(baris1, ';') >= _hitung(baris1, ',') ? ';' : ',';
    return _pecah(t, sep);
  }

  static int _hitung(String s, String c) => c.allMatches(s).length;

  static List<List<String>> _pecah(String t, String sep) {
    final keluar = <List<String>>[];
    var row = <String>[];
    final sel = StringBuffer();
    var kutip = false;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (kutip) {
        if (ch == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            sel.write('"');
            i++;
          } else {
            kutip = false;
          }
        } else {
          sel.write(ch);
        }
      } else if (ch == '"') {
        kutip = true;
      } else if (ch == sep) {
        row.add(sel.toString());
        sel.clear();
      } else if (ch == '\n') {
        row.add(sel.toString());
        sel.clear();
        if (row.any((e) => e.trim().isNotEmpty)) keluar.add(row);
        row = [];
      } else {
        sel.write(ch);
      }
    }
    row.add(sel.toString());
    if (row.any((e) => e.trim().isNotEmpty)) keluar.add(row);
    return keluar;
  }

  static String _kunci(String s) => s.trim().toLowerCase().replaceAll(' ', '_');

  static num _stokCsv(String teks) {
    final n = Uang.qtyTeks(teks);
    return (n * 10000).round() / 10000;
  }

  static Map<String, String> _peta(List<String> kepala, List<String> row) {
    final m = <String, String>{};
    for (var i = 0; i < kepala.length; i++) {
      m[kepala[i]] = i < row.length ? row[i].trim() : '';
    }
    return m;
  }

  static String _isi(Map<String, String> row, List<String> kunci) {
    for (final k in kunci) {
      final v = row[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static int _angka(String s) {
    final t = s.trim().replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(t) ?? 0;
  }

  static bool _ya(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return false;
    return t == '1' ||
        t == 'ya' ||
        t == 'y' ||
        t == 'true' ||
        t == 't' ||
        t == 'aktif' ||
        t == 'hapus';
  }
}
