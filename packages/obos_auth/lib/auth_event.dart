abstract class AuthEvent {}

class CekSesi extends AuthEvent {}

class MintaMasuk extends AuthEvent {
  MintaMasuk(this.email, this.sandi);
  final String email;
  final String sandi;
}

class MintaKeluar extends AuthEvent {}
