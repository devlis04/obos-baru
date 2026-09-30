import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../uang.dart';

class BarisMarginBuku {
  const BarisMarginBuku({
    required this.id,
    required this.tanggal,
    required this.ditutup,
    required this.nota,
    required this.omset,
    required this.modal,
    required this.margin,
    required this.marginRetur,
    required this.ongkir,
    required this.bop,
    required this.kasbon,
    required this.selisihOpname,
    required this.selisihOpnameHitung,
    required this.selisihOpnameManual,
  });

  final int id;
  final DateTime? tanggal;
  final bool ditutup;
  final int nota;
  final int omset;
  final int modal;
  final int margin;
  final int marginRetur;
  final int ongkir;
  final int bop;
  final int kasbon;
  final int selisihOpname;
  final int selisihOpnameHitung;
  final bool selisihOpnameManual;

  int get netMargin =>
      margin - marginRetur - bop - ongkir + selisihOpname;

  factory BarisMarginBuku.dari(Map<String, dynamic> m) {
    return BarisMarginBuku(
      id: Uang.dari(m['id']),
      tanggal: Uang.hariDari(m['tanggal']),
      ditutup: m['ditutup'] == true,
      nota: Uang.dari(m['nota']),
      omset: Uang.dari(m['omset']),
      modal: Uang.dari(m['modal']),
      margin: Uang.dari(m['margin']),
      marginRetur: Uang.dari(m['margin_retur']),
      ongkir: Uang.dari(m['ongkir']),
      bop: Uang.dari(m['bop']),
      kasbon: Uang.dari(m['kasbon']),
      selisihOpname: Uang.dari(m['selisih_opname']),
      selisihOpnameHitung: Uang.dari(m['selisih_opname_hitung']),
      selisihOpnameManual: m['selisih_opname_manual'] == true,
    );
  }
}

class BarisMarginRuteBuku {
  const BarisMarginRuteBuku({
    required this.id,
    required this.tanggal,
    required this.rute,
    required this.nama,
    required this.rutePengirim,
    required this.nota,
    required this.omset,
    required this.modal,
    required this.margin,
    required this.marginRetur,
    required this.bop,
  });

  final int id;
  final DateTime? tanggal;
  final String rute;
  final String nama;
  final String rutePengirim;
  final int nota;
  final int omset;
  final int modal;
  final int margin;
  final int marginRetur;
  final int bop;

  factory BarisMarginRuteBuku.dari(Map<String, dynamic> m) {
    return BarisMarginRuteBuku(
      id: Uang.dari(m['id']),
      tanggal: Uang.hariDari(m['tanggal']),
      rute: (m['rute']?.toString() ?? '').trim(),
      nama: (m['nama']?.toString() ?? '').trim(),
      rutePengirim: (m['rute_pengirim']?.toString() ?? '').trim(),
      nota: Uang.dari(m['nota']),
      omset: Uang.dari(m['omset']),
      modal: Uang.dari(m['modal']),
      margin: Uang.dari(m['margin']),
      marginRetur: Uang.dari(m['margin_retur']),
      bop: Uang.dari(m['bop']),
    );
  }
}

class BarisMarginRute {
  const BarisMarginRute({
    required this.rute,
    required this.nama,
    required this.rutePengirim,
    required this.nota,
    required this.omset,
    required this.modal,
    required this.margin,
    required this.marginRetur,
    required this.ongkir,
    required this.bop,
    required this.selisihOpname,
  });

  final String rute;
  final String nama;
  final String rutePengirim;
  final int nota;
  final int omset;
  final int modal;
  final int margin;
  final int marginRetur;
  final int ongkir;
  final int bop;
  final int selisihOpname;

  int get netMargin =>
      margin - marginRetur - bop - ongkir + selisihOpname;

  BarisMarginRute salin({int? ongkir, int? bop, int? selisihOpname}) {
    return BarisMarginRute(
      rute: rute,
      nama: nama,
      rutePengirim: rutePengirim,
      nota: nota,
      omset: omset,
      modal: modal,
      margin: margin,
      marginRetur: marginRetur,
      ongkir: ongkir ?? this.ongkir,
      bop: bop ?? this.bop,
      selisihOpname: selisihOpname ?? this.selisihOpname,
    );
  }
}

class IsiMargin {
  const IsiMargin({required this.buku, required this.rute});

  final List<BarisMarginBuku> buku;
  final List<BarisMarginRuteBuku> rute;

  static const kosong = IsiMargin(buku: [], rute: []);
}

class MarginRepo {
  MarginRepo(this._sb);

  final SupabaseClient _sb;

  Future<IsiMargin> isi() async {
    final hasil = await Jaringan.denganUlang(() async {
      final buku = await _sb.rpc('admin_margin_buku').timeout(Jaringan.lambat);
      final rute = await _sb.rpc('admin_margin_rute').timeout(Jaringan.lambat);
      return (buku, rute);
    });
    return IsiMargin(
      buku: [
        if (hasil.$1 is List)
          for (final e in hasil.$1 as List)
            if (e is Map) BarisMarginBuku.dari(Map<String, dynamic>.from(e)),
      ],
      rute: [
        if (hasil.$2 is List)
          for (final e in hasil.$2 as List)
            if (e is Map)
              BarisMarginRuteBuku.dari(Map<String, dynamic>.from(e)),
      ],
    );
  }

  Future<void> simpanSelisihOpname({
    required int id,
    required int nilai,
    required bool manual,
  }) {
    return Jaringan.denganUlang(() {
      return _sb.rpc(
        'admin_margin_set_selisih_opname',
        params: {
          'p_id': id,
          'p_nilai': nilai,
          'p_manual': manual,
        },
      ).timeout(Jaringan.lambat);
    });
  }
}
