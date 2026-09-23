class BarisMutasi {
  final String? tanggalMutasi;
  final int jumlah;
  final String berita;
  final String rekening;

  const BarisMutasi({
    this.tanggalMutasi,
    required this.jumlah,
    required this.berita,
    required this.rekening,
  });

  Map<String, dynamic> toRpc() => {
    'tanggal_mutasi': tanggalMutasi,
    'jumlah': jumlah,
    'berita': berita,
    'rekening': rekening,
  };
}

class HasilMutasiCsv {
  final List<BarisMutasi> baris;
  final String? error;

  const HasilMutasiCsv(this.baris, [this.error]);
}

/// Parser mutasi bank CSV (bukan workbook harian SETORAN.xlsx).
class MutasiCsv {
  static const _jumlah = {
    'jumlah',
    'amount',
    'kredit',
    'credit',
    'nominal',
    'nilai',
    'transfer',
    'masuk',
    'kreditmutasi',
    'creditamount',
    'transactionamount',
    'nominalkredit',
  };

  static const _debit = {
    'debit',
    'debet',
    'keluar',
    'nominaldebit',
    'nominaldebet',
    'db',
  };

  static const _jenis = {
    'jenis',
    'type',
    'tipe',
    'dc',
    'crdb',
    'mutasi',
    'dk',
  };

  static const _tanggal = {
    'tanggal',
    'date',
    'tgl',
    'waktu',
    'posting',
    'tanggaltransaksi',
    'transactiondate',
    'tgltransaksi',
  };

  static const _berita = {
    'berita',
    'keterangan',
    'deskripsi',
    'remark',
    'narasi',
    'uraian',
    'narrative',
    'description',
    'keterangantransaksi',
  };

  static const _rekening = {
    'rekening',
    'account',
    'norek',
    'norekening',
    'akun',
    'namarekening',
    'accountname',
    'accountno',
  };

