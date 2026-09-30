import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pelanggan/pelanggan.dart';
import '../uang.dart';

class IsiGajiSales {
  const IsiGajiSales({
    required this.senin,
    required this.sabtu,
    required this.rute,
    required this.nama,
    required this.rasioActual,
    required this.rasioTarget,
    required this.pctRasio,
    required this.omsetActual,
    required this.omsetTarget,
    required this.pctOmset,
    required this.benOmset,
    required this.ec,
    required this.ecTarget,
    required this.pctEc,
    required this.benEc,
    required this.visit,
    required this.visitTarget,
    required this.pctVisit,
    required this.benVisit,
    required this.bopPengirim,
    required this.total,
  });

  final DateTime senin;
  final DateTime sabtu;
  final String rute;
  final String nama;
  final double rasioActual;
  final double rasioTarget;
  final double pctRasio;
  final int omsetActual;
  final int omsetTarget;
  final double pctOmset;
  final int benOmset;
  final int ec;
  final int ecTarget;
  final double pctEc;
  final int benEc;
  final int visit;
  final int visitTarget;
  final double pctVisit;
  final int benVisit;
  final int bopPengirim;
  final int total;

  factory IsiGajiSales.dari(Map<String, dynamic> m) {
    return IsiGajiSales(
      senin: _hari(m['senin']),
      sabtu: _hari(m['sabtu']),
      rute: (m['rute']?.toString() ?? '').trim(),
      nama: (m['nama']?.toString() ?? '').trim(),
      rasioActual: _desimal(m['rasio_actual']),
      rasioTarget: _desimal(m['rasio_target']),
      pctRasio: _desimal(m['pct_rasio']),
      omsetActual: Uang.dari(m['omset_actual']),
      omsetTarget: Uang.dari(m['omset_target']),
      pctOmset: _desimal(m['pct_omset']),
      benOmset: Uang.dari(m['ben_omset']),
      ec: Uang.dari(m['ec']),
      ecTarget: Uang.dari(m['ec_target']).clamp(1, 999999),
      pctEc: _desimal(m['pct_ec']),
      benEc: Uang.dari(m['ben_ec']),
      visit: Uang.dari(m['visit']),
      visitTarget: Uang.dari(m['visit_target']).clamp(1, 999999),
      pctVisit: _desimal(m['pct_visit']),
      benVisit: Uang.dari(m['ben_visit']),
      bopPengirim: Uang.dari(m['bop_pengirim']),
      total: Uang.dari(m['total']),
    );
  }

  static DateTime _hari(Object? v) {
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final t = DateTime.tryParse(v?.toString() ?? '');
    if (t == null) return DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  static double _desimal(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class GajiSalesRepo {
  GajiSalesRepo(this._sb);

  final SupabaseClient _sb;

  Future<IsiGajiSales> lihat(DateTime hari) async {
    final senin = MingguKunjungan.seninDari(MingguKunjungan.hari(hari));
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc(
        'salesman_gaji_minggu',
        params: {'p_senin': MingguKunjungan.iso(senin)},
      ),
    );
    return _peta(hasil);
  }

  IsiGajiSales _peta(Object? hasil) {
    if (hasil is Map) {
      return IsiGajiSales.dari(Map<String, dynamic>.from(hasil));
    }
    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return IsiGajiSales.dari(Map<String, dynamic>.from(hasil.first as Map));
    }
    throw StateError('Benefit minggu ini belum bisa dihitung.');
  }
}
