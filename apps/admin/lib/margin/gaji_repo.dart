import 'package:supabase_flutter/supabase_flutter.dart';

import '../dashboard/dashboard_repo.dart';
import '../jaringan.dart';
import '../uang.dart';
import 'margin_repo.dart';

class GajiSetelan {
  const GajiSetelan({
    required this.bopMobil,
    required this.ongkirSemua,
    required this.salesNet,
    required this.salesVisit,
    required this.salesEc,
    required this.pengirim,
    required this.gudang,
    required this.gudangSlot,
    required this.admin,
    required this.omsetSemua,
    required this.rasioSales,
    required this.visitTarget,
    required this.ecTarget,
  });

  final int bopMobil;
  final int ongkirSemua;
  final int salesNet;
  final int salesVisit;
  final int salesEc;
  final int pengirim;
  final int gudang;
  final int gudangSlot;
  final int admin;
  final int omsetSemua;
  final double rasioSales;
  final double visitTarget;
  final double ecTarget;

  static const awal = GajiSetelan(
    bopMobil: 1020000,
    ongkirSemua: 2000000,
    salesNet: 800000,
    salesVisit: 200000,
    salesEc: 200000,
    pengirim: 800000,
    gudang: 500000,
    gudangSlot: 4,
    admin: 800000,
    omsetSemua: 0,
    rasioSales: 0,
    visitTarget: 90,
    ecTarget: 70,
  );

  factory GajiSetelan.dari(Map<String, dynamic> m) {
    return GajiSetelan(
      bopMobil: Uang.dari(m['bop_mobil']),
      ongkirSemua: Uang.dari(m['ongkir_semua']),
      salesNet: Uang.dari(m['sales_net']),
      salesVisit: Uang.dari(m['sales_visit']),
      salesEc: Uang.dari(m['sales_ec']),
      pengirim: Uang.dari(m['pengirim']),
      gudang: Uang.dari(m['gudang']),
      gudangSlot: Uang.dari(m['gudang_slot']).clamp(1, 99),
      admin: Uang.dari(m['admin']),
      omsetSemua: Uang.dari(m['omset_semua']),
      rasioSales: _desimal(m['rasio_sales']),
      visitTarget: _desimal(m['visit_target']) == 0 ? 90 : _desimal(m['visit_target']),
      ecTarget: _desimal(m['ec_target']) == 0 ? 70 : _desimal(m['ec_target']),
    );
  }

