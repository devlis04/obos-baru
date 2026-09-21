import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';
import 'package:obos_core/pesan.dart';

import 'auth_bloc.dart';
import 'auth_event.dart';
import 'auth_konfig.dart';
import 'auth_state.dart';

class LoginLayar extends StatefulWidget {
  const LoginLayar({super.key, required this.konfig, this.pesan});

  final AuthKonfig konfig;
  final String? pesan;

  @override
  State<LoginLayar> createState() => _LoginLayarState();
}

class _LoginLayarState extends State<LoginLayar> {
  final _email = TextEditingController();
  final _sandi = TextEditingController();
  bool _tutupSandi = true;

  @override
  void initState() {
    super.initState();
    _tampilPesan(widget.pesan);
  }

  @override
  void didUpdateWidget(LoginLayar old) {
    super.didUpdateWidget(old);
    if (widget.pesan != old.pesan) {
      _tampilPesan(widget.pesan);
    }
  }

  void _tampilPesan(String? pesan) {
    if (pesan == null || pesan.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      tampilPesan(context, pesan);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _sandi.dispose();
    super.dispose();
  }

  void _masuk() {
    final email = _email.text.trim();
    final sandi = _sandi.text;
    if (email.isEmpty || sandi.isEmpty) {
      tampilPesan(context, 'Email dan kata sandi wajib diisi.');
      return;
    }
    context.read<AuthBloc>().add(MintaMasuk(email, sandi));
  }

  @override
  Widget build(BuildContext context) {
    const garisBiru = OutlineInputBorder(
      borderRadius: Tema.sudut,
      borderSide: BorderSide(color: Tema.seed, width: 1.2),
    );
    final memuat = context.watch<AuthBloc>().state is AuthMemuat;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.konfig.judul,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Tema.seed,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.konfig.subjudul,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    enabled: !memuat,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      enabledBorder: garisBiru,
                      focusedBorder: garisBiru,
                      border: garisBiru,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _sandi,
                    enabled: !memuat,
                    obscureText: _tutupSandi,
                    onSubmitted: (_) => _masuk(),
                    decoration: InputDecoration(
                      labelText: 'Kata sandi',
                      enabledBorder: garisBiru,
                      focusedBorder: garisBiru,
                      border: garisBiru,
                      suffixIcon: IconButton(
                        color: Tema.seed,
                        icon: Icon(
                          _tutupSandi
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _tutupSandi = !_tutupSandi),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: memuat ? null : _masuk,
                      child: Text(memuat ? 'Masuk…' : 'Masuk'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
