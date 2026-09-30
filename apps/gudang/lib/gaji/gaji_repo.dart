import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../uang.dart';

class MingguGaji {
  static DateTime hari(DateTime w) => DateTime(w.year, w.month, w.day);

  static DateTime seninDari(DateTime w) {
    final h = hari(w);
    return h.subtract(Duration(days: h.weekday - 1));
  }

  static DateTime senin() => seninDari(DateTime.now());

  static bool samaHari(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String iso(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final h = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$h';
  }

  static String tampil(DateTime w) {
    final m = w.month.toString().padLeft(2, '0');
    final d = w.day.toString().padLeft(2, '0');
    return '$d/$m/${w.year}';
  }

  static String tampilPendek(DateTime w) {
    final m = w.month.toString().padLeft(2, '0');
    return '${w.day}/$m';
  }
}

class IsiGajiGudang {
  const IsiGajiGudang({
    required this.senin,
    required this.sabtu,
    required this.rute,
    required this.nama,
    required this.netActual,
    required this.netTarget,
    required this.pctNet,
    required this.rasioActual,
    required this.rasioTarget,
    required this.pctRasio,
    required this.omsetActual,
    required this.omsetTarget,
    required this.pctOmset,
    required this.hari,
    required this.hariTarget,
    required this.pctHari,
    required this.bopActual,
    required this.bopTarget,
    required this.pctBop,
    required this.gaji,
    required this.kasbon,
    required this.terima,
  });

  final DateTime senin;
  final DateTime sabtu;
  final String rute;
  final String nama;
  final int netActual;
  final int netTarget;
  final double pctNet;
  final double rasioActual;
  final double rasioTarget;
  final double pctRasio;
  final int omsetActual;
  final int omsetTarget;
  final double pctOmset;
  final int hari;
  final int hariTarget;
  final double pctHari;
  final int bopActual;
  final int bopTarget;
  final double pctBop;
  final int gaji;
  final int kasbon;
  final int terima;

  factory IsiGajiGudang.dari(Map<String, dynamic> m) {
    return IsiGajiGudang(
      senin: _hari(m['senin']),
      sabtu: _hari(m['sabtu']),
      rute: (m['rute']?.toString() ?? '').trim(),
      nama: (m['nama']?.toString() ?? '').trim(),
      netActual: Uang.dari(m['net_actual']),
      netTarget: Uang.dari(m['net_target']),
      pctNet: _desimal(m['pct_net']),
      rasioActual: _desimal(m['rasio_actual']),
      rasioTarget: _desimal(m['rasio_target']),
      pctRasio: _desimal(m['pct_rasio']),
      omsetActual: Uang.dari(m['omset_actual']),
      omsetTarget: Uang.dari(m['omset_target']),
      pctOmset: _desimal(m['pct_omset']),
      hari: Uang.dari(m['hari']),
      hariTarget: Uang.dari(m['hari_target']).clamp(1, 7),
      pctHari: _desimal(m['pct_hari']),
      bopActual: Uang.dari(m['bop_actual']),
      bopTarget: Uang.dari(m['bop_target']),
      pctBop: _desimal(m['pct_bop']),
      gaji: Uang.dari(m['gaji']),
      kasbon: Uang.dari(m['kasbon']),
      terima: Uang.dari(m['terima']),
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

class GajiGudangRepo {
  GajiGudangRepo(this._sb);

  final SupabaseClient _sb;

  Future<IsiGajiGudang> lihat(DateTime hari) async {
    final senin = MingguGaji.seninDari(MingguGaji.hari(hari));
    final hasil = await Jaringan.denganUlang(
      () => _sb.rpc(
        'gudang_gaji_minggu',
        params: {'p_senin': MingguGaji.iso(senin)},
      ),
    );
    return _peta(hasil);
  }

  IsiGajiGudang _peta(Object? hasil) {
    if (hasil is Map) {
      return IsiGajiGudang.dari(Map<String, dynamic>.from(hasil));
    }
    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return IsiGajiGudang.dari(
        Map<String, dynamic>.from(hasil.first as Map),
      );
    }
    throw StateError('Benefit minggu ini belum bisa dihitung.');
  }
}
