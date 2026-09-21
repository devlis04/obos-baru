import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

import 'beranda/beranda_gudang_layar.dart';

class AppGudang extends StatelessWidget {
  const AppGudang({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthKonfig.gudang)..add(CekSesi()),
      child: MaterialApp(
        title: 'Obos Gudang',
        debugShowCheckedModeBanner: false,
        theme: Tema.terang(),
        home: const _Gerbang(),
      ),
    );
  }
}

class _Gerbang extends StatelessWidget {
  const _Gerbang();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthMasuk) {
          return BerandaGudangLayar(
            nama: state.nama,
            peran: state.peran,
            info: state.info,
          );
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.gudang, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
