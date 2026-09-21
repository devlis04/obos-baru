import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

Widget chipStatusNota(String label) {
  final kunci = label.trim().split(RegExp(r'\s+')).first;
  final warna = switch (kunci) {
    'Terkirim' || 'Sedang' => Colors.green,
    'Batal' => Colors.red,
    'Pending' => Colors.orange.shade800,
    _ => Colors.amber.shade800,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: Tema.sudut,
      border: Border.all(color: warna, width: 1.2),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: warna,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    ),
  );
}
