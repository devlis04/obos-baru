import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

import 'barang/barang_layar.dart';
import 'beranda/beranda_admin_layar.dart';
import 'dashboard/dashboard_layar.dart';
import 'pelanggan/pelanggan_layar.dart';

class AppAdmin extends StatelessWidget {
  const AppAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthKonfig.admin)..add(CekSesi()),
      child: MaterialApp(
        title: 'Obos Admin',
        debugShowCheckedModeBanner: false,
        theme: Tema.terang(),
        home: const _Gerbang(),
        onGenerateRoute: (settings) {
          if (settings.name == '/' || settings.name == '/setoran') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const _Gerbang(),
            );
          }
          if (settings.name == '/dashboard') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const _GerbangDashboard(),
            );
          }
          if (settings.name == '/barang') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const _GerbangBarang(),
            );
          }
          if (settings.name == '/pelanggan') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const _GerbangPelanggan(),
            );
          }
          return null;
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
          return BerandaAdminLayar(
            nama: state.nama,
            info: state.info,
          );
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.admin, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class _GerbangDashboard extends StatelessWidget {
  const _GerbangDashboard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthMasuk) {
          return const DashboardLayar();
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.admin, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class _GerbangBarang extends StatelessWidget {
  const _GerbangBarang();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthMasuk) {
          return const BarangLayar();
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.admin, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class _GerbangPelanggan extends StatelessWidget {
  const _GerbangPelanggan();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthMasuk) {
          return const PelangganLayar();
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: AuthKonfig.admin, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
