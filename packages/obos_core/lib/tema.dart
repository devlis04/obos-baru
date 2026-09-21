import 'package:flutter/material.dart';

class Tema {
  static const Color seed = Color(0xFF1B75CB);
  static const Color biru = seed;
  static const Color latar = Color(0xFFF3F5F8);
  static const Color teksKartu = Colors.black;
  static const Color redup = Colors.grey;
  static const Color kuning = Color(0xFFF9A825);
  static const double pxSudut = 5;
  static const BorderRadius sudut = BorderRadius.all(Radius.circular(pxSudut));

  static ThemeData terang() {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD6E8F7),
      onPrimaryContainer: seed,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: latar,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: const RoundedRectangleBorder(
          borderRadius: sudut,
          side: BorderSide(color: seed, width: 1.2),
        ),
      ),
      iconTheme: const IconThemeData(color: seed),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        iconTheme: const IconThemeData(color: seed),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 46),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: sudut,
          borderSide: BorderSide(color: seed, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: sudut,
          borderSide: BorderSide(color: seed, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: sudut,
          borderSide: BorderSide(color: seed, width: 1.2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kuning,
        shape: RoundedRectangleBorder(borderRadius: sudut),
        contentTextStyle: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: seed),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: sudut),
      ),
      datePickerTheme: const DatePickerThemeData(
        shape: RoundedRectangleBorder(borderRadius: sudut),
      ),
    );
  }
}
