import 'package:flutter/services.dart';

class Uang {
  static int dari(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String isoHari(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final b = d.month.toString().padLeft(2, '0');
    final h = d.day.toString().padLeft(2, '0');
    return '$y-$b-$h';
  }

  static DateTime? hariDari(Object? v) {
    final s = v?.toString() ?? '';
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
  }

  static String angka(int nominal) {
    final tanda = nominal < 0 ? '-' : '';
    final n = nominal.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return '$tanda$n';
  }

  static String rp(int nominal) => 'Rp ${angka(nominal)}';

  static int angkaTeks(String s) {
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static String qty(num n) {
    if (n == n.roundToDouble()) return '${n.round()}';
    return n
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  static String qtyCsv(num n) {
    if (n == n.roundToDouble()) return '${n.round()}';
    return n
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static num qtyTeks(String s) {
    var t = s.trim().replaceAll(' ', '');
    if (t.isEmpty) return 0;
    if (t.contains(',') && t.contains('.')) {
      if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
        t = t.replaceAll('.', '').replaceAll(',', '.');
      } else {
        t = t.replaceAll(',', '');
      }
    } else if (t.contains(',')) {
      t = t.replaceAll(',', '.');
    }
    return num.tryParse(t) ?? 0;
  }

  static String tanggal(DateTime d) {
    final h = d.day.toString().padLeft(2, '0');
    final b = d.month.toString().padLeft(2, '0');
    return '$h/$b/${d.year}';
  }

  static const _hari = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static String hari(DateTime d) => _hari[d.weekday - 1];

  static String pendek(DateTime d) {
    final h = d.day.toString();
    final b = d.month.toString().padLeft(2, '0');
    return '$h/$b';
  }

  static String hariTanggal(DateTime d) => '${hari(d)} ${tanggal(d)}';

  static String setoranJudul(DateTime? d) {
    if (d == null) return 'Setoran';
    return 'Setoran ${hari(d)} ${tanggal(d)}';
  }
}

class UangFormatRibuan extends TextInputFormatter {
  const UangFormatRibuan({this.kosong = '0'});

  final String kosong;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return TextEditingValue(
        text: kosong,
        selection: TextSelection.collapsed(offset: kosong.length),
      );
    }
    final teks = Uang.angka(int.parse(digits));
    return TextEditingValue(
      text: teks,
      selection: TextSelection.collapsed(offset: teks.length),
    );
  }
}