  static HasilMutasiCsv parse(String teks) {
    final raw = teks.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (raw.isEmpty) {
      return const HasilMutasiCsv([], 'Berkas CSV kosong.');
    }
    final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) {
      return const HasilMutasiCsv([], 'Berkas CSV kosong.');
    }
    final daftar = [for (final l in lines) _bukaBarisBca(l)];
    String? periodeIso;
    for (final baris in daftar) {
      final p = _periodeDariBaris(baris);
      if (p != null) {
        periodeIso = p;
        break;
      }
    }
    var iHeader = -1;
    var sep = ',';
    List<String> header = const [];
    for (var i = 0; i < daftar.length; i++) {
      final s = _pemisah(daftar[i]);
      final h = _pecah(daftar[i], s).map(_kunci).toList();
      if (_cari(h, _jumlah) != null || _cari(h, _debit) != null) {
        iHeader = i;
        sep = s;
        header = h;
        break;
      }
    }
    if (iHeader < 0) {
      return const HasilMutasiCsv(
        [],
        'Kolom jumlah/kredit tidak ketemu. Pakai header Jumlah, Kredit, atau Nominal.',
      );
    }
    final iJumlah = _cari(header, _jumlah);
    final iDebit = _cari(header, _debit);
    final iTgl = _cari(header, _tanggal);
    final iBerita = _cari(header, _berita);
    final iRek = _cari(header, _rekening);
    final iJenis = _cari(header, _jenis);
    final hasil = <BarisMutasi>[];
    for (var i = iHeader + 1; i < daftar.length; i++) {
      final kol = _pecah(daftar[i], sep);
      if (_bukanBarisData(kol)) continue;
      final sisiJumlah = iJumlah == null
          ? (nilai: 0, debit: false)
          : _uangSisi(_isi(kol, iJumlah));
      if (iJenis != null && _jenisDebit(_isi(kol, iJenis))) continue;
      if (sisiJumlah.debit) continue;
      final kredit = sisiJumlah.nilai;
      final debit = iDebit == null ? 0 : _uangSisi(_isi(kol, iDebit)).nilai;
      if (debit > 0 && kredit <= 0) continue;
      if (kredit < 0) continue;
      final jumlah = kredit;
      if (jumlah <= 0) continue;
      final berita = iBerita == null ? '' : _isi(kol, iBerita);
      if (beritaDebet(berita)) {
        continue;
      }
      final tglTeks = iTgl == null ? '' : _isi(kol, iTgl);
      final rekKolom = iRek == null ? '' : _isi(kol, iRek);
      hasil.add(
        BarisMutasi(
          tanggalMutasi: _tanggalIso(tglTeks) ?? periodeIso,
          jumlah: jumlah,
          berita: berita,
          rekening: rekKolom.isNotEmpty ? rekKolom : namaDariBerita(berita),
        ),
      );
    }
    if (hasil.isEmpty) {
      return const HasilMutasiCsv(
        [],
        'Tidak ada baris kredit yang bisa dibaca.',
      );
    }
    return HasilMutasiCsv(hasil);
  }

  /// Kode rute dari berita. Tanggal di berita wajib = judul setoran + 1,
  /// atau Senin jika judul Sabtu (lewati Minggu).
  static String? ruteDariBerita(String berita, [String? judulIso]) {
    final n = _rapiBerita(berita);
    final m = RegExp(
      r'SBGP\s*0*([1-4])(?!\d)',
      caseSensitive: false,
    ).firstMatch(n);
    if (m == null) return null;
    final rute = 'SBGP0${m.group(1)}';
    if (judulIso == null || judulIso.isEmpty) return rute;
    final tgl = _tanggalSetelahRute(n.substring(m.end));
    if (tgl == null) return null;
    final judul = DateTime.tryParse(judulIso);
    if (judul == null) return null;
    if (tgl != _isoHari(tanggalBeritaDariJudul(judul))) return null;
    return rute;
  }

  /// Tanggal yang harus tertulis di berita: H+1, Senin jika judul Sabtu.
  static DateTime tanggalBeritaDariJudul(DateTime judul) {
    var t = DateTime(judul.year, judul.month, judul.day).add(
      const Duration(days: 1),
    );
    if (t.weekday == DateTime.sunday) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }

  static String _isoHari(DateTime d) {
    final h = d.day.toString().padLeft(2, '0');
    final b = d.month.toString().padLeft(2, '0');
    return '${d.year}-$b-$h';
  }

  /// Nama pengirim di ujung berita BCA (setelah kode bank, SBGP, tanggal).
  static String namaDariBerita(String berita) {
    var t = _rapiBerita(berita);
    t = t.replaceAll(RegExp(r'\b(TRSF|TRANSFER)\s+E-BANKING\s+(CR|DB)\b'), '');
    t = t.replaceAll(RegExp(r'\bBI-FAST(\s+TRSF)?(\s+(CR|DB))?\b'), '');
    t = t.replaceAll(RegExp(r'\b\d{4}/[A-Z0-9]+(?:/[A-Z0-9]+)*\b'), '');
    t = t.replaceAll(RegExp(r'\bSBGP\s*0*[1-4]\b'), '');
    t = t.replaceAll(RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b'), '');
    t = t.replaceAll(
      RegExp(
        r'\b\d{1,2}\s+(JANUARI|FEBRUARI|MARET|APRIL|MEI|JUNI|JULI|AGUSTUS|'
        r'SEPTEMBER|OKTOBER|NOVEMBER|DESEMBER|JAN|FEB|MAR|APR|MAY|JUN|JUL|'
        r'AGU|AGS|AGT|AUG|SEP|SEPT|OKT|OCT|NOV|DES|DEC)\s+\d{2,4}\b',
      ),
      '',
    );
    t = t.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)*\b'), '');
    t = t.replaceAll(RegExp(r'[^A-Z ]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _rapiBerita(String s) {
    var t = s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    const potong = {
      'JANU ARI': 'JANUARI',
      'FEBRU ARI': 'FEBRUARI',
      'SEPTEM BER': 'SEPTEMBER',
      'SEPTEMBE R': 'SEPTEMBER',
      'SEPTEMB ER': 'SEPTEMBER',
      'OKTO BER': 'OKTOBER',
      'OKTOBE R': 'OKTOBER',
      'NOVEM BER': 'NOVEMBER',
      'DESEM BER': 'DESEMBER',
      'AGUS TUS': 'AGUSTUS',
    };
    for (final e in potong.entries) {
      t = t.replaceAll(e.key, e.value);
    }
    t = t.replaceAllMapped(
      RegExp(r'(\d{1,2}[/\-.]\d{1,2}[/\-.])(\d{2,3})\s+(\d{1,2})\b'),
      (m) => '${m[1]}${m[2]}${m[3]}',
    );
    t = t.replaceAllMapped(
      RegExp(
        r'\b(JANUARI|FEBRUARI|MARET|APRIL|MEI|JUNI|JULI|AGUSTUS|SEPTEMBER|'
        r'OKTOBER|NOVEMBER|DESEMBER|JAN|FEB|MAR|APR|MAY|JUN|JUL|AGU|AGS|'
        r'AGT|AUG|SEP|SEPT|OKT|OCT|NOV|DES|DEC)\s+(\d{2})\s+(\d{2})\b',
      ),
      (m) => '${m[1]} ${m[2]}${m[3]}',
    );
    return t;
  }

  /// BCA Corp: seluruh baris dikutip, kolom dalam `""`.
  static String _bukaBarisBca(String line) {
    var t = line.trim();
    if (t.length < 2 || !t.startsWith('"') || !t.endsWith('"')) return t;
    if (!t.contains('""')) return t;
    return t.substring(1, t.length - 1).replaceAll('""', '"');
  }

  static const _bulanNama = {
    'JAN': 1,
    'JANUARI': 1,
    'FEB': 2,
    'FEBRUARI': 2,
    'MAR': 3,
    'MARET': 3,
    'APR': 4,
    'APRIL': 4,
    'MEI': 5,
    'MAY': 5,
    'JUN': 6,
    'JUNI': 6,
    'JUL': 7,
    'JULI': 7,
    'AGU': 8,
    'AGS': 8,
    'AGT': 8,
    'AUG': 8,
    'AGUSTUS': 8,
    'SEP': 9,
    'SEPT': 9,
    'SEPTEMBER': 9,
    'OKT': 10,
    'OCT': 10,
    'OKTOBER': 10,
    'NOV': 11,
    'NOVEMBER': 11,
    'DES': 12,
    'DEC': 12,
    'DESEMBER': 12,
  };

  static String? _tanggalSetelahRute(String sisa) {
    var t = sisa.trim().replaceFirst(RegExp(r'^[\s,./\-]+'), '');
    if (t.isEmpty) return null;
    final angka = RegExp(
      r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})',
    ).firstMatch(t);
    if (angka != null) {
      return _tanggalIso('${angka[1]}/${angka[2]}/${angka[3]}');
    }
    final nama = RegExp(r'^(\d{1,2})\s+([A-Z]+)\s+(\d{2,4})').firstMatch(t);
    if (nama == null) return null;
    final mo = _bulanNama[nama[2]!];
    if (mo == null) return null;
    var y = int.parse(nama[3]!);
    if (y < 100) y += 2000;
    final d = int.parse(nama[1]!);
    if (d < 1 || d > 31) return null;
    return '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  static String _pemisah(String header) {
    final titik = ';'.allMatches(header).length;
    final koma = ','.allMatches(header).length;
    final tab = '\t'.allMatches(header).length;
    if (tab > 0 && tab >= titik && tab >= koma) return '\t';
    if (titik > koma) return ';';
    return ',';
  }

  static List<String> _pecah(String line, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var kutip = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (kutip && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          kutip = !kutip;
        }
      } else if (c == sep && !kutip) {
        out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString().trim());
    return out;
  }

  static String _kunci(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int? _cari(List<String> header, Set<String> nama) {
    for (var i = 0; i < header.length; i++) {
      if (nama.contains(header[i])) return i;
    }
    return null;
  }

  static String _isi(List<String> kol, int i) =>
      i >= 0 && i < kol.length ? kol[i].trim() : '';

  static bool _jenisDebit(String s) {
    final t = s.trim().toUpperCase();
    return t == 'DB' ||
        t == 'D' ||
        t == 'DEBIT' ||
        t == 'DEBET' ||
        t == 'KELUAR' ||
        t == 'DR';
  }

  static final _reDebetBerita = RegExp(
    r'(^|[^A-Z0-9])(DB|DEBET|DEBIT)([^A-Z0-9]|$)',
    caseSensitive: false,
  );

  static bool beritaDebet(String s) => _reDebetBerita.hasMatch(s);

  static final _reSisiUang = RegExp(r'(CR|DB|DR)$', caseSensitive: false);

  static final _reBukanData = RegExp(
    r'^(saldoawal|saldoakhir|mutasidebet|mutasikredit|informasirekening|'
    r'norekening|periode|kodematauang|nama)$',
  );

  static bool _bukanBarisData(List<String> kol) {
    if (kol.isEmpty) return true;
    final kunci = _kunci(kol.first);
    if (kunci.isEmpty) return true;
    if (_reBukanData.hasMatch(kunci)) return true;
    return kunci.startsWith('saldoawal') ||
        kunci.startsWith('saldoakhir') ||
        kunci.startsWith('mutasidebet') ||
        kunci.startsWith('mutasikredit') ||
        kunci.startsWith('informasirekening') ||
        kunci.startsWith('norekening') ||
        kunci.startsWith('periode') ||
        kunci.startsWith('kodematauang');
  }

  static String? _periodeDariBaris(String baris) {
    final m = RegExp(
      r'periode\s*:?\s*(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})',
      caseSensitive: false,
    ).firstMatch(baris);
    if (m == null) return null;
    return _tanggalIso(m.group(1)!);
  }

  static ({int nilai, bool debit}) _uangSisi(String s) {
    if (s.isEmpty) return (nilai: 0, debit: false);
    var t = s.replaceAll(RegExp(r'\s'), '').replaceAll('Rp', '');
    var debit = false;
    final m = _reSisiUang.firstMatch(t);
    if (m != null) {
      final sisi = m.group(1)!.toUpperCase();
      debit = sisi == 'DB' || sisi == 'DR';
      t = t.substring(0, m.start);
    }
    return (nilai: _uangTeks(t), debit: debit);
  }

  static int _uangTeks(String t) {
    if (t.isEmpty) return 0;
    if (t.contains(',') && t.contains('.')) {
      if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
        t = t.replaceAll('.', '').replaceAll(',', '.');
      } else {
        t = t.replaceAll(',', '');
      }
    } else if (RegExp(r',\d{1,2}$').hasMatch(t)) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
      t = t.replaceAll('.', '');
    }
    final n = num.tryParse(t);
    if (n != null) {
      if (n < 0) return 0;
      return n.round();
    }
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static String? _tanggalIso(String s) {
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) {
      return '${iso.year.toString().padLeft(4, '0')}-'
          '${iso.month.toString().padLeft(2, '0')}-'
          '${iso.day.toString().padLeft(2, '0')}';
    }
    final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(s);
    if (m != null) {
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      return '${y.toString().padLeft(4, '0')}-'
          '${mo.toString().padLeft(2, '0')}-'
          '${d.toString().padLeft(2, '0')}';
    }
    final m2 = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})$').firstMatch(s);
    if (m2 != null) {
      final d = int.parse(m2.group(1)!);
      final mo = int.parse(m2.group(2)!);
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      final y = DateTime.now().year;
      return '$y-'
          '${mo.toString().padLeft(2, '0')}-'
          '${d.toString().padLeft(2, '0')}';
    }
    return null;
  }
}
