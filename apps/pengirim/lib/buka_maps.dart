import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pesan.dart';

Future<bool> _cobaBuka(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<void> bukaMapsToko({
  required BuildContext context,
  required String nama,
  double? latitude,
  double? longitude,
}) async {
  final lat = latitude;
  final lng = longitude;
  if (lat == null || lng == null || lat == 0 || lng == 0) {
    if (!context.mounted) return;
    tampilPesan(context, 'Toko ini belum punya koordinat GPS.');
    return;
  }

  final label = nama.replaceAll(RegExp(r'[()]'), ' ').trim();
  final titik = '$lat,$lng';
  final daftar = <Uri>[
    Uri.parse('geo:$titik?q=$titik($label)'),
    Uri.parse('geo:0,0?q=$titik($label)'),
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$titik'),
    Uri.parse('https://maps.google.com/?q=$titik'),
  ];

  for (final uri in daftar) {
    if (await _cobaBuka(uri)) return;
  }

  if (!context.mounted) return;
  tampilPesan(context, 'Tidak ada aplikasi peta di HP ini.');
}
