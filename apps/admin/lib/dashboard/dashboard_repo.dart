import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../uang.dart';

class CapaianDash {
  const CapaianDash({
    required this.omsetOrder,
    required this.labaOrder,
    required this.omsetKiriman,
    required this.labaKiriman,
    required this.omsetActual,
    required this.labaActual,
    required this.ecOrder,
    required this.ecKiriman,
    required this.ecActual,
    required this.notaOrder,
    required this.notaKiriman,
    required this.notaActual,
    required this.visit,
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
  final int notaOrder;
  final int notaKiriman;
  final int notaActual;
  final int visit;
  final int targetEc;
  final int targetVisit;

  static const kosong = CapaianDash(
    omsetOrder: 0,
    labaOrder: 0,
    omsetKiriman: 0,
    labaKiriman: 0,
    omsetActual: 0,
    labaActual: 0,
    ecOrder: 0,
    ecKiriman: 0,
    ecActual: 0,
    notaOrder: 0,
    notaKiriman: 0,
    notaActual: 0,
    visit: 0,
    targetEc: 1,
    targetVisit: 1,
  );

  factory CapaianDash.dari(Map<String, dynamic>? j) {
    if (j == null) return kosong;
    return CapaianDash(
      omsetOrder: Uang.dari(j['omset_order']),
      labaOrder: Uang.dari(j['laba_order']),
      omsetKiriman: Uang.dari(j['omset_kiriman']),
      labaKiriman: Uang.dari(j['laba_kiriman']),
      omsetActual: Uang.dari(j['omset_actual']),
      labaActual: Uang.dari(j['laba_actual']),
      ecOrder: Uang.dari(j['ec_order']),
      ecKiriman: Uang.dari(j['ec_kiriman']),
      ecActual: Uang.dari(j['ec_actual']),
      notaOrder: Uang.dari(j['nota_order']),
      notaKiriman: Uang.dari(j['nota_kiriman']),
      notaActual: Uang.dari(j['nota_actual']),
      visit: Uang.dari(j['visit']),
      targetEc: Uang.dari(j['target_ec']).clamp(1, 1 << 30),
      targetVisit: Uang.dari(j['target_visit']).clamp(1, 1 << 30),
    );
  }
}

class KartuDash {
  const KartuDash({
    required this.rute,
    required this.nama,
    required this.targetOmset,
    required this.targetPersen,
    required this.minggu,
    required this.hari,
  });

  final String rute;
  final String nama;
  final int targetOmset;
  final double targetPersen;
  final CapaianDash minggu;
  final CapaianDash hari;

  static const totalKosong = KartuDash(
    rute: '',
    nama: 'Total',
    targetOmset: 0,
    targetPersen: 0,
    minggu: CapaianDash.kosong,
    hari: CapaianDash.kosong,
  );

  factory KartuDash.dari(Map<String, dynamic>? j) {
    if (j == null) return totalKosong;
    return KartuDash(
      rute: (j['rute']?.toString() ?? '').trim(),
      nama: (j['nama']?.toString() ?? '').trim(),
      targetOmset: Uang.dari(j['target_omset']),
      targetPersen: _desimal(j['target_persen']),
      minggu: CapaianDash.dari(
        j['minggu'] is Map
            ? Map<String, dynamic>.from(j['minggu'] as Map)
            : null,
      ),
      hari: CapaianDash.dari(
        j['hari'] is Map ? Map<String, dynamic>.from(j['hari'] as Map) : null,
      ),
    );
  }

  static double _desimal(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String get judul {
    if (rute.isEmpty) return nama.isEmpty ? 'Total' : nama;
    if (nama.isEmpty) return rute;
    return '$rute · $nama';
  }
}

class IsiDashboard {
  const IsiDashboard({
    required this.senin,
    required this.sabtu,
    required this.hari,
    required this.total,
    required this.rute,
  });

  final DateTime senin;
  final DateTime sabtu;
  final DateTime hari;
  final KartuDash total;
  final List<KartuDash> rute;

  static IsiDashboard kosong(DateTime senin, DateTime hari) {
    return IsiDashboard(
      senin: senin,
      sabtu: senin.add(const Duration(days: 5)),
      hari: hari,
      total: KartuDash.totalKosong,
      rute: const [],
    );
  }
}

class DashboardRepo {
  DashboardRepo(this._sb);
  final SupabaseClient _sb;

  Future<IsiDashboard> isi({
    required DateTime senin,
    required DateTime hari,
  }) async {
    final hasil = await Jaringan.denganUlang(
      () => _sb
          .rpc(
            'admin_dashboard',
            params: {
              'p_senin': Uang.isoHari(senin),
              'p_hari': Uang.isoHari(hari),
            },
          )
          .timeout(const Duration(seconds: 30)),
    );
    if (hasil is! Map) {
      throw Exception('Dashboard belum bisa dimuat.');
    }
    return _baca(Map<String, dynamic>.from(hasil));
  }

  IsiDashboard _baca(Map<String, dynamic> j) {
    final senin = _tgl(j['senin']) ?? DateTime.now();
    final sabtu = _tgl(j['sabtu']) ?? senin.add(const Duration(days: 5));
    final hari = _tgl(j['hari']) ?? DateTime.now();
    final rute = <KartuDash>[];
    final raw = j['rute'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        rute.add(KartuDash.dari(Map<String, dynamic>.from(e)));
      }
    }
    return IsiDashboard(
      senin: senin,
      sabtu: sabtu,
      hari: hari,
      total: KartuDash.dari(
        j['total'] is Map ? Map<String, dynamic>.from(j['total'] as Map) : null,
      ),
      rute: rute,
    );
  }

  DateTime? _tgl(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
  }

  Future<IsiTokoDash> tokoHari({
    required DateTime hari,
    required String rute,
  }) async {
    final hasil = await Jaringan.denganUlang(
      () => _sb
          .rpc(
            'admin_dashboard_toko',
            params: {
              'p_hari': Uang.isoHari(hari),
              'p_rute': rute,
            },
          )
          .timeout(const Duration(seconds: 30)),
    );
    if (hasil is! Map) {
      throw Exception('Daftar toko belum bisa dimuat.');
    }
    return IsiTokoDash.dari(Map<String, dynamic>.from(hasil));
  }
}

class IsiTokoDash {
  const IsiTokoDash({
    required this.hari,
    required this.rute,
    required this.toko,
  });

  final DateTime hari;
  final String rute;
  final List<TokoDash> toko;

  factory IsiTokoDash.dari(Map<String, dynamic> j) {
    final list = j['toko'];
    return IsiTokoDash(
      hari: Uang.hariDari(j['hari']) ?? DateTime.now(),
      rute: (j['rute']?.toString() ?? '').trim(),
      toko: [
        if (list is List)
          for (final e in list)
            if (e is Map) TokoDash.dari(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class TokoDash {
  const TokoDash({
    required this.idPelanggan,
    required this.nama,
    required this.rute,
    required this.nota,
    required this.sku,
    required this.order,
    required this.kiriman,
    required this.batal,
    required this.pending,
    required this.actual,
    required this.status,
    required this.jadwal,
    required this.isi,
    this.visitMasuk,
    this.visitKeluar,
  });

  final String idPelanggan;
  final String nama;
  final String rute;
  final int nota;
  final int sku;
  final int order;
  final int kiriman;
  final int batal;
  final int pending;
  final int actual;
  final String status;
  final bool jadwal;
  final DateTime? visitMasuk;
  final DateTime? visitKeluar;
  final Map<String, dynamic> isi;

  factory TokoDash.dari(Map<String, dynamic> m) {
    final sku = m['sku'];
    return TokoDash(
      idPelanggan: m['id_pelanggan']?.toString() ?? '',
      nama: (m['nama']?.toString() ?? '').trim(),
      rute: (m['rute_pengirim']?.toString() ?? '').trim(),
      nota: Uang.dari(m['nota']),
      sku: sku is List ? sku.length : 0,
      order: Uang.dari(m['order'] ?? m['nilai']),
      kiriman: Uang.dari(m['packed']),
      batal: Uang.dari(m['batal']),
      pending: Uang.dari(m['pending']),
      actual: Uang.dari(m['actual']),
      status: (m['status']?.toString() ?? '').trim().isEmpty
          ? '-'
          : m['status'].toString(),
      jadwal: m['jadwal'] == true,
      visitMasuk: DateTime.tryParse(m['visit_masuk']?.toString() ?? ''),
      visitKeluar: DateTime.tryParse(m['visit_keluar']?.toString() ?? ''),
      isi: m,
    );
  }

  String get teksVisit {
    if (visitMasuk == null) return jadwal ? 'jadwal' : '—';
    final masuk = _jam(visitMasuk!);
    if (visitKeluar == null) return masuk;
    return '$masuk–${_jam(visitKeluar!)}';
  }

  static String _jam(DateTime d) {
    final l = d.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
