import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jaringan.dart';
import 'pesan.dart';

void umpan(BuildContext context, String pesan, {Duration? lama}) {
  tampilPesan(context, pesan, lama: lama);
}

String pesanGagal(Object e, String cadangan) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    return e.message.trim();
  }
  if (Jaringan.mati(e)) {
    return 'Tidak ada internet. Sambungkan internet, lalu coba lagi.';
  }
  return cadangan;
}

Route<T> ruteHalaman<T>(Widget page) {
  return MaterialPageRoute<T>(builder: (_) => page);
}
