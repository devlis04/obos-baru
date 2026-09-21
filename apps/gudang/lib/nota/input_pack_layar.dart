import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../barang/barang.dart';
import '../barang/barang_cache.dart';
import '../barang/barang_repo.dart';
import 'package:obos_core/obos_core.dart';

import '../umpan.dart';
import 'bilah_aksi.dart';
import 'dialog_qty.dart';
import 'kartu_barang.dart';
import 'transaksi_helper.dart';

class InputPackLayar extends StatefulWidget {
  const InputPackLayar({
    super.key,
    required this.namaToko,
    required this.keranjangAwal,
    required this.qtyTersimpan,
    required this.daftarAwal,
  });

  final String namaToko;
  final Map<String, int> keranjangAwal;
  final Map<String, int> qtyTersimpan;
  final List<Barang> daftarAwal;

  @override
  State<InputPackLayar> createState() => _InputPackLayarState();
}

class _InputPackLayarState extends State<InputPackLayar> {
  final _repo = BarangRepo(Supabase.instance.client);
  final _cariCtrl = TextEditingController();
  final Map<String, int> _keranjang = {};
  final Map<String, Barang> _dikenal = {};
  final Set<String> _skuKunci = {};
  List<Barang> _tampilan = [];
  bool _memuat = false;
  String _query = '';
  Timer? _tunda;

  @override
  void initState() {
    super.initState();
    _keranjang.addAll(widget.keranjangAwal);
    for (final b in widget.daftarAwal) {
      _dikenal[b.id] = b;
      _skuKunci.add(b.id);
    }
    _siapCache();
  }

  Future<void> _siapCache() async {
    final cache = await BarangCache.semua();
    if (!mounted) return;
    for (final b in cache) {
      _dikenal.putIfAbsent(b.id, () => b);
    }
    _muatCari('');
  }

  @override
  void dispose() {
    _tunda?.cancel();
    _cariCtrl.dispose();
    super.dispose();
  }

  List<Barang> get _daftarHarga => _dikenal.values.toList();

  List<Barang> get _daftarTampil {
    final seen = <String>{};
    final out = <Barang>[];
    void tambah(Barang b) {
      if (seen.add(b.id)) out.add(b);
    }

    _keranjang.forEach((id, qty) {
      if (qty <= 0) return;
      final b = _dikenal[id];
      if (b != null) tambah(b);
    });
    for (final b in _tampilan) {
      tambah(b);
    }
    out.sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    return out;
  }

