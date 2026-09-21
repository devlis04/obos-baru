import 'dart:convert';
import 'dart:math';

import 'prefs_hp.dart';

class KunjunganHp {
  const KunjunganHp({
    required this.id,
    required this.bypass,
    required this.selesaiMinggu,
  });

  final String id;
  final bool bypass;
  final bool selesaiMinggu;
}

class SesiHp {
  static const _masuk = 'is_login';
  static const _email = 'email';
  static const _nama = 'nama';
  static const _peran = 'peran';
  static const _rute = 'rute';
  static const _kunciHp = 'kunci_hp';
  static const _hari = 'hari';
  static const _kunjunganId = 'kunjungan_id';
  static const _kunjunganBypass = 'kunjungan_bypass';
  static const _kunjunganSelesai = 'kunjungan_selesai_minggu';
  static const _kunjunganHari = 'kunjungan_hari';

  static Future<bool> bertandaMasuk() async => PrefsHp.getBool(_masuk);

  static Future<String?> email() async => PrefsHp.getString(_email);

  static Future<String> nama() async =>
      (await PrefsHp.getString(_nama)) ?? '';

  static Future<String> peran() async =>
      (await PrefsHp.getString(_peran)) ?? '';

  static Future<String> rute() async =>
      (await PrefsHp.getString(_rute)) ?? '';

  static Future<void> tandaiMasuk({
    required String email,
    required String nama,
    required String peran,
    required String rute,
  }) async {
    await PrefsHp.setBool(_masuk, true);
    await PrefsHp.setString(_email, email);
    await PrefsHp.setString(_nama, nama);
    await PrefsHp.setString(_peran, peran);
    await PrefsHp.setString(_rute, rute);
  }

  static Future<void> tandaiKeluar() async {
    await PrefsHp.setBool(_masuk, false);
    await PrefsHp.hapus(_email);
    await PrefsHp.hapus(_nama);
    await PrefsHp.hapus(_peran);
    await PrefsHp.hapus(_rute);
    await PrefsHp.hapus(_hari);
    await PrefsHp.hapus(_kunjunganId);
    await PrefsHp.hapus(_kunjunganBypass);
    await PrefsHp.hapus(_kunjunganSelesai);
    await PrefsHp.hapus(_kunjunganHari);
  }

  static Future<KunjunganHp?> kunjunganAktif() async {
    final id = await PrefsHp.getString(_kunjunganId);
    if (id == null || id.isEmpty) return null;
    return KunjunganHp(
      id: id,
      bypass: await PrefsHp.getBool(_kunjunganBypass),
      selesaiMinggu: await PrefsHp.getBool(_kunjunganSelesai),
    );
  }

  static Future<void> setKunjungan({
    required String id,
    required bool bypass,
    bool selesaiMinggu = false,
  }) async {
    await PrefsHp.setString(_kunjunganId, id);
    await PrefsHp.setBool(_kunjunganBypass, bypass);
    await PrefsHp.setBool(_kunjunganSelesai, selesaiMinggu);
  }

  static Future<void> hapusKunjungan() async {
    await PrefsHp.hapus(_kunjunganId);
    await PrefsHp.hapus(_kunjunganBypass);
    await PrefsHp.hapus(_kunjunganSelesai);
    await PrefsHp.hapus(_kunjunganHari);
  }

  static Future<String?> hariTerakhir() async => PrefsHp.getString(_hari);

  static Future<void> setHari(String hari) async {
    await PrefsHp.setString(_hari, hari);
  }

  static Future<String> kunciHp() async {
    final ada = await PrefsHp.getString(_kunciHp);
    if (ada != null && ada.length >= 16) return ada;
    final acak = Random.secure();
    final bytes = List<int>.generate(16, (_) => acak.nextInt(256));
    final kunci = base64UrlEncode(bytes).replaceAll('=', '');
    await PrefsHp.setString(_kunciHp, kunci);
    return kunci;
  }
}
