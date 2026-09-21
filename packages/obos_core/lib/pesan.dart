import 'package:flutter/material.dart';

import 'tema.dart';

void tampilPesan(BuildContext context, String teks) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
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
