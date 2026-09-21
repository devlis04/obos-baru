import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:obos_core/obos_core.dart';

import '../absensi/absensi_repo.dart';
import '../rumus_sederhana.dart';
import '../umpan.dart';
import 'buku_repo.dart';
import 'opname_bagian.dart';
import 'opname_draf.dart';
import 'pilih_bagian_opname.dart';

class OpnameLayar extends StatefulWidget {
  const OpnameLayar({super.key});

  @override
  State<OpnameLayar> createState() => _OpnameLayarState();
}

class _OpnameLayarState extends State<OpnameLayar> {
  final _repo = BukuRepo(Supabase.instance.client);
  final _cariCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _muat = true;
  bool _segar = false;
  bool _proses = false;
  int _indeks = 0;
  String _cari = '';
  List<BarisBuku> _semua = [];
  int? _idBuku;
  Timer? _drafTunda;

  int _jumlahBagian = 1;

  int get _nBagian => _jumlahBagian < 1 ? 1 : _jumlahBagian;

  List<PotonganOpname<BarisBuku>> get _semuaPotong =>
      bagiOpname(_semua, jumlah: _nBagian, namaBarang: (o) => o.nama);

  PotonganOpname<BarisBuku> get _potongan {
    final semua = _semuaPotong;
    if (semua.isEmpty) {
      return PotonganOpname<BarisBuku>(
        indeks: 0,
        baris: const [],
        namaAwal: '',
        namaAkhir: '',
      );
    }
    return semua[_indeks.clamp(0, semua.length - 1)];
  }

  List<BarisBuku> get _tampil {
    final q = _cari.trim().toLowerCase();
    final sumber = _potongan.baris;
    if (q.isEmpty) return sumber;
    return sumber
        .where(
          (o) =>
              o.nama.toLowerCase().contains(q) ||
              o.idBarang.toLowerCase().contains(q),
        )
        .toList();
  }

  int get _terisi => _semua.where((o) => o.terhitungTerisi).length;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  @override
  void dispose() {
    _drafTunda?.cancel();
    final buku = _idBuku;
    final isi = {for (final o in _semua) o.idBarang: o.fisikCtrl.text};
    _scroll.dispose();
    _cariCtrl.dispose();
    for (final o in _semua) {
      o.dispose();
    }
    super.dispose();
    if (buku != null && _semua.isNotEmpty) {
      unawaited(OpnameDraf.simpan(buku: buku, isi: isi));
    }
  }

  Map<String, String> _teksFisik() => {
        for (final o in _semua) o.idBarang: o.fisikCtrl.text,
      };

  Future<void> _tulisDraf() async {
    final buku = _idBuku;
    if (buku == null || _semua.isEmpty) return;
    await OpnameDraf.simpan(buku: buku, isi: _teksFisik());
  }

