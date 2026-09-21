import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';

import 'auth_bloc.dart';
import 'auth_event.dart';
import 'auth_konfig.dart';
import 'auth_state.dart';
import 'login_layar.dart';

class ObosApp extends StatelessWidget {
  const ObosApp({super.key, required this.konfig});

  final AuthKonfig konfig;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(konfig)..add(CekSesi()),
      child: MaterialApp(
        title: konfig.judul,
        debugShowCheckedModeBanner: false,
        theme: Tema.terang(),
        home: GerbangAuth(konfig: konfig),
      ),
    );
  }
}

class GerbangAuth extends StatelessWidget {
  const GerbangAuth({super.key, required this.konfig});

  final AuthKonfig konfig;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthMasuk) {
          return HaloMasukLayar(state: state);
        }
        if (state is AuthKeluar) {
          return LoginLayar(konfig: konfig, pesan: state.pesan);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class HaloMasukLayar extends StatelessWidget {
  const HaloMasukLayar({super.key, required this.state});

  final AuthMasuk state;

  @override
  Widget build(BuildContext context) {
    final info = state.info;
    return Scaffold(
      appBar: AppBar(title: Text(state.nama)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masuk sebagai ${state.nama}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Email: ${state.email}'),
            Text('Peran: ${state.peran}'),
            if (state.rute.trim().isNotEmpty) Text('Rute: ${state.rute}'),
            if (info != null && info.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(info, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.read<AuthBloc>().add(MintaKeluar()),
                child: const Text('Keluar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
