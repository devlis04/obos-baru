import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'auth_event.dart';
import 'auth_konfig.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this.konfig) : super(AuthAwal()) {
    on<CekSesi>(_onCek);
    on<MintaMasuk>(_onMasuk);
    on<MintaKeluar>(_onKeluar);
  }

  final AuthKonfig konfig;
  final _sb = Supabase.instance.client;
  static const _batas = Duration(seconds: 12);

  bool _emailSama(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  Future<Map<String, dynamic>?> _profilHp(String email) async {
    final row = await _sb
        .from('users')
        .select('email, nama, rute, is_login, peran')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle()
        .timeout(_batas);
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>?> _profilAdmin() async {
    final hasil = await _sb.rpc('admin_profil').timeout(_batas);
    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return Map<String, dynamic>.from(hasil.first as Map);
    }
    if (hasil is Map) {
      return Map<String, dynamic>.from(hasil);
    }
    return null;
  }

  Future<bool> _kunciSlot(bool isi) async {
    final ok = await _sb.rpc(
      'hp_apply_is_login',
      params: {
        'p_is_login': isi,
        'p_kunci': await SesiHp.kunciHp(),
      },
    ).timeout(_batas);
    return ok == true;
  }

  Future<void> _signOut() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
  }

  AuthMasuk _masukDari({
    required String nama,
    required String email,
    required String peran,
    required String rute,
    String? info,
  }) {
    return AuthMasuk(
      nama: nama,
      email: email,
      peran: peran,
      rute: rute,
      info: info,
    );
  }

  Future<void> _onCek(CekSesi event, Emitter<AuthState> emit) async {
    emit(AuthMemuat());
    if (!konfig.pakaiSlotHp) {
      await _onCekAdmin(emit);
      return;
    }
    await _onCekHp(emit);
  }

  Future<void> _onCekAdmin(Emitter<AuthState> emit) async {
    final sesi = _sb.auth.currentSession;
    if (sesi == null) {
      emit(AuthKeluar());
      return;
    }
    try {
      await _sb.auth.refreshSession();
    } catch (_) {}
    try {
      final profil = await _profilAdmin();
      final nama = profil?['nama']?.toString().trim();
      final email = profil?['email']?.toString().trim();
      final peran = profil?['peran']?.toString() ?? 'admin';
      final rute = profil?['rute']?.toString() ?? '';
      if (nama == null || nama.isEmpty || email == null || email.isEmpty) {
        await _signOut();
        emit(AuthKeluar());
        return;
      }
      emit(_masukDari(nama: nama, email: email, peran: peran, rute: rute));
    } catch (_) {
      await _signOut();
      emit(AuthKeluar(pesan: 'Sesi tidak aktif. Masuk lagi.'));
    }
  }

  Future<void> _onCekHp(Emitter<AuthState> emit) async {
    final lokal = await SesiHp.bertandaMasuk();
    final saved = await SesiHp.email();
    final sesi = _sb.auth.currentSession;
    final sesiEmail = sesi?.user.email;

    if (!lokal ||
        saved == null ||
        sesi == null ||
        sesiEmail == null ||
        !_emailSama(saved, sesiEmail)) {
      if (sesi != null) await _signOut();
      emit(AuthKeluar());
      return;
    }

    try {
      await _sb.auth.refreshSession();
    } catch (_) {}

    try {
      final profil = await _profilHp(saved);
      if (profil != null && profil['is_login'] == false) {
        await SesiHp.tandaiKeluar();
        await _signOut();
        emit(AuthKeluar());
        return;
      }
      if (!konfig.peranCocok(profil?['peran']?.toString())) {
        await SesiHp.tandaiKeluar();
        await _signOut();
        emit(AuthKeluar());
        return;
      }
      if (!await _kunciSlot(true)) {
        await SesiHp.tandaiKeluar();
        await _signOut();
        emit(
          AuthKeluar(
            pesan: 'Akun sedang dipakai di HP lain. Keluar dulu di HP itu.',
          ),
        );
        return;
      }
      final nama = profil?['nama']?.toString() ?? await SesiHp.nama();
      final peran = profil?['peran']?.toString() ?? await SesiHp.peran();
      final rute = profil?['rute']?.toString() ?? await SesiHp.rute();
      await SesiHp.tandaiMasuk(
        email: saved,
        nama: nama,
        peran: peran,
        rute: rute,
      );
      emit(_masukDari(nama: nama, email: saved, peran: peran, rute: rute));
    } catch (_) {
      emit(
        _masukDari(
          nama: await SesiHp.nama(),
          email: saved,
          peran: await SesiHp.peran(),
          rute: await SesiHp.rute(),
        ),
      );
    }
  }

  Future<void> _onMasuk(MintaMasuk event, Emitter<AuthState> emit) async {
    emit(AuthMemuat());
    try {
      if (konfig.pakaiSlotHp) {
        await _masukHp(event, emit);
      } else {
        await _masukAdmin(event, emit);
      }
    } on AuthException catch (e) {
      emit(AuthKeluar(pesan: _pesanMasuk(e.message)));
    } catch (_) {
      emit(
        AuthKeluar(
          pesan: 'Tidak bisa masuk. Periksa internet, lalu coba lagi.',
        ),
      );
    }
  }

  Future<void> _masukAdmin(MintaMasuk event, Emitter<AuthState> emit) async {
    final res = await _sb.auth.signInWithPassword(
      email: event.email.trim(),
      password: event.sandi,
    );
    if (res.user?.email == null) {
      emit(AuthKeluar(pesan: 'Email atau kata sandi tidak sesuai.'));
      return;
    }
    final profil = await _profilAdmin();
    final nama = profil?['nama']?.toString().trim();
    final email = profil?['email']?.toString().trim();
    final peran = profil?['peran']?.toString() ?? 'admin';
    final rute = profil?['rute']?.toString() ?? '';
    if (nama == null || nama.isEmpty || email == null || email.isEmpty) {
      await _signOut();
      emit(AuthKeluar(pesan: 'Hanya akun admin yang boleh masuk web ini.'));
      return;
    }
    emit(_masukDari(nama: nama, email: email, peran: peran, rute: rute));
  }

  Future<void> _masukHp(MintaMasuk event, Emitter<AuthState> emit) async {
    final lokal = await SesiHp.bertandaMasuk();
    final res = await _sb.auth.signInWithPassword(
      email: event.email.trim(),
      password: event.sandi,
    );
    final user = res.user;
    if (user?.email == null) {
      emit(AuthKeluar(pesan: 'Email atau kata sandi tidak sesuai.'));
      return;
    }
    final email = user!.email!;
    final profil = await _profilHp(email);
    if (profil == null) {
      await _signOut();
      emit(
        AuthKeluar(
          pesan: 'Akun Auth ada, tetapi belum ada di public.users.',
        ),
      );
      return;
    }
    final peran = profil['peran']?.toString() ?? '';
    if (!konfig.peranCocok(peran)) {
      await _signOut();
      emit(AuthKeluar(pesan: konfig.pesanSalahPeran(peran)));
      return;
    }
    if (profil['is_login'] == true && !lokal) {
      await _signOut();
      emit(
        AuthKeluar(
          pesan: 'Akun sedang dipakai di HP lain. Keluar dulu di HP itu.',
        ),
      );
      return;
    }
    if (!await _kunciSlot(true)) {
      await _signOut();
      emit(
        AuthKeluar(
          pesan: 'Akun sedang dipakai di HP lain. Keluar dulu di HP itu.',
        ),
      );
      return;
    }
    final nama = profil['nama']?.toString() ?? '';
    final rute = profil['rute']?.toString() ?? '';
    await SesiHp.tandaiMasuk(
      email: email,
      nama: nama,
      peran: peran,
      rute: rute,
    );
    emit(_masukDari(nama: nama, email: email, peran: peran, rute: rute));
  }

  Future<void> _onKeluar(MintaKeluar event, Emitter<AuthState> emit) async {
    final sebelumnya = state;
    emit(AuthMemuat());
    if (!konfig.pakaiSlotHp) {
      await _signOut();
      emit(AuthKeluar());
      return;
    }
    try {
      if (!await _kunciSlot(false)) {
        throw Exception('rpc');
      }
      await SesiHp.tandaiKeluar();
      await _signOut();
      emit(AuthKeluar());
    } catch (_) {
      const gagal =
          'Tidak bisa keluar di server. Sambungkan internet, lalu coba lagi.';
      if (sebelumnya is AuthMasuk) {
        emit(
          AuthMasuk(
            nama: sebelumnya.nama,
            email: sebelumnya.email,
            peran: sebelumnya.peran,
            rute: sebelumnya.rute,
            info: gagal,
          ),
        );
        return;
      }
      emit(AuthKeluar(pesan: gagal));
    }
  }

  String _pesanMasuk(String asli) {
    final t = asli.toLowerCase();
    if (t.contains('not confirmed') || t.contains('email_not_confirmed')) {
      return 'Email Auth belum dikonfirmasi. Jalankan supabase/002_confirm_auth.sql.';
    }
    if (t.contains('invalid') ||
        t.contains('credential') ||
        t.contains('password')) {
      return 'Email atau kata sandi tidak sesuai.';
    }
    return 'Tidak bisa masuk. Periksa email, sandi, dan internet.';
  }
}