  static double _desimal(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class GajiAbsen {
  const GajiAbsen({
    required this.email,
    required this.nama,
    required this.peran,
    required this.rute,
    required this.hari,
  });

  final String email;
  final String nama;
  final String peran;
  final String rute;
  final int hari;

  factory GajiAbsen.dari(Map<String, dynamic> m) {
    return GajiAbsen(
      email: (m['email']?.toString() ?? '').trim(),
      nama: (m['nama']?.toString() ?? '').trim(),
      peran: (m['peran']?.toString() ?? '').trim().toLowerCase(),
      rute: (m['rute']?.toString() ?? '').trim(),
      hari: Uang.dari(m['hari']),
    );
  }

  String get pasangan {
    final t = rute.toUpperCase();
    if (t.length > 1 && (t.endsWith('D') || t.endsWith('H'))) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }
}

class BarisGajiSales {
  const BarisGajiSales({
    required this.rute,
    required this.nama,
    required this.pengirim,
    required this.omsetTarget,
    required this.rasioTarget,
    required this.marginTarget,
    required this.bopTarget,
    required this.ongkirTarget,
    required this.netTarget,
    required this.netActual,
    required this.pctNet,
    required this.benNet,
    required this.toko,
    required this.visit,
    required this.benVisit,
    required this.ec,
    required this.benEc,
    required this.total,
  });

  final String rute;
  final String nama;
  final String pengirim;
  final int omsetTarget;
  final double rasioTarget;
  final int marginTarget;
  final int bopTarget;
  final int ongkirTarget;
  final int netTarget;
  final int netActual;
  final double pctNet;
  final int benNet;
  final int toko;
  final int visit;
  final int benVisit;
  final int ec;
  final int benEc;
  final int total;
}

class BarisGajiOrang {
  const BarisGajiOrang({
    required this.email,
    required this.nama,
    required this.rute,
    required this.hari,
    required this.penuh,
    required this.gaji,
    required this.kasbon,
  });

  final String email;
  final String nama;
  final String rute;
  final int hari;
  final int penuh;
  final int gaji;
  final int kasbon;
}

class IsiGaji {
  const IsiGaji({
    required this.sales,
    required this.pengirim,
    required this.gudang,
    required this.admin,
    required this.rasioPerusahaan,
    required this.netActual,
    required this.gajiSemua,
  });

  final List<BarisGajiSales> sales;
  final List<BarisGajiOrang> pengirim;
  final List<BarisGajiOrang> gudang;
  final List<BarisGajiOrang> admin;
  final double rasioPerusahaan;
  final int netActual;
  final int gajiSemua;

  int get sisaPerusahaan => netActual - gajiSemua;
}

class GajiRepo {
  GajiRepo(this._sb);

  final SupabaseClient _sb;

  GajiSetelan? _dariHasilSetelan(Object? hasil) {
    if (hasil is Map) {
      return GajiSetelan.dari(Map<String, dynamic>.from(hasil));
    }
    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return GajiSetelan.dari(Map<String, dynamic>.from(hasil.first as Map));
    }
    return null;
  }

  Future<GajiSetelan> _rpcSetelan([DateTime? senin]) async {
    final hasil = senin != null
        ? await _sb.rpc(
            'admin_gaji_setelan_minggu',
            params: {'p_senin': Uang.isoHari(senin)},
          ).timeout(Jaringan.cepat)
        : await Jaringan.denganUlang(() {
            return _sb.rpc('admin_gaji_setelan').timeout(Jaringan.lambat);
          });
    return _dariHasilSetelan(hasil) ?? GajiSetelan.awal;
  }

  Future<GajiSetelan> setelan({DateTime? senin}) async {
    if (senin != null) {
      try {
        return await _rpcSetelan(senin);
      } catch (_) {
        return _rpcSetelan();
      }
    }
    return _rpcSetelan();
  }

  Future<void> simpan(GajiSetelan s) {
    return Jaringan.denganUlang(() {
      return _sb.rpc(
        'admin_gaji_setelan_simpan',
        params: {
          'p_bop_mobil': s.bopMobil,
          'p_ongkir_semua': s.ongkirSemua,
          'p_sales_net': s.salesNet,
          'p_sales_visit': s.salesVisit,
          'p_sales_ec': s.salesEc,
          'p_pengirim': s.pengirim,
          'p_gudang': s.gudang,
          'p_gudang_slot': s.gudangSlot,
          'p_admin': s.admin,
          'p_omset_semua': s.omsetSemua,
          'p_rasio_sales': s.rasioSales,
          'p_visit_target': s.visitTarget,
          'p_ec_target': s.ecTarget,
        },
      ).timeout(Jaringan.lambat);
    });
  }

  Future<void> simpanTarget(List<Map<String, Object>> isi) {
    return Jaringan.denganUlang(() {
      return _sb.rpc(
        'admin_target_sales_simpan',
        params: {'p_isi': isi},
      ).timeout(Jaringan.lambat);
    });
  }

  Map<String, int> _petaEmailNilai(Object? hasil) {
    final out = <String, int>{};
    if (hasil is! List) return out;
    for (final e in hasil) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final email = (m['email']?.toString() ?? '').trim().toLowerCase();
      if (email.isEmpty) continue;
      out[email] = Uang.dari(m['nilai']);
    }
    return out;
  }

  Future<Map<String, int>> kasbon({
    required DateTime senin,
    required DateTime sabtu,
  }) async {
    final lapangan = <String, int>{};
    try {
      final hasil = await Jaringan.denganUlang(() {
        return _sb.rpc(
          'admin_gaji_kasbon',
          params: {
            'p_senin': Uang.isoHari(senin),
            'p_sabtu': Uang.isoHari(sabtu),
          },
        ).timeout(Jaringan.lambat);
      });
      lapangan.addAll(_petaEmailNilai(hasil));
    } catch (_) {}
    try {
      final hasil = await Jaringan.denganUlang(() {
        return _sb.rpc(
          'admin_gaji_kasbon_minggu',
          params: {'p_senin': Uang.isoHari(senin)},
        ).timeout(Jaringan.lambat);
      });
      lapangan.addAll(_petaEmailNilai(hasil));
    } catch (_) {}
    return lapangan;
  }

