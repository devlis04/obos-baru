import 'package:flutter/services.dart';

num? nilaiDariRumus(String teks) {
  var s = teks.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;
  s = s
      .replaceAll(',', '.')
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('x', '*')
      .replaceAll('X', '*');
  try {
    final v = _Parser(s).parse();
    if (v.isNaN || v.isInfinite || v < 0) return null;
    final r = (v * 10000).round() / 10000;
    if (r == r.roundToDouble()) return r.round();
    return r;
  } catch (_) {
    return null;
  }
}

String teksQty(num n) {
  if (n == n.roundToDouble()) return '${n.round()}';
  return n
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

class FormatRumusQty implements TextInputFormatter {
  const FormatRumusQty();

  static final _ok = RegExp(r'^[0-9+\-*/xX×÷().,\s]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || _ok.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;

  double parse() {
    final v = _expr();
    if (i != s.length) throw const FormatException();
    return v;
  }

  double _expr() {
    var v = _term();
    while (i < s.length) {
      final c = s[i];
      if (c != '+' && c != '-') break;
      i++;
      final r = _term();
      v = c == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (i < s.length) {
      final c = s[i];
      if (c != '*' && c != '/') break;
      i++;
      final r = _factor();
      if (c == '/') {
        if (r == 0) throw const FormatException();
        v = v / r;
      } else {
        v *= r;
      }
    }
    return v;
  }

  double _factor() {
    if (i >= s.length) throw const FormatException();
    if (s[i] == '+') {
      i++;
      return _factor();
    }
    if (s[i] == '-') {
      i++;
      return -_factor();
    }
    if (s[i] == '(') {
      i++;
      final v = _expr();
      if (i >= s.length || s[i] != ')') throw const FormatException();
      i++;
      return v;
    }
    return _number();
  }

  double _number() {
    final start = i;
    var titik = false;
    while (i < s.length) {
      final c = s[i];
      if (c == '.') {
        if (titik) throw const FormatException();
        titik = true;
        i++;
        continue;
      }
      if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) {
        i++;
        continue;
      }
      break;
    }
    if (i == start || s.substring(start, i) == '.') {
      throw const FormatException();
    }
    return double.parse(s.substring(start, i));
  }
}
