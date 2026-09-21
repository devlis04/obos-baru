import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

import 'beranda/beranda_pengirim_layar.dart';

class AppPengirim extends StatelessWidget {
  const AppPengirim({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthKonfig.pengirim)..add(CekSesi()),
      child: MaterialApp(
        title: 'Obos Pengirim',
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
          return BerandaPengirimLayar(
            nama: state.nama,
            rute: state.rute,
            info: state.info,
          );
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.pengirim, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