  Future<void> simpanKasbonMinggu({
    required DateTime senin,
    required List<Map<String, Object>> isi,
  }) {
    return Jaringan.denganUlang(() {
      return _sb.rpc(
        'admin_gaji_kasbon_minggu_simpan',
        params: {
          'p_senin': Uang.isoHari(senin),
          'p_isi': isi,
        },
      ).timeout(Jaringan.lambat);
    });
  }

  Future<List<GajiAbsen>> absen({
    required DateTime senin,
    required DateTime sabtu,
  }) async {
    final hasil = await Jaringan.denganUlang(() {
      return _sb.rpc(
        'admin_gaji_absen',
        params: {
          'p_senin': Uang.isoHari(senin),
          'p_sabtu': Uang.isoHari(sabtu),
        },
      ).timeout(Jaringan.lambat);
    });
    return [
      if (hasil is List)
        for (final e in hasil)
          if (e is Map) GajiAbsen.dari(Map<String, dynamic>.from(e)),
    ];
  }

  double _rasio(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  Map<String, dynamic>? _petaPertama(Object? hasil) {
    if (hasil is Map) return Map<String, dynamic>.from(hasil);
    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return Map<String, dynamic>.from(hasil.first as Map);
    }
    return null;
  }

  IsiDashboard? _dashDariRuteMinggu(
    Object? hasil,
    DateTime senin,
    DateTime hari,
  ) {
    if (hasil is! List) return null;
    final rute = <KartuDash>[];
    for (final e in hasil) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final kode = (m['rute']?.toString() ?? '').trim();
      if (kode.isEmpty) continue;
      final toko = Uang.dari(m['toko']);
      rute.add(
        KartuDash(
          rute: kode,
          nama: (m['nama']?.toString() ?? '').trim(),
          targetOmset: Uang.dari(m['omset']),
          targetPersen: _rasio(m['rasio']),
          minggu: CapaianDash.gaji(
            visit: Uang.dari(m['visit']),
            toko: toko,
            ec: Uang.dari(m['ec']),
          ),
          hari: CapaianDash.kosong,
        ),
      );
    }
    if (rute.isEmpty) return null;
    return IsiDashboard(
      senin: senin,
      sabtu: senin.add(const Duration(days: 5)),
      hari: hari,
      total: KartuDash.totalKosong,
      rute: rute,
    );
  }

  Future<IsiDashboard> _dashDariPatokan({
    required DateTime senin,
    required DateTime hari,
    required List<BarisMarginRute> rute,
  }) async {
    final kartu = <KartuDash>[];
    for (final r in rute) {
      var omset = 0;
      var rasio = 0.0;
      var toko = 0;
      try {
        final h = await _sb.rpc(
          'gaji_target_pada',
          params: {
            'p_rute': r.rute,
            'p_senin': Uang.isoHari(senin),
          },
        ).timeout(Jaringan.cepat);
        final m = _petaPertama(h);
        if (m != null) {
          omset = Uang.dari(m['omset']);
          rasio = _rasio(m['rasio']);
        }
      } catch (_) {}
      try {
        final n = await _sb.rpc(
          'gaji_n_toko_rute',
          params: {
            'p_rute': r.rute,
            'p_senin': Uang.isoHari(senin),
          },
        ).timeout(Jaringan.cepat);
        toko = Uang.dari(n);
      } catch (_) {}
      kartu.add(
        KartuDash(
          rute: r.rute,
          nama: r.nama,
          targetOmset: omset,
          targetPersen: rasio,
          minggu: CapaianDash.gaji(visit: 0, toko: toko, ec: 0),
          hari: CapaianDash.kosong,
        ),
      );
    }
    return IsiDashboard(
      senin: senin,
      sabtu: senin.add(const Duration(days: 5)),
      hari: hari,
      total: KartuDash.totalKosong,
      rute: kartu,
    );
  }

  Future<IsiDashboard> dashboard({
    required DateTime senin,
    required DateTime hari,
    List<BarisMarginRute> rute = const [],
  }) async {
    try {
      final hasil = await _sb.rpc(
        'admin_gaji_rute_minggu',
        params: {'p_senin': Uang.isoHari(senin)},
      ).timeout(const Duration(seconds: 45));
      final isi = _dashDariRuteMinggu(hasil, senin, hari);
      if (isi != null) return isi;
    } catch (_) {}
    try {
      return await DashboardRepo(_sb).isi(senin: senin, hari: hari);
    } catch (e) {
      if (rute.isEmpty) rethrow;
      return _dashDariPatokan(senin: senin, hari: hari, rute: rute);
    }
  }
}

