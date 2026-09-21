import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pesan.dart';
import '../transaksi/input_order_layar.dart';
import '../transaksi/nota.dart';
import '../transaksi/riwayat_layar.dart';
import '../transaksi/transaksi_helper.dart';
import '../transaksi/transaksi_repo.dart';
import 'kunjungan_sesi.dart';
import 'pelanggan.dart';
import 'pelanggan_bloc.dart';
import 'scan_layar.dart';

class TokoLayar extends StatefulWidget {
  const TokoLayar({
    super.key,
    required this.toko,
    required this.bypass,
    this.selesaiMinggu = false,
  });

  final Pelanggan toko;
  final bool bypass;
  final bool selesaiMinggu;

  @override
  State<TokoLayar> createState() => _TokoLayarState();
}

class _TokoLayarState extends State<TokoLayar> {
  final Map<String, int> _keranjang = {};
  final _repo = TransaksiRepo(Supabase.instance.client);
  PotensiToko _potensi = PotensiToko.kosong;
  bool _potensiLoading = true;

  bool get _adaIsi => _keranjang.values.any((q) => q > 0);

  @override
  void initState() {
    super.initState();
    unawaited(_muatPotensi());
  }

  Future<void> _muatPotensi() async {
    final id = widget.toko.id.trim();
    if (id.isEmpty || id.startsWith('TMP')) {
      if (mounted) setState(() => _potensiLoading = false);
      return;
    }
    final awal = _potensiLoading;
    try {
      final nota = await _repo.potensiToko(id);
      if (!mounted) return;
      setState(() {
        _potensi = PotensiToko.dari(nota);
        _potensiLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _potensiLoading = false);
      if (awal && Jaringan.mati(e)) {
        tampilPesan(
          context,
          'Tidak ada internet. Potensi 10 minggu terakhir dibatalkan.',
        );
      }
    }
  }

  Future<void> _bukaRiwayat() async {
    if (widget.toko.id.startsWith('TMP')) {
      tampilPesan(
        context,
        'Toko baru belum punya id cloud. Sambungkan internet, unduh rute, lalu buka riwayat lagi.',
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => RiwayatLayar(toko: widget.toko)),
    );
    if (!mounted) return;
    setState(() => _potensiLoading = true);
    await _muatPotensi();
  }

  Future<void> _bukaInput() async {
    if (widget.toko.id.startsWith('TMP')) {
      tampilPesan(
        context,
        'Toko baru belum punya id cloud. Sambungkan internet, unduh rute, lalu input order lagi.',
      );
      return;
    }
    final updated = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => InputOrderLayar(
          toko: widget.toko,
          keranjangAwal: Map<String, int>.from(_keranjang),
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _keranjang
        ..clear()
        ..addAll(updated);
      _potensiLoading = true;
    });
    await _muatPotensi();
  }

