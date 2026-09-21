import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pesan.dart';

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

  final geo = Uri(
    scheme: 'geo',
    path: '$lat,$lng',
    queryParameters: {'q': '$lat,$lng($nama)'},
  );
  if (await canLaunchUrl(geo)) {
    await launchUrl(geo, mode: LaunchMode.externalApplication);
    return;
  }

  final web = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  );
  if (await canLaunchUrl(web)) {
    await launchUrl(web, mode: LaunchMode.externalApplication);
    return;
  }

  if (!context.mounted) return;
  tampilPesan(context, 'Tidak ada aplikasi peta di HP ini.');
}
