import 'dart:async';

import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void tampilPesan(BuildContext context, String teks) {
  if (!context.mounted) return;
  tampilPesanDi(ScaffoldMessenger.of(context), teks);
}

void tampilPesanDi(ScaffoldMessengerState messenger, String teks) {
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: Tema.kuning,
      content: Text(
        teks,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

String pesanGagal(Object e, String cadangan) {
  if (e is PostgrestException) {
    final m = e.message.trim();
    if (m.isNotEmpty) return m;
    final h = (e.hint ?? '').trim();
    if (h.isNotEmpty) return h;
  }
  if (e is TimeoutException) {
    return 'Server lambat merespons. $cadangan';
  }
  return cadangan;
}
