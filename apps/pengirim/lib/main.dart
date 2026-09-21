import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import 'app.dart';

Future<void> main() async {
  final ok = await siapkanObos(pakaiPrefsHp: true);
  if (!ok) {
    runApp(const EnvKurangApp());
    return;
  }
  runApp(const AppPengirim());
}
