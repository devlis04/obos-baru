class AuthKonfig {
  const AuthKonfig({
    required this.judul,
    required this.subjudul,
    required this.peranDiizinkan,
    required this.pakaiSlotHp,
  });

  final String judul;
  final String subjudul;
  final Set<String> peranDiizinkan;
  final bool pakaiSlotHp;

  static const salesman = AuthKonfig(
    judul: 'Obos Salesman',
    subjudul: 'Untuk salesman',
    peranDiizinkan: {'sales'},
    pakaiSlotHp: true,
  );

  static const gudang = AuthKonfig(
    judul: 'Obos Gudang',
    subjudul: 'Untuk gudang',
    peranDiizinkan: {'gudang', 'admin'},
    pakaiSlotHp: true,
  );

  static const pengirim = AuthKonfig(
    judul: 'Obos Pengirim',
    subjudul: 'Untuk pengirim',
    peranDiizinkan: {'pengirim'},
    pakaiSlotHp: true,
  );

  static const admin = AuthKonfig(
    judul: 'Obos Admin',
    subjudul: 'Hanya akun admin',
    peranDiizinkan: {'admin'},
    pakaiSlotHp: false,
  );

  bool peranCocok(String? peran) =>
      peranDiizinkan.contains((peran ?? '').trim().toLowerCase());

  String pesanSalahPeran(String peran) {
    final p = peran.trim().toLowerCase();
    if (p == 'sales') {
      return 'Akun ini untuk salesman. Buka aplikasi salesman.';
    }
    if (p == 'pengirim') {
      return 'Akun ini untuk pengirim. Buka aplikasi pengirim.';
    }
    if (p == 'gudang') {
      return 'Akun ini untuk gudang. Buka aplikasi gudang.';
    }
    if (p == 'admin') {
      return 'Akun ini untuk admin. Buka web admin, atau aplikasi gudang.';
    }
    return 'Peran akun tidak sesuai aplikasi ini.';
  }
}
