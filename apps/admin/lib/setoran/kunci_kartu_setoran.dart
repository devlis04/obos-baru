import 'dart:async';
import 'dart:convert';

import '../uang.dart';

/// Kunci chip setoran: `b{id}|…` atau `YYYY-MM-DD|…`.
String? kunciKartuBuku(
  String k, {
  int? idBuku,
  DateTime? tanggal,
}) {
  if (idBuku == null) return k;
  if (k.startsWith('b$idBuku|')) return k;
  if (RegExp(r'^b\d+\|').hasMatch(k)) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}\|').hasMatch(k)) {
    final tgl = tanggal == null ? null : Uang.isoHari(tanggal);
    if (tgl != null && !k.startsWith('$tgl|')) return null;
    return 'b$idBuku|${k.substring(11)}';
  }
  return 'b$idBuku|$k';
}

bool flagKartu(Object? v) {
  if (v == true || v == 1) return true;
  final s = v?.toString().toLowerCase().trim();
  return s == 'true' || s == 't' || s == '1';
}

Map<String, dynamic>? petaChip(Object? raw) {
  Object? v = raw;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    try {
      v = jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Centang disimpan ke foto buku tanpa menunggu tombol Simpan.
class ChipSetoranPersist {
  ChipSetoranPersist._();
  static final ChipSetoranPersist instance = ChipSetoranPersist._();

  Future<void> Function()? _simpan;
  Timer? _tunda;
  bool _diam = false;

  void atur(Future<void> Function()? simpan) {
    _simpan = simpan;
  }

  void diam(bool v) => _diam = v;

  void minta() {
    if (_simpan == null) return;
    _tunda?.cancel();
    _tunda = Timer(const Duration(milliseconds: 600), () {
      final fn = _simpan;
      if (fn == null) return;
      if (_diam) {
        minta();
        return;
      }
      unawaited(fn());
    });
  }

  void batal() {
    _tunda?.cancel();
    _tunda = null;
  }
}
