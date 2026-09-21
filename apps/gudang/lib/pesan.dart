import 'package:flutter/material.dart';

void tampilPesan(BuildContext context, String teks, {Duration? lama}) {
  if (!context.mounted) return;
  tampilPesanDi(ScaffoldMessenger.of(context), teks, lama: lama);
}

void tampilPesanDi(
  ScaffoldMessengerState messenger,
  String teks, {
  Duration? lama,
}) {
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
      duration: lama ?? const Duration(milliseconds: 4000),
    ),
  );
}
