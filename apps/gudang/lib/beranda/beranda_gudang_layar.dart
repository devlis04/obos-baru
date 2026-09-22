import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../absensi/absensi_repo.dart';
import '../absensi/scan_absensi_layar.dart';
import '../barang/barang_repo.dart';
import '../jaringan.dart';
import '../lantai.dart';
import '../nota/nota_rute_layar.dart';
import '../stok/opname_layar.dart';
import '../umpan.dart';
import '../uang.dart';
import 'gudang_drawer.dart';
import 'kartu_repo.dart';
import 'ringkas_rute.dart';

class BerandaGudangLayar extends StatefulWidget {
  const BerandaGudangLayar({
    super.key,
    required this.nama,
    required this.peran,
    this.info,
  });

  final String nama;
  final String peran;
  final String? info;

  @override
  State<BerandaGudangLayar> createState() => _BerandaGudangLayarState();
}

class _BerandaGudangLayarState extends State<BerandaGudangLayar> {
  final _absensi = AbsensiRepo(Supabase.instance.client);
  final _kartu = KartuRepo(Supabase.instance.client);
  StatusAbsensi _status = StatusAbsensi.kosong;
  bool _muat = true;
  List<RingkasRute> _rute = [];
  DateTime? _pilihTanggalBuku;
  late DateTime _tanggal;
  bool _hidup = true;

  bool get _hariIni {
    final now = DateTime.now();
    return _tanggal.year == now.year &&
        _tanggal.month == now.month &&
        _tanggal.day == now.day;
  }

  String get _judul {
    if (_hidup && _hariIni) return 'Packing hari ini';
    return 'Packing ${Uang.tanggal(_tanggal)}';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _tanggal = DateTime(now.year, now.month, now.day);
    final info = widget.info;
    if (info != null && info.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        umpan(context, info);
      });
    }
    _muatData();
  }

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal buku',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    final hari = DateTime(picked.year, picked.month, picked.day);
    setState(() => _pilihTanggalBuku = hari);
    await _muatData();
  }

  Future<void> _muatData({bool diam = false}) async {
    if (!diam) setState(() => _muat = true);
    try {
      final status = await _absensi.status();
      final pilih = _pilihTanggalBuku;
      final buku = await _kartu.bukuHari(pilih);
      final now = DateTime.now();
      final tgl = pilih ??
          buku?.tanggal ??
          DateTime(now.year, now.month, now.day);
      final hidup = buku != null &&
          buku.hidup &&
          buku.tanggal.year == tgl.year &&
          buku.tanggal.month == tgl.month &&
          buku.tanggal.day == tgl.day;
      final list = await _kartu.untukTanggal(tgl);
      if (!mounted) return;
      setState(() {
        _status = status;
        _tanggal = tgl;
        _hidup = hidup;
        _rute = list;
        _muat = false;
      });
      unawaited(_isiKatalog());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rute = [];
        _muat = false;
      });
      umpan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Daftar packing dibatalkan. Sambungkan internet, lalu coba lagi.'
            : pesanGagal(
                e,
                'Daftar packing belum bisa dimuat. Periksa internet, lalu tarik untuk menyegarkan.',
              ),
      );
    }
  }

  Future<void> _isiKatalog() async {
    try {
      await BarangRepo(Supabase.instance.client).katalog();
    } catch (_) {}
  }

  Future<void> _bukaScan() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanAbsensiLayar(keluar: _status.masuk),
      ),
    );
    if (!mounted) return;
    if (ok == true || ok == null) await _muatData(diam: true);
  }

  Future<void> _bukaOpname() async {
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const OpnameLayar()),
    );
    if (mounted) await _muatData();
  }

  RingkasRute get _total {
    var jumlah = 0;
    var siap = 0;
    var oO = 0, oP = 0, oA = 0, lO = 0, lP = 0, lA = 0;
    for (final r in _rute) {
      jumlah += r.jumlahNota;
      siap += r.sudahSiap;
      oO += r.omsetOrder;
      oP += r.omsetPacked;
      oA += r.omsetActual;
      lO += r.labaOrder;
      lP += r.labaPacked;
      lA += r.labaActual;
    }
    return RingkasRute(
      rute: '',
      namaSales: 'Semua sales',
      jumlahNota: jumlah,
      sudahSiap: siap,
      omsetOrder: oO,
      omsetPacked: oP,
      omsetActual: oA,
      labaOrder: lO,
      labaPacked: lP,
      labaActual: lA,
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tema.pxSudut),
        border: Border.all(color: Tema.seed, width: 1.2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Tema.seed,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _chipStatus(bool masuk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: masuk ? const Color(0xFF2E7D32) : Tema.kuning,
        borderRadius: Tema.sudut,
      ),
      child: Text(
        masuk ? 'SUDAH ABSEN' : 'BELUM ABSEN',
        style: TextStyle(
          color: masuk ? Colors.white : Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _nominal(RingkasRute r) {
    const gaya = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Tema.seed,
    );
    Widget baris(String uang, String rasio) {
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(uang, style: gaya),
          Text(
            rasio,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        baris(
          'Order : ${Uang.rp(r.omsetOrder)}',
          Uang.rasio(omset: r.omsetOrder, laba: r.labaOrder),
        ),
        const SizedBox(height: 2),
        baris(
          'Kiriman : ${Uang.rp(r.omsetPacked)}',
          Uang.rasio(omset: r.omsetPacked, laba: r.labaPacked),
        ),
        const SizedBox(height: 2),
        baris(
          'Actual : ${Uang.rp(r.omsetActual)}',
          Uang.rasio(omset: r.omsetActual, laba: r.labaActual),
        ),
      ],
    );
  }

  Widget _kartuTotal() {
    final t = _total;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Tema.seed.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Semua sales',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip('Order: ${t.jumlahNota}'),
                      _chip('Siap: ${t.sudahSiap}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _nominal(t),
          ],
        ),
      ),
    );
  }

  Widget _kartuRute(RingkasRute r) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            ruteHalaman(
              NotaRuteLayar(
                tanggal: _tanggal,
                rute: r.rute,
                namaSales: r.namaSales,
                bukuHidup: _hidup,
              ),
            ),
          );
          if (mounted) await _muatData();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.namaSales,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip('Order: ${r.jumlahNota}'),
                        _chip('Siap: ${r.sudahSiap}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rute: ${r.rute}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _nominal(r),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final masuk = _status.masuk;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_outlined),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: Text(_judul),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _chipStatus(masuk)),
            ),
          ],
        ),
        drawer: GudangDrawer(
          nama: widget.nama,
          peran: widget.peran,
          sudahMasuk: masuk,
          onScanAbsensi: _bukaScan,
          onPilihTanggal: _pilihTanggal,
          onStokOpname: _bukaOpname,
        ),
        body: _muat
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_rute.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: _kartuTotal(),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _muatData(diam: true),
                      child: _rute.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                              children: [
                                const SizedBox(height: 80),
                                Center(
                                  child: Text(
                                    'Belum ada order ${Uang.tanggal(_tanggal)}.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                              itemCount: _rute.length,
                              itemBuilder: (context, index) =>
                                  _kartuRute(_rute[index]),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