  Future<void> _muatCari(String kata) async {
    setState(() => _memuat = true);
    try {
      final hasil = await _repo.cari(kata);
      if (!mounted) return;
      for (final b in hasil) {
        final lama = _dikenal[b.id];
        if (lama != null && _skuKunci.contains(b.id)) {
          _dikenal[b.id] = lama.salin(stok: b.stok);
        } else {
          _dikenal[b.id] = b;
        }
      }
      setState(() {
        _tampilan = hasil;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      umpan(context, pesanGagal(e, 'Gagal memuat daftar barang.'));
    }
  }

  void _jadwalCari(String value) {
    _tunda?.cancel();
    _tunda = Timer(const Duration(milliseconds: 350), () {
      _muatCari(value);
    });
  }

  int _qtyGrupTanpaIni(Barang barang) {
    final tanpa = Map<String, int>.from(_keranjang)..remove(barang.id);
    return TransaksiHelper.qtyGrup(
      barang: barang,
      keranjang: tanpa,
      daftar: _daftarHarga,
    );
  }

  num _sisaBuku(String id) => _dikenal[id]?.stok ?? 0;

  num _maksPack(String id) => TransaksiHelper.maksPack(
        sisaBuku: _sisaBuku(id),
        qtyTersimpan: widget.qtyTersimpan[id] ?? 0,
      );

  Barang _kartu(Barang barang, int qty) {
    return barang.salin(
      stok: TransaksiHelper.sisaTampil(
        sisaBuku: barang.stok,
        qtyTersimpan: widget.qtyTersimpan[barang.id] ?? 0,
        qtyKeranjang: qty,
      ),
    );
  }

  bool get _adaBarisStokNol => _keranjang.entries.any(
        (e) => e.value > 0 && e.value > _maksPack(e.key),
      );

  void _setQty(String id, int qty) {
    if (qty > 0 && qty > _maksPack(id)) {
      umpan(
        context,
        _maksPack(id) <= 0
            ? 'Sisa stok 0. Barang ini tidak bisa dipacking.'
            : 'Sisa stok tidak cukup.',
      );
      return;
    }
    setState(() {
      if (qty <= 0) {
        _keranjang.remove(id);
      } else {
        _keranjang[id] = qty;
      }
    });
  }

  void _kosongkan() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Kosongkan keranjang?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      content: IsiDialog(
        child: const Text(
          'Semua jumlah yang sudah dipilih akan dihapus (jadi 0). Nota bisa dibatalkan dari halaman periksa jika keranjang kosong.',
        ),
      ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              setState(() => _keranjang.clear());
              Navigator.pop(ctx);
              umpan(
                context,
                'Keranjang sudah dikosongkan.',
              );
            },
            child: const Text('Ya, kosongkan'),
          ),
        ],
      ),
    );
  }

  void _kembali() {
    Navigator.pop(context, Map<String, int>.from(_keranjang));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daftar = _daftarHarga;
    final tampil = _daftarTampil;
    final adaIsi = _keranjang.values.any((q) => q > 0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _kembali();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.namaToko.trim().isEmpty ? 'Input packing' : widget.namaToko,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_outlined),
            onPressed: _kembali,
          ),
          actions: [
            IconButton(
              style: IconButton.styleFrom(
                foregroundColor: adaIsi ? Colors.red : Tema.seed,
                disabledForegroundColor: Tema.seed,
              ),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Kosongkan semua jumlah',
              onPressed: adaIsi ? _kosongkan : null,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: TextField(
                controller: _cariCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari nama atau id barang...',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_outlined),
                          onPressed: () {
                            setState(() {
                              _cariCtrl.clear();
                              _query = '';
                            });
                            _muatCari('');
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                  _jadwalCari(value);
                },
              ),
            ),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : tampil.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _query.isEmpty
                                ? Icons.inventory_2_outlined
                                : Icons.search_off_outlined,
                            size: 48,
                            color: Tema.seed,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'Master data produk kosong.'
                                : 'Barang tidak ditemukan.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: tampil.length,
                      itemBuilder: (context, index) {
                        final barang = tampil[index];
                        final qty = _keranjang[barang.id] ?? 0;
                        return KartuBarang(
                          barang: _kartu(barang, qty),
                          qtyInput: qty,
                          qtyGrup: TransaksiHelper.qtyGrup(
                            barang: barang,
                            keranjang: _keranjang,
                            daftar: daftar,
                          ),
                          hargaDinamis: TransaksiHelper.hargaJual(
                            barang: barang,
                            keranjang: _keranjang,
                            daftar: daftar,
                          ),
                          onTap: () => _setQty(barang.id, qty + 1),
                          onLongPress: () {
                            DialogQty.show(
                              context,
                              barang: barang,
                              qtySekarang: qty,
                              qtyGrupTanpaIni: _qtyGrupTanpaIni(barang),
                              onTerapkan: (n) => _setQty(barang.id, n),
                            );
                          },
                        );
                      },
                    ),
            ),
            BilahAksi(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Estimasi Total',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            TransaksiHelper.rp(
                              TransaksiHelper.totalNota(
                                keranjang: _keranjang,
                                daftar: daftar,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            TransaksiHelper.rasioKeranjang(
                              keranjang: _keranjang,
                              daftar: daftar,
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: SizedBox(
                        height: 46,
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: _keranjang.isEmpty || _adaBarisStokNol
                              ? null
                              : _kembali,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Periksa'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
