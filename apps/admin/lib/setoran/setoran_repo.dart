import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../uang.dart';

int _n(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

class BarisSetoranRute {
  const BarisSetoranRute({
    required this.rute,
    required this.kiriman,
    required this.batal,
    required this.pending,
    required this.actual,
    required this.wajibKunci,
    required this.transfer,
    required this.tunai,
    required this.bop,
    required this.kasbon,
    this.kasbonSupir = 0,
    this.kasbonKenek = 0,
    this.namaSupir = '',
    this.namaKenek = '',
    required this.retur,
    required this.sudahSetor,
  });

  final String rute;
  final int kiriman;
  final int batal;
  final int pending;
  final int actual;
  final int wajibKunci;
  final int transfer;
  final int tunai;
  final int bop;
  final int kasbon;
  final int kasbonSupir;
  final int kasbonKenek;
  final String namaSupir;
  final String namaKenek;
  final int retur;
  final bool sudahSetor;

  int get cek => actual - transfer - tunai - bop - retur - kasbon;

  List<({String peran, String label, int klaim})> get orangKasbon {
    if (kasbonSupir == 0 && kasbonKenek == 0 && kasbon > 0) {
      return [(peran: 'kasbon', label: 'Kasbon', klaim: kasbon)];
    }
    final supir = namaSupir.trim().isEmpty ? 'Supir' : 'Supir $namaSupir';
    final kenek = namaKenek.trim().isEmpty ? 'Kenek' : 'Kenek $namaKenek';
    return [
      (peran: 'supir', label: supir, klaim: kasbonSupir),
      (peran: 'kenek', label: kenek, klaim: kasbonKenek),
    ];
  }

  static const kosong = BarisSetoranRute(
    rute: '',
    kiriman: 0,
    batal: 0,
    pending: 0,
    actual: 0,
    wajibKunci: 0,
    transfer: 0,
    tunai: 0,
    bop: 0,
    kasbon: 0,
    kasbonSupir: 0,
    kasbonKenek: 0,
    namaSupir: '',
    namaKenek: '',
    retur: 0,
    sudahSetor: false,
  );

  factory BarisSetoranRute.dari(Map<String, dynamic> m) {
    return BarisSetoranRute(
      rute: m['rute_pengirim']?.toString() ?? '',
      kiriman: _n(m['kiriman']),
      batal: _n(m['batal']),
      pending: _n(m['pending']),
      actual: _n(m['actual']),
      wajibKunci: _n(m['wajib_kunci']),
      transfer: _n(m['transfer']),
      tunai: _n(m['tunai']),
      bop: _n(m['bop']),
      kasbon: _n(m['kasbon']),
      kasbonSupir: _n(m['kasbon_supir']),
      kasbonKenek: _n(m['kasbon_kenek']),
      namaSupir: m['nama_supir']?.toString() ?? '',
      namaKenek: m['nama_kenek']?.toString() ?? '',
      retur: _n(m['retur']),
      sudahSetor: m['sudah_setor'] == true,
    );
  }

  factory BarisSetoranRute.jumlah(List<BarisSetoranRute> rute) {
    return BarisSetoranRute(
      rute: 'Jumlah',
      kiriman: rute.fold(0, (n, r) => n + r.kiriman),
      batal: rute.fold(0, (n, r) => n + r.batal),
      pending: rute.fold(0, (n, r) => n + r.pending),
      actual: rute.fold(0, (n, r) => n + r.actual),
      wajibKunci: rute.fold(0, (n, r) => n + r.wajibKunci),
      transfer: rute.fold(0, (n, r) => n + r.transfer),
      tunai: rute.fold(0, (n, r) => n + r.tunai),
      bop: rute.fold(0, (n, r) => n + r.bop),
      kasbon: rute.fold(0, (n, r) => n + r.kasbon),
      kasbonSupir: rute.fold(0, (n, r) => n + r.kasbonSupir),
      kasbonKenek: rute.fold(0, (n, r) => n + r.kasbonKenek),
      retur: rute.fold(0, (n, r) => n + r.retur),
      sudahSetor: rute.isNotEmpty && rute.every((r) => r.sudahSetor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BarisSetoranRute &&
      other.rute == rute &&
      other.kiriman == kiriman &&
      other.batal == batal &&
      other.pending == pending &&
      other.actual == actual &&
      other.wajibKunci == wajibKunci &&
      other.transfer == transfer &&
      other.tunai == tunai &&
      other.bop == bop &&
      other.kasbon == kasbon &&
      other.kasbonSupir == kasbonSupir &&
      other.kasbonKenek == kasbonKenek &&
      other.namaSupir == namaSupir &&
      other.namaKenek == namaKenek &&
      other.retur == retur &&
      other.sudahSetor == sudahSetor;

  @override
  int get hashCode => Object.hash(
        rute,
        kiriman,
        batal,
        pending,
        actual,
        wajibKunci,
        transfer,
        tunai,
        bop,
        kasbon,
        kasbonSupir,
        kasbonKenek,
        namaSupir,
        namaKenek,
        retur,
        sudahSetor,
      );
}

class RingkasSetoran {
  const RingkasSetoran({
    required this.adaBuku,
    this.idSetoranBuku,
    this.tanggal,
    this.ditutup = false,
    this.dariSnapshot = false,
    this.rute = const [],
    this.cek,
    this.tunaiAdmin,
    this.kasbon,
  });

  static const kosong = RingkasSetoran(adaBuku: false);

  final bool adaBuku;
  final int? idSetoranBuku;
  final DateTime? tanggal;
  final bool ditutup;
  final bool dariSnapshot;
  final List<BarisSetoranRute> rute;
  final Object? cek;
  final Object? tunaiAdmin;
  final Object? kasbon;

  BarisSetoranRute get total => BarisSetoranRute.jumlah(rute);

  @override
  bool operator ==(Object other) =>
      other is RingkasSetoran &&
      other.adaBuku == adaBuku &&
      other.idSetoranBuku == idSetoranBuku &&
      other.tanggal == tanggal &&
      other.ditutup == ditutup &&
      other.dariSnapshot == dariSnapshot &&
      other.rute.length == rute.length &&
      _samaRute(other.rute);

  bool _samaRute(List<BarisSetoranRute> lain) {
    for (var i = 0; i < rute.length; i++) {
      if (rute[i] != lain[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        adaBuku,
        idSetoranBuku,
        tanggal,
        ditutup,
        dariSnapshot,
        Object.hashAll(rute),
      );

  factory RingkasSetoran.dari(Map<String, dynamic> m) {
    final tgl = Uang.hariDari(m['tanggal']);
    final list = m['rute'];
    return RingkasSetoran(
      adaBuku: m['ada_buku'] == true,
      idSetoranBuku: (m['id_setoran_buku'] as num?)?.toInt(),
      tanggal: tgl,
      ditutup: m['ditutup'] == true,
      dariSnapshot: m['dari_snapshot'] == true,
      cek: m['cek'],
      tunaiAdmin: m['tunai_admin'],
      kasbon: m['kasbon'],
      rute: [
        if (list is List)
          for (final e in list)
            if (e is Map)
              BarisSetoranRute.dari(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class SkuSetoranRinci {
  const SkuSetoranRinci({
    required this.idBarang,
    required this.nama,
    required this.qty,
    required this.nilai,
    this.qtyPacked = 0,
    this.packed = 0,
    this.qtyBatal = 0,
    this.batal = 0,
    this.qtyActual = 0,
    this.actual = 0,
    this.qtyRetur = 0,
    this.nilaiRetur = 0,
  });

  final String idBarang;
  final String nama;
  final int qty;
  final int nilai;
  final int qtyPacked;
  final int packed;
  final int qtyBatal;
  final int batal;
  final int qtyActual;
  final int actual;
  final int qtyRetur;
  final int nilaiRetur;

  factory SkuSetoranRinci.dari(Map<String, dynamic> m) {
    final qtyPacked = _n(m['qty_packed'] ?? m['qty']);
    final packed = _n(m['packed'] ?? m['nilai']);
    return SkuSetoranRinci(
      idBarang: m['id_barang']?.toString() ?? '',
      nama: m['nama']?.toString() ?? '',
      qty: qtyPacked,
      nilai: packed,
      qtyPacked: qtyPacked,
      packed: packed,
      qtyBatal: _n(m['qty_batal']),
      batal: _n(m['batal']),
      qtyActual: _n(m['qty_actual']),
      actual: _n(m['actual']),
      qtyRetur: _n(m['qty_retur'] ?? m['qty']),
      nilaiRetur: _n(m['retur'] ?? m['nilai']),
    );
  }
}

class TokoSetoranRinci {
  const TokoSetoranRinci({
    required this.idPelanggan,
    required this.nama,
    required this.rutePengirim,
    required this.nilai,
    required this.sku,
    this.nota = 0,
    this.packed = 0,
    this.batal = 0,
    this.pending = 0,
    this.actual = 0,
    this.retur = 0,
    this.status = '-',
    this.notaList = const [],
  });

  final String idPelanggan;
  final String nama;
  final String rutePengirim;
  final int nilai;
  final List<SkuSetoranRinci> sku;
  final int nota;
  final int packed;
  final int batal;
  final int pending;
  final int actual;
  final int retur;
  final String status;
  final List<NotaSetoranRinci> notaList;

  factory TokoSetoranRinci.dari(Map<String, dynamic> m) {
    final list = m['sku'];
    final notas = m['nota_list'];
    final packed = _n(m['packed']);
    return TokoSetoranRinci(
      idPelanggan: m['id_pelanggan']?.toString() ?? '',
      nama: m['nama']?.toString() ?? '',
      rutePengirim: m['rute_pengirim']?.toString() ?? '',
      nilai: _n(m['nilai']),
      nota: _n(m['nota']),
      packed: packed,
      batal: _n(m['batal']),
      pending: _n(m['pending']),
      actual: _n(m['actual']),
      retur: _n(m['retur']),
      status: (m['status']?.toString() ?? '').trim().isEmpty
          ? '-'
          : m['status'].toString(),
      sku: [
        if (list is List)
          for (final e in list)
            if (e is Map)
              SkuSetoranRinci.dari(Map<String, dynamic>.from(e)),
      ],
      notaList: [
        if (notas is List)
          for (final e in notas)
            if (e is Map)
              NotaSetoranRinci.dari(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class NotaSetoranRinci {
  const NotaSetoranRinci({
    required this.id,
    required this.rute,
    required this.packed,
    required this.batal,
    required this.pending,
    required this.actual,
    required this.retur,
    required this.status,
    this.sku = const [],
  });

  final String id;
  final String rute;
  final int packed;
  final int batal;
  final int pending;
  final int actual;
  final int retur;
  final String status;
  final List<SkuSetoranRinci> sku;

  factory NotaSetoranRinci.dari(Map<String, dynamic> m) {
    final list = m['sku'];
    return NotaSetoranRinci(
      id: m['id']?.toString() ?? '',
      rute: m['rute']?.toString() ?? '',
      packed: _n(m['packed']),
      batal: _n(m['batal']),
      pending: _n(m['pending']),
      actual: _n(m['actual']),
      retur: _n(m['retur']),
      status: (m['status']?.toString() ?? '').trim().isEmpty
          ? '-'
          : m['status'].toString(),
      sku: [
        if (list is List)
          for (final e in list)
            if (e is Map)
              SkuSetoranRinci.dari(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class RinciSetoran {
  const RinciSetoran({
    required this.jenis,
    this.rute,
    this.tanggal,
    this.total = 0,
    this.toko = const [],
  });

  final String jenis;
  final String? rute;
  final DateTime? tanggal;
  final int total;
  final List<TokoSetoranRinci> toko;

  factory RinciSetoran.dari(Map<String, dynamic> m) {
    DateTime? tgl;
    final raw = m['tanggal']?.toString();
    if (raw != null && raw.isNotEmpty) tgl = DateTime.tryParse(raw);
    final list = m['toko'];
    return RinciSetoran(
      jenis: m['jenis']?.toString() ?? '',
      rute: m['rute']?.toString(),
      tanggal: tgl,
      total: _n(m['total']),
      toko: [
        if (list is List)
          for (final e in list)
            if (e is Map)
              TokoSetoranRinci.dari(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class BukuSetoranPilih {
  const BukuSetoranPilih({
    required this.id,
    required this.tanggal,
    required this.ditutup,
    this.adaSnapshot = false,
  });

  final int id;
  final DateTime tanggal;
  final bool ditutup;
  final bool adaSnapshot;

  factory BukuSetoranPilih.dari(Map<String, dynamic> m) {
    final tgl = Uang.hariDari(m['tanggal']) ?? DateTime.now();
    return BukuSetoranPilih(
      id: _n(m['id']),
      tanggal: DateTime(tgl.year, tgl.month, tgl.day),
      ditutup: m['ditutup'] == true,
      adaSnapshot: m['ada_snapshot'] == true,
    );
  }
}

class SiklusBuku {
  const SiklusBuku({
    this.adaBuku = false,
    this.pesan = '',
    this.siapTutup = false,
    this.malamBaruTertahan = false,
  });

  static const kosong = SiklusBuku();

  final bool adaBuku;
  final String pesan;
  final bool siapTutup;
  final bool malamBaruTertahan;

  factory SiklusBuku.dari(Map<String, dynamic> m) {
    return SiklusBuku(
      adaBuku: m['ada_buku'] == true,
      pesan: (m['pesan']?.toString() ?? '').trim(),
      siapTutup: m['siap_tutup'] == true,
      malamBaruTertahan: m['malam_baru_tertahan'] == true,
    );
  }
}

class SetoranRepo {
  SetoranRepo(this._sb);
  final SupabaseClient _sb;

  Map<String, dynamic> _pBuku(int? id) => {
        'p_id_setoran_buku': ?id,
      };

  Future<RingkasSetoran> ringkas({int? idBuku}) async {
    final hasil = await _sb
        .rpc('admin_setoran_kartu', params: _pBuku(idBuku))
        .timeout(Jaringan.lambat);
    if (hasil is! Map) return RingkasSetoran.kosong;
    return RingkasSetoran.dari(Map<String, dynamic>.from(hasil));
  }

  Future<SiklusBuku> siklus() async {
    final hasil = await _sb.rpc('admin_buku_siklus').timeout(Jaringan.cepat);
    if (hasil is! Map) return SiklusBuku.kosong;
    return SiklusBuku.dari(Map<String, dynamic>.from(hasil));
  }

  Future<List<BukuSetoranPilih>> daftarBuku() async {
    final hasil =
        await _sb.rpc('admin_setoran_buku_daftar').timeout(Jaringan.lambat);
    if (hasil is! List) return const [];
    return [
      for (final e in hasil)
        if (e is Map) BukuSetoranPilih.dari(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> simpanKartu({
    required int idBuku,
    Object? cek,
    Object? tunai,
    Object? kasbon,
  }) {
    return _sb.rpc(
      'admin_setoran_simpan',
      params: {
        'p_id_setoran_buku': idBuku,
        'p_cek': cek,
        'p_tunai': tunai,
        'p_kasbon': kasbon,
      },
    ).timeout(Jaringan.lambat);
  }

  Future<RinciSetoran> rinci({
    required String jenis,
    String? rute,
    int? idBuku,
  }) async {
    final hasil = await _sb.rpc(
      'admin_setoran_rinci',
      params: {
        'p_jenis': jenis,
        'p_rute': rute,
        ..._pBuku(idBuku),
      },
    ).timeout(Jaringan.lambat);
    if (hasil is! Map) {
      return RinciSetoran(jenis: jenis, rute: rute);
    }
    return RinciSetoran.dari(Map<String, dynamic>.from(hasil));
  }
}
