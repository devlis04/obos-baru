import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String csvTulis(List<String> kepala, List<List<String>> isi) {
  final buf = StringBuffer()
    ..write('sep=,\r\n')
    ..write(kepala.map(_sel).join(','))
    ..write('\r\n');
  for (final row in isi) {
    buf
      ..write(row.map(_sel).join(','))
      ..write('\r\n');
  }
  return buf.toString();
}

void unduhBerkasCsv(String namaFile, String isi) {
  final crlf = isi
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '\r\n');
  final isiUtf8 = utf8.encode(crlf);
  final data = Uint8List(3 + isiUtf8.length)
    ..[0] = 0xEF
    ..[1] = 0xBB
    ..[2] = 0xBF
    ..setAll(3, isiUtf8);
  final blob = web.Blob(
    [data.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = namaFile.endsWith('.csv') ? namaFile : '$namaFile.csv'
    ..rel = 'noopener'
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  Future<void>.delayed(const Duration(seconds: 2), () {
    a.remove();
    web.URL.revokeObjectURL(url);
  });
}

String _sel(String v) {
  if (v.contains(',') ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}
