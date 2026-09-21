abstract class AuthState {}

class AuthAwal extends AuthState {}

class AuthMemuat extends AuthState {}

class AuthMasuk extends AuthState {
  AuthMasuk({
    required this.nama,
    required this.email,
    required this.peran,
    required this.rute,
    this.info,
  });

  final String nama;
  final String email;
  final String peran;
  final String rute;
  final String? info;
}

class AuthKeluar extends AuthState {
  AuthKeluar({this.pesan});
  final String? pesan;
}
