import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences terenkripsi AES. Kunci hanya di secure storage HP.
class PrefsHp {
  static const _kunciSimpan = 'obos_aes_public_v1';
  static const _awalan = 'x.';
  static const _storage = FlutterSecureStorage();

  static enc.Key? _aesKey;

  static Future<void> siap() async {
    await _aes();
  }

  static Future<enc.Key> _aes() async {
    final ada = _aesKey;
    if (ada != null) return ada;
    var b64 = await _storage.read(key: _kunciSimpan);
    if (b64 == null || b64.isEmpty) {
      final bytes = Uint8List(32);
      final acak = Random.secure();
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = acak.nextInt(256);
      }
      b64 = base64Encode(bytes);
      await _storage.write(key: _kunciSimpan, value: b64);
    }
    return _aesKey = enc.Key.fromBase64(b64);
  }

  static String _nama(String kunci) => '$_awalan$kunci';

  static Future<enc.Encrypter> _mesin() async =>
      enc.Encrypter(enc.AES(await _aes(), mode: enc.AESMode.cbc));

  static Future<String> _enkrip(String plain) async {
    final iv = enc.IV.fromSecureRandom(16);
    final ct = (await _mesin()).encrypt(plain, iv: iv);
    return '${iv.base64}.${ct.base64}';
  }

  static String? _dekrip(String bungkus) {
    final bagian = bungkus.split('.');
    if (bagian.length != 2) return null;
    final key = _aesKey;
    if (key == null) return null;
    try {
      final iv = enc.IV.fromBase64(bagian[0]);
      final mesin = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return mesin.decrypt(enc.Encrypted.fromBase64(bagian[1]), iv: iv);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getString(String kunci) async {
    await _aes();
    final p = await SharedPreferences.getInstance();
    final bungkus = p.getString(_nama(kunci));
    if (bungkus == null || bungkus.isEmpty) return null;
    return _dekrip(bungkus);
  }

  static Future<void> setString(String kunci, String nilai) async {
    await _aes();
    final p = await SharedPreferences.getInstance();
    await p.setString(_nama(kunci), await _enkrip(nilai));
  }

  static Future<bool> getBool(String kunci, {bool jikaKosong = false}) async {
    final s = await getString(kunci);
    if (s == null) return jikaKosong;
    return s == '1';
  }

  static Future<void> setBool(String kunci, bool nilai) async {
    await setString(kunci, nilai ? '1' : '0');
  }

  static Future<void> hapus(String kunci) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_nama(kunci));
  }
}