  @override
  Widget build(BuildContext context) {
    final toko = widget.toko;
    final bypass = widget.bypass;
    final masuk = MingguKunjungan.chip(toko.waktuMasuk);
    final keluar = MingguKunjungan.chipKeluar(toko.waktuMasuk, toko.waktuKeluar);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        tampilPesan(
          context,
          widget.selesaiMinggu
              ? 'Masih di toko ini. Tekan "Kembali ke rute" di bawah.'
              : bypass
                  ? 'Kunjungan masih berlangsung. Tekan "Kembali ke rute (tanpa scan keluar)" di bawah.'
                  : 'Kunjungan masih berlangsung. Tekan "Selesai kunjungan" di bawah.',
        );
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Tema.seed,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: bypass
              ? const Text(
                  'MASUK TANPA SCAN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.yellow,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RefreshIndicator(
                  color: Tema.biru,
                  onRefresh: _muatPotensi,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                toko.nama,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Kode toko: ${toko.id}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              const Divider(height: 24),
                              _chipWaktu('Masuk: $masuk', Icons.login_outlined),
                              const SizedBox(height: 8),
                              _chipWaktu('Keluar: $keluar', Icons.logout_outlined),
                              const Divider(height: 24),
                              _blokPotensi(),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Tema.seed,
                                    side: const BorderSide(
                                      color: Tema.seed,
                                      width: 1.2,
                                    ),
                                  ),
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  label: const Text(
                                    'Riwayat transaksi',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _bukaRiwayat,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 40),
                      Center(
                        child: Text(
                          widget.selesaiMinggu
                              ? 'Catat order barang, lalu tekan "Kembali ke rute".'
                              : 'Catat order barang, lalu selesaikan kunjungan.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _adaIsi ? Colors.yellow.shade700 : Tema.seed,
                    foregroundColor: _adaIsi ? Colors.black : Colors.white,
                  ),
                  onPressed: _bukaInput,
                  child: Text(
                    _adaIsi ? 'Ubah order' : 'Input order',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _TombolKeluar(
                toko: toko,
                bypass: bypass,
                selesaiMinggu: widget.selesaiMinggu,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blokPotensi() {
    if (_potensiLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final teksOrder = _potensi.ada
        ? TransaksiHelper.rp(_potensi.rataOrder)
        : '-';
    final teksRasio = _potensi.ada && _potensi.rasio != null
        ? '${_potensi.rasio!.toStringAsFixed(1)}%'
        : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rata-rata 10 minggu terakhir',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        _barisPotensi('Potensi order', teksOrder),
        _barisPotensi('Potensi rasio laba', teksRasio),
      ],
    );
  }

  Widget _barisPotensi(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black),
            ),
          ),
          Text(
            nilai,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Tema.seed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipWaktu(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Tema.pxSudut),
        border: Border.all(color: Tema.seed, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Tema.seed),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Tema.seed,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _TombolKeluar extends StatefulWidget {
  const _TombolKeluar({
    required this.toko,
    required this.bypass,
    required this.selesaiMinggu,
  });

  final Pelanggan toko;
  final bool bypass;
  final bool selesaiMinggu;

  @override
  State<_TombolKeluar> createState() => _TombolKeluarState();
}

class _TombolKeluarState extends State<_TombolKeluar> {
  Timer? _timer;
  int _sisa = 0;
  bool _kunci = false;

  @override
  void initState() {
    super.initState();
    if (widget.selesaiMinggu || widget.bypass) return;
    final masuk = MingguKunjungan.diMingguIni(widget.toko.waktuMasuk)
        ? widget.toko.waktuMasuk
        : null;
    if (masuk == null) return;
    final lokal = masuk.isUtc ? masuk.toLocal() : masuk;
    final elapsed = DateTime.now().difference(lokal).inSeconds;
    if (elapsed >= 60) return;
    _kunci = true;
    _sisa = 60 - elapsed;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_sisa > 1) {
        setState(() => _sisa--);
      } else {
        setState(() {
          _kunci = false;
          _sisa = 0;
        });
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _aksi() async {
    if (widget.selesaiMinggu || widget.bypass) {
      await KunjunganSesi.keluarKeDaftar(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: context.read<PelangganBloc>(),
          child: ScanLayar(
            toko: widget.toko,
            keluar: true,
            tampilBypass: false,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gaya = FilledButton.styleFrom(
      backgroundColor: _kunci
          ? Colors.grey.shade400
          : widget.selesaiMinggu
              ? Tema.seed
              : (widget.bypass ? Colors.blueGrey : Colors.red.shade700),
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey.shade400,
      disabledForegroundColor: Colors.white,
    );
    final teks = Text(
      _kunci
          ? 'Tunggu Sisa Kunjungan ($_sisa s)'
          : widget.selesaiMinggu
              ? 'Kembali ke rute'
              : (widget.bypass
                  ? 'Kembali ke rute (tanpa scan keluar)'
                  : 'Selesai kunjungan'),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    );
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: widget.bypass && !_kunci
          ? FilledButton(style: gaya, onPressed: _aksi, child: teks)
          : FilledButton.icon(
              style: gaya,
              onPressed: _kunci ? null : _aksi,
              icon: Icon(
                _kunci
                    ? Icons.lock_clock_outlined
                    : widget.selesaiMinggu
                        ? Icons.storefront_outlined
                        : Icons.logout_outlined,
              ),
              label: teks,
            ),
    );
  }
}
