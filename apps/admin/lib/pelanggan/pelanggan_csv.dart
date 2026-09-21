import 'pelanggan.dart';

class BarisCsvPelanggan {
  const BarisCsvPelanggan({
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

  factory BarisCsvPelanggan.fromJson(Map<String, dynamic> json) {
    return BarisCsvPelanggan(
      baris: (json['baris'] as num?)?.toInt() ?? 0,
      id: json['id_pelanggan']?.toString() ?? '',
      aksi: json['aksi']?.toString() ?? '',
      ok: json['ok'] == true,
      pesan: json['pesan']?.toString() ?? '',
    );
  }
}

class PelangganCsv {
  static const pemisah = ';';

  static const kepala = [
    'id',
    'nama',
    'rute',
    'visit',
    'urutan',
    'latitude',
    'longitude',
    'aktif',
    'hapus',
  ];

  static String template() {
    return _tulis(kepala, [
      [
        'SBGO0001',
        'TOKO CONTOH',
        'SBGS01',
        'Senin',
        '1',
        '-6.9',
        '107.6',
        '1',
        '',
      ],
    ]);
  }

  static String dariDaftar(List<Pelanggan> daftar) {
    return _tulis(kepala, [
      for (final p in daftar)
        [
          p.id,
          p.nama,
          p.rute,
          p.visit,
          '${p.urutan}',
          p.latitude == null ? '' : '${p.latitude}',
          p.longitude == null ? '' : '${p.longitude}',
          p.aktif ? '1' : '0',
          '',
        ],
    ]);
  }

  static List<Map<String, dynamic>> baca(String teks) {
    final tabel = _baca(teks);
    if (tabel.isEmpty) return [];
    final kepala = tabel.first.map(_kunci).toList();
    final keluar = <Map<String, dynamic>>[];
    for (var i = 1; i < tabel.length; i++) {
      final row = _peta(kepala, tabel[i]);
      final id = _isi(row, const [
        'id',
        'id_pelanggan',
        'idpelanggan',
        'kode',
      ]);
      if (id.isEmpty) continue;
      final aktifTeks = row['aktif']?.trim() ?? '';
      final ruteTeks = _isi(row, const ['rute']);
      final visitTeks = _isi(row, const ['visit', 'hari']);
      final urutanTeks = _isi(row, const ['urutan']);
      final latTeks = _isi(row, const ['latitude', 'lat']);
      final lngTeks = _isi(row, const ['longitude', 'lng', 'lon']);
      final nama = _isi(row, const ['nama', 'nama_pelanggan', 'namapelanggan', 'toko']);
      keluar.add({
        'id_pelanggan': id,
        if (nama.isNotEmpty) 'nama_pelanggan': nama,
        if (ruteTeks.isNotEmpty) 'rute': ruteTeks,
        if (visitTeks.isNotEmpty) 'visit': visitTeks,
        if (urutanTeks.isNotEmpty) 'urutan': int.tryParse(urutanTeks) ?? 0,
        if (latTeks.isNotEmpty)
          'latitude': double.tryParse(latTeks.replaceAll(',', '.')),
        if (lngTeks.isNotEmpty)
          'longitude': double.tryParse(lngTeks.replaceAll(',', '.')),
        if (aktifTeks.isNotEmpty) 'aktif': _ya(aktifTeks),
        'hapus': _ya(row['hapus'] ?? ''),
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

  static String _sel(String s) {
    if (s.contains(pemisah) || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static List<List<String>> _baca(String teks) {
    var t = teks.replaceFirst(RegExp(r'^\uFEFF'), '');
    t = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (t.trim().isEmpty) return [];
    final baris1 =
        t.split('\n').firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
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

  static Map<String, String> _peta(List<String> kepala, List<String> row) {
    final m = <String, String>{};
    for (var i = 0; i < kepala.length; i++) {
      m[kepala[i]] = i < row.length ? row[i].trim() : '';
    }
    return m;
  }

  static String _kunci(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static String _isi(Map<String, String> row, List<String> nama) {
    for (final n in nama) {
      final v = row[n];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static bool _ya(String s) {
    final t = s.trim().toLowerCase();
    return t == '1' || t == 'ya' || t == 'true' || t == 'y' || t == 'hapus';
  }
}
