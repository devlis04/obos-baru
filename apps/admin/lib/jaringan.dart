import 'dart:async';
import 'dart:io';

class Jaringan {
  static const lambat = Duration(seconds: 20);
  static const cepat = Duration(seconds: 10);

  static bool mati(Object e) {
    if (e is TimeoutException ||
        e is SocketException ||
        e is HandshakeException) {
      return true;
    }
    final teks = e.toString().toLowerCase();
    return teks.contains('socketexception') ||
        teks.contains('clientexception') ||
        teks.contains('failed host lookup') ||
        teks.contains('connection refused') ||
        teks.contains('connection reset') ||
        teks.contains('connection abort') ||
        teks.contains('network is unreachable') ||
        teks.contains('failed to fetch') ||
        teks.contains('xmlhttprequest') ||
        teks.contains('timed out') ||
        teks.contains('timeout') ||
        teks.contains('offline');
  }

  /// Satu kali ulang jika putus/timeout. Jangan untuk tulis yang tidak idempoten.
  static Future<T> denganUlang<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      if (!mati(e)) rethrow;
      return await fn();
    }
  }
}