int marginDari({required int omset, required double persen}) {
  if (omset <= 0 || persen <= 0) return 0;
  return ((omset * persen) / (100 + persen)).round();
}

String kunciKasbon(String email, String rute, String nama) {
  final e = email.trim().toLowerCase();
  if (e.isNotEmpty) return e;
  return '${rute.trim().toLowerCase()}|${nama.trim().toLowerCase()}';
}

String _pctTeks(double n) =>
    '${(n * 100).toStringAsFixed(2).replaceAll('.', ',')}%';

bool gajiPakaiExcel(DateTime senin) {
  final s = DateTime(senin.year, senin.month, senin.day);
  return !s.isBefore(DateTime(2026, 10, 12));
}

int gajiMround(num n, int kelipatan) {
  if (kelipatan == 0) return n.round();
  return ((n / kelipatan).round()) * kelipatan;
}

IsiGaji hitungGaji({
  required GajiSetelan setelan,
  required List<BarisMarginRute> ruteMargin,
  required IsiDashboard dash,
  required List<GajiAbsen> absen,
  Map<String, int> omsetRute = const {},
  Map<String, double> rasioRute = const {},
  Map<String, int> kasbonOrang = const {},
  bool rumusExcel = false,
}) {
  final netAkt = {for (final r in ruteMargin) r.rute: r.netMargin};
  final petaPeng = {for (final r in ruteMargin) r.rute: r.rutePengirim};

  final draf = <_DrafSales>[];
  for (final k in dash.rute) {
    if (k.rute.isEmpty) continue;
    draf.add(
      _DrafSales(
        rute: k.rute,
        nama: k.nama,
        pengirim: petaPeng[k.rute] ?? '',
        omset: omsetRute[k.rute] ?? k.targetOmset,
        persen: rasioRute[k.rute] ?? k.targetPersen,
        netActual: netAkt[k.rute] ?? 0,
        toko: k.minggu.targetVisit,
        visit: k.minggu.visit,
        ec: k.minggu.ecActual,
      ),
    );
  }
  draf.sort((a, b) => a.rute.toLowerCase().compareTo(b.rute.toLowerCase()));

  for (final d in draf) {
    d.margin = marginDari(omset: d.omset, persen: d.persen);
  }

  final denomMar = draf.fold<int>(0, (a, d) => a + d.margin);
  var sisaOngkir = setelan.ongkirSemua;
  for (var i = 0; i < draf.length; i++) {
    final v = i == draf.length - 1
        ? sisaOngkir
        : denomMar <= 0
            ? setelan.ongkirSemua ~/ draf.length
            : ((draf[i].margin / denomMar) * setelan.ongkirSemua).round();
    sisaOngkir -= v;
    draf[i].ongkir = v;
  }

  final grup = <String, List<int>>{};
  for (var i = 0; i < draf.length; i++) {
    final p = draf[i].pengirim;
    if (p.isEmpty) continue;
    grup.putIfAbsent(p, () => []).add(i);
  }
  for (final idx in grup.values) {
    final denom = rumusExcel
        ? idx.fold<int>(0, (a, i) => a + (draf[i].margin - draf[i].ongkir))
        : idx.fold<int>(0, (a, i) => a + draf[i].margin);
    var sisa = setelan.bopMobil;
    for (var k = 0; k < idx.length; k++) {
      final i = idx[k];
      final bagian = rumusExcel ? draf[i].margin - draf[i].ongkir : draf[i].margin;
      final v = k == idx.length - 1
          ? sisa
          : denom <= 0
              ? setelan.bopMobil ~/ idx.length
              : ((bagian / denom) * setelan.bopMobil).round();
      sisa -= v;
      draf[i].bop = v;
    }
  }

  final sales = <BarisGajiSales>[];
  var totNetT = 0;
  var totNetA = 0;
  for (final d in draf) {
    totNetT += d.margin - d.bop - d.ongkir;
    totNetA += d.netActual;
  }
  for (final d in draf) {
    final netT = d.margin - d.bop - d.ongkir;
    final pct = netT == 0 ? 0.0 : d.netActual / netT;
    late final int benNet;
    late final int benV;
    late final int benE;
    if (rumusExcel) {
      final ah = totNetT <= 0
          ? 0
          : gajiMround(setelan.omsetSemua * netT / totNetT, 5000);
      benNet = gajiMround(pct * ah, 500);
      final scanPct = d.toko <= 0 ? 0.0 : d.visit * 100.0 / d.toko;
      final ecPct = d.toko <= 0 ? 0.0 : d.ec * 100.0 / d.toko;
      benV = d.toko <= 0 || setelan.visitTarget <= 0
          ? 0
          : gajiMround(
              pct * setelan.salesVisit * (scanPct / setelan.visitTarget),
              500,
            );
      benE = d.toko <= 0 || setelan.ecTarget <= 0
          ? 0
          : gajiMround(
              pct * setelan.salesEc * (ecPct / setelan.ecTarget),
              500,
            );
    } else {
      benNet = (setelan.salesNet * pct).round();
      benV = d.toko <= 0
          ? 0
          : ((setelan.salesVisit * d.visit) / d.toko).round();
      benE =
          d.toko <= 0 ? 0 : ((setelan.salesEc * d.ec) / d.toko).round();
    }
    sales.add(
      BarisGajiSales(
        rute: d.rute,
        nama: d.nama,
        pengirim: d.pengirim,
        omsetTarget: d.omset,
        rasioTarget: d.persen,
        marginTarget: d.margin,
        bopTarget: d.bop,
        ongkirTarget: d.ongkir,
        netTarget: netT,
        netActual: d.netActual,
        pctNet: pct,
        benNet: benNet,
        toko: d.toko,
        visit: d.visit,
        benVisit: benV,
        ec: d.ec,
        benEc: benE,
        total: benNet + benV + benE,
      ),
    );
  }

  final rasioP = totNetT == 0 ? 0.0 : totNetA / totNetT;
  final netTPas = <String, int>{};
  final netAPas = <String, int>{};
  for (final s in sales) {
    if (s.pengirim.isEmpty) continue;
    netTPas[s.pengirim] = (netTPas[s.pengirim] ?? 0) + s.netTarget;
    netAPas[s.pengirim] = (netAPas[s.pengirim] ?? 0) + s.netActual;
  }

  final kirim = absen.where((a) => a.peran == 'pengirim').toList();
  final pasOrang = <String, List<GajiAbsen>>{};
  for (final a in kirim) {
    pasOrang.putIfAbsent(a.pasangan, () => []).add(a);
  }
  final pengirim = <BarisGajiOrang>[];
  for (final e in pasOrang.entries) {
    final t = netTPas[e.key] ?? 0;
    final a = netAPas[e.key] ?? 0;
    final pct = t == 0 ? 0.0 : a / t;
    final penuh = rumusExcel
        ? gajiMround(setelan.pengirim * pct, 500)
        : (setelan.pengirim * pct).round();
    final orang = e.value;
    final hadir = [for (final o in orang) if (o.hari > 0) o];
    final pool = rumusExcel ? penuh : penuh * 2;
    final hari = hadir.fold<int>(0, (n, o) => n + o.hari);
    var sisa = pool;
    final gaji = <String, int>{};
    for (var i = 0; i < hadir.length; i++) {
      final o = hadir[i];
      final int v;
      if (rumusExcel) {
        v = hari <= 0 ? 0 : gajiMround((pool * o.hari) / hari, 500);
      } else if (i == hadir.length - 1) {
        v = sisa;
      } else {
        v = ((pool * o.hari) / hari).round();
      }
      sisa -= v;
      gaji[o.email] = v;
    }
    for (final o in orang) {
      pengirim.add(
        BarisGajiOrang(
          email: o.email,
          nama: o.nama,
          rute: o.rute,
          hari: o.hari,
          penuh: penuh,
          gaji: gaji[o.email] ?? 0,
          kasbon: kasbonOrang[kunciKasbon(o.email, o.rute, o.nama)] ?? 0,
        ),
      );
    }
  }
  pengirim.sort((a, b) => a.rute.toLowerCase().compareTo(b.rute.toLowerCase()));

  final gd = absen.where((a) => a.peran == 'gudang').toList()
    ..sort((a, b) => a.rute.toLowerCase().compareTo(b.rute.toLowerCase()));
  final slot = setelan.gudangSlot;
  final poolG = rumusExcel
      ? gajiMround(setelan.gudang * rasioP, 500)
      : (setelan.gudang * rasioP * slot).round();
  final hadirG = [for (final o in gd) if (o.hari > 0) o];
  final hariG = hadirG.fold<int>(0, (n, o) => n + o.hari);
  var sisaG = poolG;
  final gajiG = <String, int>{};
  for (var i = 0; i < hadirG.length; i++) {
    final o = hadirG[i];
    final int v;
    if (rumusExcel) {
      v = hariG <= 0 ? 0 : gajiMround((poolG * o.hari) / hariG, 500);
    } else if (i == hadirG.length - 1) {
      v = sisaG;
    } else {
      v = hariG <= 0 ? 0 : ((poolG * o.hari) / hariG).round();
    }
    sisaG -= v;
    gajiG[o.email] = v;
  }
  final gudang = [
    for (final o in gd)
      BarisGajiOrang(
        email: o.email,
        nama: o.nama,
        rute: o.rute,
        hari: o.hari,
        penuh: rumusExcel
            ? gajiMround(setelan.gudang * rasioP, 500)
            : (setelan.gudang * rasioP).round(),
        gaji: gajiG[o.email] ?? 0,
        kasbon: kasbonOrang[kunciKasbon(o.email, o.rute, o.nama)] ?? 0,
      ),
  ];

  final ad = absen.where((a) => a.peran == 'admin').toList()
    ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
  final admin = [
    for (final o in ad)
      BarisGajiOrang(
        email: o.email,
        nama: o.nama,
        rute: o.rute,
        hari: o.hari,
        penuh: rumusExcel
            ? gajiMround(setelan.admin * rasioP, 500)
            : (setelan.admin * rasioP).round(),
        gaji: rumusExcel
            ? gajiMround(setelan.admin * rasioP, 500)
            : (setelan.admin * rasioP).round(),
        kasbon: kasbonOrang[kunciKasbon(o.email, o.rute, o.nama)] ?? 0,
      ),
  ];

  final gajiSemua = sales.fold<int>(0, (n, s) => n + s.total) +
      pengirim.fold<int>(0, (n, o) => n + o.gaji) +
      gudang.fold<int>(0, (n, o) => n + o.gaji) +
      admin.fold<int>(0, (n, o) => n + o.gaji);

  return IsiGaji(
    sales: sales,
    pengirim: pengirim,
    gudang: gudang,
    admin: admin,
    rasioPerusahaan: rasioP,
    netActual: totNetA,
    gajiSemua: gajiSemua,
  );
}

String teksRasioGaji(double n) => _pctTeks(n);

class _DrafSales {
  _DrafSales({
    required this.rute,
    required this.nama,
    required this.pengirim,
    required this.omset,
    required this.persen,
    required this.netActual,
    required this.toko,
    required this.visit,
    required this.ec,
  });

  final String rute;
  final String nama;
  final String pengirim;
  int omset;
  double persen;
  int margin = 0;
  final int netActual;
  final int toko;
  final int visit;
  final int ec;
  int bop = 0;
  int ongkir = 0;
}
