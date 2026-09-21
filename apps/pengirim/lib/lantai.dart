import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'absensi/absensi_repo.dart';
import 'jaringan.dart';
import 'umpan.dart';

Future<bool> pastikanBolehKerja(BuildContext context) async {
  try {
    final status = await AbsensiRepo(Supabase.instance.client).status();
    if (!context.mounted) return false;
    if (!status.login) {
      umpan(context, 'Sesi login tidak aktif. Masuk lagi.');
      return false;
    }
    if (!status.masuk) {
      umpan(context, 'Scan masuk gudang dulu.');
      return false;
    }
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    umpan(
      context,
      Jaringan.mati(e)
          ? 'Tidak ada internet. Status absensi belum bisa dicek.'
          : pesanGagal(e, 'Status lantai belum bisa dicek.'),
    );
    return false;
  }
}
