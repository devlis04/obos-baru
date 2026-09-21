import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

import 'cangkang/cangkang_layar.dart';
import 'barang/barang_bloc.dart';
import 'barang/barang_event.dart';
import 'pelanggan/pelanggan_bloc.dart';

class AppSales extends StatelessWidget {
  const AppSales({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthKonfig.salesman)..add(CekSesi()),
      child: BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (p, c) =>
            p.runtimeType != c.runtimeType ||
            (p is AuthMasuk && c is AuthMasuk && p.rute != c.rute),
        builder: (context, state) {
          return MaterialApp(
            title: 'Obos Sales',
            debugShowCheckedModeBanner: false,
            theme: Tema.terang(),
            builder: (context, child) {
              final halaman = child ?? const SizedBox.shrink();
              if (state is AuthMasuk) {
                return MultiBlocProvider(
                  key: ValueKey(state.rute),
                  providers: [
                    BlocProvider(
                      create: (_) => PelangganBloc(rute: state.rute),
                    ),
                    BlocProvider(
                      create: (_) => BarangBloc()..add(MuatBarang()),
                    ),
                  ],
                  child: halaman,
                );
              }
              return halaman;
            },
            home: const _Gerbang(),
          );
        },
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
          return CangkangLayar(
            nama: state.nama,
            rute: state.rute,
            info: state.info,
          );
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.salesman, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
