import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../lantai.dart';
import '../uang.dart';
import '../umpan.dart';
import 'retur_toko.dart';
import 'toko_repo.dart';

class _BarisRetur {
  _BarisRetur({
    required this.kode,
    required this.nama,
    this.harga = 0,
    int qty = 0,
  }) : qtyCtrl = TextEditingController(text: qty <= 0 ? '' : '$qty');

  final String kode;
  final String nama;
  final int harga;
  final TextEditingController qtyCtrl;

  int get qty {
    final digits = qtyCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  int get nilai => qty * harga;

  void dispose() => qtyCtrl.dispose();
}

class ReturTokoLayar extends StatefulWidget {
  const ReturTokoLayar({
    super.key,
    required this.namaToko,
    required this.idPelanggan,
    required this.tanggal,
  });

  final String namaToko;
  final String idPelanggan;
  final DateTime tanggal;

  @override
  State<ReturTokoLayar> createState() => _ReturTokoLayarState();
}

class _ReturTokoLayarState extends State<ReturTokoLayar> {
  final _repo = TokoRepo(Supabase.instance.client);
  final _cariCtrl = TextEditingController();
  final _baris = <_BarisRetur>[];
  Timer? _tunda;
  bool _muat = true;
  bool _proses = false;
  bool _dikunci = false;
  List<SaranBarang> _saran = [];

  int get _nilai => _baris.fold<int>(0, (a, b) => a + b.nilai);

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  @override
  void dispose() {
    _tunda?.cancel();
    _cariCtrl.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final list = await _repo.returTokoLihat(
        widget.tanggal,
        widget.idPelanggan,
      );
      var kunci = list.any((r) => r.dikunci);
      if (!kunci) {
        try {
          kunci = await _repo.returDikunci(widget.tanggal);
        } catch (_) {}
      }
      if (!mounted) return;
      for (final b in _baris) {
        b.dispose();
      }
      _baris
        ..clear()
        ..addAll([
          for (final r in list)
            _BarisRetur(kode: r.kode, nama: r.nama, harga: r.harga, qty: r.qty),
        ]);
      setState(() {
        _dikunci = kunci;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      umpan(context, pesanGagal(e, 'Retur toko belum bisa dimuat.'));
    }
  }

  void _tambah(String kode, String nama, int harga) {
    final kodeN = kode.trim();
    if (kodeN.isEmpty) return;
    for (final b in _baris) {
      if (b.kode == kodeN) {
        _cariCtrl.clear();
        setState(() => _saran = []);
        return;
      }
    }
    _baris.add(_BarisRetur(kode: kodeN, nama: nama.trim(), harga: harga));
    _cariCtrl.clear();
    setState(() => _saran = []);
  }

  void _cari(String q) {
    _tunda?.cancel();
    final teks = q.trim();
    if (teks.length < 2) {
      setState(() => _saran = []);
      return;
    }
    _tunda = Timer(const Duration(milliseconds: 280), () async {
      try {
        final next = await _repo.barangCari(teks);
        if (!mounted) return;
        setState(() => _saran = next);
      } catch (_) {
        if (!mounted) return;
        setState(() => _saran = []);
      }
    });
  }

  Future<void> _simpan() async {
    if (_dikunci || _proses) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    setState(() => _proses = true);
    try {
      final ok = await _repo.returTokoSimpan(
        tanggal: widget.tanggal,
        idPelanggan: widget.idPelanggan,
        baris: [
          for (final b in _baris)
            if (b.kode.isNotEmpty && b.qty > 0)
              {
                'kode_barang': b.kode,
                'nama_barang': b.nama,
                'qty': b.qty,
                'harga_jual': b.harga,
              },
        ],
      );
      if (!mounted) return;
      if (ok) {
        umpan(context, 'Retur toko disimpan.');
        Navigator.of(context).pop(true);
      } else {
        umpan(context, 'Retur toko gagal disimpan.');
      }
    } catch (e) {
      if (!mounted) return;
      umpan(
        context,
        pesanGagal(
          e,
          Jaringan.mati(e)
              ? 'Tidak ada internet. Retur belum tersimpan.'
              : 'Retur toko gagal disimpan.',
        ),
      );
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur barang'),
      ),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      Text(
                        widget.namaToko,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Klaim retur toko. Stok gudang bergeser saat disimpan, '
                        'seperti batal. Nilai mengurangi tagihan toko '
                        'dan masuk rumus setoran.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                      if (_dikunci) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Sudah dikunci. Tidak bisa diubah.',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (!_dikunci) ...[
                        TextField(
                          controller: _cariCtrl,
                          onChanged: _cari,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Cari nama atau kode barang',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        if (_saran.isNotEmpty)
                          ..._saran.map(
                            (s) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(s.nama),
                              subtitle: Text(
                                '${s.kode} · ${Uang.rp(s.harga)}',
                              ),
                              onTap: () => _tambah(s.kode, s.nama, s.harga),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (_baris.isEmpty)
                        Text(
                          'Belum ada barang retur di toko ini.',
                          style: TextStyle(color: Colors.grey.shade600),
                        )
                      else
                        for (final b in _baris)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.nama.isEmpty ? b.kode : b.nama,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${b.kode} · ${Uang.rp(b.nilai)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 72,
                                  child: TextField(
                                    controller: b.qtyCtrl,
                                    enabled: !_dikunci,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Qty',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                if (!_dikunci)
                                  IconButton(
                                    tooltip: 'Hapus',
                                    onPressed: () {
                                      b.dispose();
                                      setState(() => _baris.remove(b));
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        Text(
                          'Nilai retur ${Uang.rp(_nilai)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Tema.seed,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _dikunci || _proses ? null : _simpan,
                            child: _proses
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_dikunci ? 'Terkunci' : 'Simpan retur'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
