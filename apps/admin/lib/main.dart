import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import 'app.dart';

Future<void> main() async {
  final ok = await siapkanObos(pakaiPrefsHp: false);
  if (!ok) {
    runApp(const EnvKurangApp());
    return;
  }
  runApp(const AppAdmin());
}
