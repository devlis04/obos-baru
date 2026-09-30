import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pelanggan/pelanggan.dart';
import '../uang.dart';

class IsiRingkas {
  const IsiRingkas({
    required this.omsetOrder,
    required this.labaOrder,
    required this.omsetKiriman,
    required this.labaKiriman,
    required this.omsetActual,
    required this.labaActual,
    required this.ecOrder,
    required this.ecKiriman,
    required this.ecActual,
    required this.visit,
    required this.targetOmset,
    required this.targetPersen,
    required this.targetEc,
    required this.targetVisit,
  });

  final int omsetOrder;
  final int labaOrder;
  final int omsetKiriman;
  final int labaKiriman;
  final int omsetActual;
  final int labaActual;
  final int ecOrder;
  final int ecKiriman;
  final int ecActual;
  final int visit;
  final int targetOmset;
  final double targetPersen;
  final int targetEc;
  final int targetVisit;

  factory IsiRingkas.dari(Map<String, dynamic> m) {
    int n(String k) => Uang.dari(m[k]);
    double d(String k) {
      final v = m[k];
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    return IsiRingkas(
      omsetOrder: n('omset_order'),
      labaOrder: n('laba_order'),
      omsetKiriman: n('omset_kiriman'),
      labaKiriman: n('laba_kiriman'),
      omsetActual: n('omset_actual'),
      labaActual: n('laba_actual'),
      ecOrder: n('ec_order'),
      ecKiriman: n('ec_kiriman'),
      ecActual: n('ec_actual'),
      visit: n('visit'),
      targetOmset: n('target_omset'),
      targetPersen: d('target_persen'),
      targetEc: n('target_ec').clamp(1, 1 << 30),
      targetVisit: n('target_visit').clamp(1, 1 << 30),
    );
  }
}

class RingkasRepo {
  RingkasRepo(this._sb);

  final SupabaseClient _sb;

  Future<IsiRingkas> lihat({
    required DateTime dari,
    required DateTime sampai,
  }) async {
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc(
        'salesman_ringkas',
        params: {
          'p_dari': MingguKunjungan.iso(MingguKunjungan.hari(dari)),
          'p_sampai': MingguKunjungan.iso(MingguKunjungan.hari(sampai)),
        },
      ),
    );
    if (hasil is Map) {
      return IsiRingkas.dari(Map<String, dynamic>.from(hasil));
    }
    throw StateError('Ringkasan penjualan belum bisa dimuat. Jalankan SQL 133.');
  }
}