  void _jadwalDraf() {
    _drafTunda?.cancel();
    _drafTunda = Timer(const Duration(milliseconds: 400), () {
      unawaited(_tulisDraf());
    });
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final buku = await AbsensiRepo(Supabase.instance.client).idBukuTerbuka();
      final list = await _repo.isi();
      if (!mounted) return;
      for (final o in _semua) {
        o.dispose();
      }
      final draf = await OpnameDraf.baca();
      if (buku == null) {
        await OpnameDraf.hapus();
      } else if (draf.buku != null && draf.buku != buku) {
        await OpnameDraf.hapus();
      } else if (draf.buku == buku) {
        for (final o in list) {
          if (o.stokFisik != null) continue;
          final teks = draf.isi[o.idBarang];
          if (teks == null) continue;
          o.fisikCtrl.text = teks;
          o.kotor = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _idBuku = buku;
        _semua = list;
        var n = 1;
        for (final o in list) {
          if (o.jumlahBagian > n) n = o.jumlahBagian;
        }
        _jumlahBagian = n;
        _muat = false;
        final potong = _semuaPotong;
        if (_indeks >= potong.length) _indeks = 0;
        if (potong.isNotEmpty && potong[_indeks].baris.isEmpty) {
          final isi = potong.indexWhere((p) => p.baris.isNotEmpty);
          _indeks = isi < 0 ? 0 : isi;
        }
      });
      if (list.isEmpty) {
        umpan(
          context,
          'Tidak ada buku stok terbuka. Scan masuk gudang dulu.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semua = [];
        _muat = false;
      });
      umpan(context, pesanGagal(e, 'Opname belum bisa dimuat.'));
    }
  }

  Future<void> _segarBuku({bool diam = false}) async {
    if (_muat || _segar || (_proses && !diam)) return;
    if (_semua.isEmpty) {
      await _muatData();
      return;
    }
    setState(() => _segar = true);
    await _tulisDraf();
    try {
      final buku = await AbsensiRepo(Supabase.instance.client).idBukuTerbuka();
      final list = await _repo.isi();
      if (!mounted) {
        for (final s in list) {
          s.dispose();
        }
        return;
      }
      if (buku == null || list.isEmpty || (_idBuku != null && buku != _idBuku)) {
        for (final s in list) {
          s.dispose();
        }
        if (_idBuku != null && buku != null && buku != _idBuku) {
          await OpnameDraf.hapus();
        }
        if (mounted) setState(() => _segar = false);
        await _muatData();
        return;
      }
      final draf = await OpnameDraf.baca();
      final petaDraf = draf.buku == buku ? draf.isi : <String, String>{};
      final lama = {for (final o in _semua) o.idBarang: o};
      final pakai = <BarisBuku>[];
      final buang = <BarisBuku>[];
      for (final s in list) {
        final ada = lama.remove(s.idBarang);
        if (ada == null) {
          if (s.stokFisik == null) {
            final teks = petaDraf[s.idBarang];
            if (teks != null) {
              s.fisikCtrl.text = teks;
              s.kotor = true;
            }
          }
          pakai.add(s);
        } else {
          ada.ikutiBuku(s);
          buang.add(s);
          pakai.add(ada);
        }
      }
      final sisaLama = lama.values.toList();
      setState(() {
        _idBuku = buku;
        _semua = pakai;
        var n = 1;
        for (final o in pakai) {
          if (o.jumlahBagian > n) n = o.jumlahBagian;
        }
        _jumlahBagian = n;
        _segar = false;
        final potong = _semuaPotong;
        if (_indeks >= potong.length) _indeks = 0;
      });
      for (final s in buang) {
        s.dispose();
      }
      for (final s in sisaLama) {
        s.dispose();
      }
      if (!mounted) return;
      if (!diam) {
        umpan(
          context,
          'Jumlah kiriman dan hitung diperbarui. Fisik dari HP lain diisi ke kolom yang kosong. Yang sudah diketik di HP ini (belum Simpan) tidak diubah.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _segar = false);
      umpan(context, pesanGagal(e, 'Kiriman, hitung, dan fisik belum bisa diperbarui.'));
    }
  }

  Future<void> _gantiBagian() async {
    final pilih = await pilihBagianOpname(
      context,
      semua: _semua,
      jumlah: _nBagian,
      terpilih: _indeks,
    );
    if (!mounted || pilih == null) return;
    setState(() {
      _indeks = pilih;
      _cari = '';
      _cariCtrl.clear();
    });
  }

  void _tunjukSku(BarisBuku sku) {
    final potong = _semuaPotong;
    final idx = potong.indexWhere(
      (p) => p.baris.any((b) => b.idBarang == sku.idBarang),
    );
    setState(() {
      if (idx >= 0) _indeks = idx;
      _cari = '';
      _cariCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final i = _tampil.indexWhere((o) => o.idBarang == sku.idBarang);
      if (i < 0) return;
      _scroll.animateTo(
        (i * 168.0).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _tekanSimpan() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_simpan());
    });
  }

  Future<void> _simpan() async {
    if (_proses || _segar || _semua.isEmpty) return;
    final rusak = _semua.where((o) => o.fisikTerisi && o.fisikAngka == null).toList();
    if (rusak.isNotEmpty) {
      _tunjukSku(rusak.first);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rumus tidak valid'),
          content: IsiDialog(
            child: Text(
              'Jumlah fisik tidak bisa dibaca: ${rusak.first.nama}.\n'
              'Gunakan angka atau rumus + − × ÷.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final kirim = _semua.where((o) => o.perluKirim).toList();
    if (kirim.isEmpty && _terisi == 0) {
      umpan(
        context,
        'Isi jumlah fisik, lalu tap Simpan. Tiap HP mengirim bagiannya sendiri.',
      );
      return;
    }
    setState(() => _proses = true);
    try {
      final hasil = await _repo.simpanOpname(kirim.map((o) => o.keKirim()).toList());
      for (final o in kirim) {
        o.stokFisik = o.fisikAngka;
        o.kotor = false;
      }
      await _segarBuku(diam: true);
      if (!mounted) return;
      setState(() => _proses = false);
      final tulis = hasil.ditulis;
      final lengkap = hasil.kurang == 0 && hasil.total > 0;
      umpan(
        context,
        tulis > 0
            ? (lengkap
                ? 'Terkirim $tulis SKU. Semua fisik sudah di server (${hasil.terisi}/${hasil.total}). Konfirmasi dan tutup buku dari web admin.'
                : 'Terkirim $tulis SKU dari HP ini. Server ${hasil.terisi}/${hasil.total}, kurang ${hasil.kurang}. HP yang belum mengirim: tap Simpan.')
            : (lengkap
                ? 'Semua fisik sudah di server (${hasil.terisi}/${hasil.total}). Konfirmasi dan tutup buku dari web admin.'
                : 'Tidak ada perubahan dari HP ini. Server ${hasil.terisi}/${hasil.total}, kurang ${hasil.kurang}. Refresh jika HP lain sudah Simpan.'),
        lama: const Duration(seconds: 8),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      var p = pesanGagal(e, 'Opname belum tersimpan.');
      if (p.contains('schema cache') ||
          p.contains('could not find the function') ||
          p.contains('Fungsi server belum terpasang') ||
          e.toString().contains('tidak dikenal')) {
        p =
            'Fungsi simpan opname belum terpasang. Jalankan supabase/018_gudang_opname.sql di SQL Editor, lalu coba lagi.';
      }
      if (!mounted) return;
      umpan(context, p);
    }
  }

  double _lebarFisik(BuildContext context, String teks) {
    final contoh = teks.trim().isEmpty ? '0000' : teks;
    final gaya = Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final ukur = TextPainter(
      text: TextSpan(text: contoh, style: gaya),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return (ukur.width + 24).clamp(56.0, 220.0);
  }

  @override
  Widget build(BuildContext context) {
    final potong = _potongan;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _muat || _semua.isEmpty
              ? 'Stok opname'
              : (_nBagian <= 1
                  ? 'Stok opname'
                  : 'Stok opname · $_nBagian bagian'),
        ),
        actions: [
          if (!_muat && _nBagian > 1)
            IconButton(
              tooltip: 'Ganti bagian',
              onPressed: _gantiBagian,
              icon: const Icon(Icons.grid_view_outlined),
            ),
        ],
      ),
      floatingActionButton: _semua.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'opname_simpan',
              onPressed: _proses || _segar ? null : _tekanSimpan,
              icon: _proses
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text('Simpan ($_terisi/${_semua.length})'),
            ),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: const Color(0xFFD6E8F7),
                  child: InkWell(
                    onTap: _nBagian > 1 ? _gantiBagian : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${potong.judulDari(_nBagian)} · ${potong.rentang}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_nBagian > 1)
                            const Text(
                              'Ganti',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Tema.biru,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _cariCtrl,
                    onChanged: (v) => setState(() => _cari = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama atau id barang',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _segarBuku(diam: true),
                    child: _tampil.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  _semua.isEmpty
                                      ? 'Tidak ada buku terbuka.'
                                      : 'Tidak ada barang di ${potong.judulDari(_nBagian)}.',
                                  style: TextStyle(color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: _tampil.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                            final o = _tampil[i];
                            final isi = o.fisikTerisi;
                            final beda = isi && o.selisihTampil != 0;
                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.nama,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 72,
                                          child: Text('Fisik'),
                                        ),
                                        SizedBox(
                                          width: _lebarFisik(
                                            context,
                                            o.fisikCtrl.text,
                                          ),
                                          child: Focus(
                                            onFocusChange: (punya) {
                                              if (punya) return;
                                              if (!o.fisikTerisi && o.stokFisik != null) {
                                                o.fisikCtrl.text = teksQty(o.stokFisik!);
                                                o.kotor = false;
                                              } else {
                                                final n = o.fisikAngka;
                                                if (n != null) {
                                                  o.fisikCtrl.text = teksQty(n);
                                                }
                                              }
                                              _jadwalDraf();
                                              setState(() {});
                                            },
                                            child: TextField(
                                              controller: o.fisikCtrl,
                                              keyboardType: TextInputType.text,
                                              inputFormatters: const [
                                                FormatRumusQty(),
                                              ],
                                              onChanged: (_) {
                                                o.kotor = true;
                                                _jadwalDraf();
                                                setState(() {});
                                              },
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                hintText: '0',
                                                contentPadding: EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (isi) ...[
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Selisih ${teksQty(o.selisihTampil)}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: beda
                                                    ? Colors.red
                                                    : Colors.green,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ),
              ],
            ),
    );
  }
}
