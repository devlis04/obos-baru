import 'package:flutter/material.dart';

void tampilPesan(BuildContext context, String teks) {
  if (!context.mounted) return;
  tampilPesanDi(ScaffoldMessenger.of(context), teks);
}

void tampilPesanDi(ScaffoldMessengerState messenger, String teks) {
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFFF9A825),
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
