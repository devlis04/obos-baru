import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'prefs_hp.dart';
import 'tema.dart';

Future<bool> siapkanObos({required bool pakaiPrefsHp}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (pakaiPrefsHp) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await PrefsHp.siap();
  }
  await dotenv.load(fileName: 'assets/.env');
  final url = (dotenv.env['SUPABASE_URL'] ?? '').trim();
  final kunci = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();
  if (url.isEmpty || kunci.isEmpty) return false;
  await Supabase.initialize(
    url: url,
    // ignore: deprecated_member_use
    anonKey: kunci,
  );
  return true;
}

class EnvKurangApp extends StatelessWidget {
  const EnvKurangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Tema.terang(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              'Isi assets/.env dengan SUPABASE_URL dan SUPABASE_ANON_KEY '
              'dari project Supabase baru (skema public).',
              style: TextStyle(height: 1.4, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
