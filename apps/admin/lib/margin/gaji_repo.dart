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

  Future<GajiSetelan> setelan() async {
    final hasil = await Jaringan.denganUlang(() {
      return _sb.rpc('admin_gaji_setelan').timeout(Jaringan.lambat);
    });
    if (hasil is Map) {
      return GajiSetelan.dari(Map<String, dynamic>.from(hasil));
    }
    if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      return GajiSetelan.dari(Map<String, dynamic>.from(hasil.first as Map));
    }
    return GajiSetelan.awal;
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
          'p_omset_semua': 0,
          'p_rasio_sales': 0,
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

  Future<IsiDashboard> dashboard({
    required DateTime senin,
    required DateTime hari,
  }) {
    return DashboardRepo(_sb).isi(senin: senin, hari: hari);
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

IsiGaji hitungGaji({
  required GajiSetelan setelan,
  required List<BarisMarginRute> ruteMargin,
  required IsiDashboard dash,
  required List<GajiAbsen> absen,
  Map<String, int> omsetRute = const {},
  Map<String, double> rasioRute = const {},
  Map<String, int> kasbonOrang = const {},
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
    final denom = idx.fold<int>(0, (a, i) => a + draf[i].margin);
    var sisa = setelan.bopMobil;
    for (var k = 0; k < idx.length; k++) {
      final i = idx[k];
      final v = k == idx.length - 1
          ? sisa
          : denom <= 0
              ? setelan.bopMobil ~/ idx.length
              : ((draf[i].margin / denom) * setelan.bopMobil).round();
      sisa -= v;
      draf[i].bop = v;
    }
  }

  final sales = <BarisGajiSales>[];
  var totNetT = 0;
  var totNetA = 0;
  for (final d in draf) {
    final netT = d.margin - d.bop - d.ongkir;
    final pct = netT == 0 ? 0.0 : d.netActual / netT;
    final benNet = (setelan.salesNet * pct).round();
    final benV = d.toko <= 0
        ? 0
        : ((setelan.salesVisit * d.visit) / d.toko).round();
    final benE =
        d.toko <= 0 ? 0 : ((setelan.salesEc * d.ec) / d.toko).round();
    totNetT += netT;
    totNetA += d.netActual;
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
    final penuh = (setelan.pengirim * pct).round();
    final orang = e.value;
    final hadir = [for (final o in orang) if (o.hari > 0) o];
    final pool = penuh * 2;
    final hari = hadir.fold<int>(0, (n, o) => n + o.hari);
    var sisa = pool;
    final gaji = <String, int>{};
    for (var i = 0; i < hadir.length; i++) {
      final o = hadir[i];
      final v = i == hadir.length - 1
          ? sisa
          : ((pool * o.hari) / hari).round();
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
  final poolG = (setelan.gudang * rasioP * slot).round();
  final hadirG = [for (final o in gd) if (o.hari > 0) o];
  final hariG = hadirG.fold<int>(0, (n, o) => n + o.hari);
  var sisaG = poolG;
  final gajiG = <String, int>{};
  for (var i = 0; i < hadirG.length; i++) {
    final o = hadirG[i];
    final v = i == hadirG.length - 1
        ? sisaG
        : hariG <= 0
            ? 0
            : ((poolG * o.hari) / hariG).round();
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
        penuh: (setelan.gudang * rasioP).round(),
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
        penuh: (setelan.admin * rasioP).round(),
        gaji: (setelan.admin * rasioP).round(),
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
