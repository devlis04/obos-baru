import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../barang/barang.dart';
import '../barang/barang_repo.dart';
import '../lantai.dart';
import '../umpan.dart';
import 'bilah_aksi.dart';
import 'dialog_qty.dart';
import 'input_pack_layar.dart';
import 'kartu_barang.dart';
import 'nota_repo.dart';
import 'transaksi_helper.dart';

class NotaReviewLayar extends StatefulWidget {
  const NotaReviewLayar({
    super.key,
    required this.nota,
    required this.namaSales,
    this.bukuHidup = true,
  });

  final RingkasNota nota;
  final String namaSales;
  final bool bukuHidup;

  @override
  State<NotaReviewLayar> createState() => _NotaReviewLayarState();
}

class _NotaReviewLayarState extends State<NotaReviewLayar> {
  final _notaRepo = NotaRepo(Supabase.instance.client);
  final _barangRepo = BarangRepo(Supabase.instance.client);
  bool _muat = true;
  bool _simpan = false;
  late RingkasNota _nota;
  List<Barang> _katalog = [];
  final Map<String, int> _keranjang = {};
  final Map<String, int> _qtyTersimpan = {};
  final Set<String> _idAsal = {};

  @override
  void initState() {
    super.initState();
    _nota = widget.nota;
    _muatData();
  }

  bool get _bisaUbah => widget.bukuHidup && _nota.bisaPack;

  bool get _kosong =>
      _keranjang.isEmpty || !_keranjang.values.any((q) => q > 0);

  num _sisaBuku(String id) {
    for (final b in _katalog) {
      if (b.id == id) return b.stok;
    }
    return 0;
  }

  num _maksPack(String id) => TransaksiHelper.maksPack(
        sisaBuku: _sisaBuku(id),
        qtyTersimpan: _qtyTersimpan[id] ?? 0,
      );

  bool get _adaBarisStokNol => _keranjang.entries.any(
        (e) => e.value > 0 && e.value > _maksPack(e.key),
      );

  Barang _kartu(Barang barang, int qty) {
    return barang.salin(
      stok: TransaksiHelper.sisaTampil(
        sisaBuku: barang.stok,
        qtyTersimpan: _qtyTersimpan[barang.id] ?? 0,
        qtyKeranjang: qty,
      ),
    );
  }

  List<Barang> get _dibeli {
    return _katalog.where((b) => (_keranjang[b.id] ?? 0) > 0).toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final items = await _notaRepo.item(_nota.idTransaksi);
      final ids =
          items.map((e) => e.idBarang).where((e) => e.isNotEmpty).toList();
      var katalog = <Barang>[];
      try {
        katalog = await _barangRepo.banyak(ids);
      } catch (_) {}
      final byId = {for (final b in katalog) b.id: b};
      for (final it in items) {
        final live = byId[it.idBarang];
        final dasar = live ??
            Barang(
              id: it.idBarang,
              idGrup: it.idGrupKunci,
              nama: it.nama,
              kategori: '',
              stok: 0,
              hargaBeli: 0,
              hargaJual: it.hargaDasarKunci,
              minStrat1: it.minStrat1,
              jualStrat1: it.jualStrat1,
              minStrat2: it.minStrat2,
              jualStrat2: it.jualStrat2,
              minStrat3: it.minStrat3,
              jualStrat3: it.jualStrat3,
              minStrat4: it.minStrat4,
              jualStrat4: it.jualStrat4,
              minStrat5: it.minStrat5,
              jualStrat5: it.jualStrat5,
            );
        byId[it.idBarang] = TransaksiHelper.pakaiKunciNota(dasar, it);
      }
      _katalog = byId.values.toList()
        ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
      _keranjang.clear();
      _qtyTersimpan.clear();
      _idAsal
        ..clear()
        ..addAll(ids);
      for (final it in items) {
        final qty = it.qtyPacked ?? it.qtyOrder;
        if (qty > 0) {
          _keranjang[it.idBarang] = qty;
          _qtyTersimpan[it.idBarang] = it.qtyPacked ?? 0;
        }
      }
      if (!mounted) return;
      setState(() => _muat = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      umpan(
        context,
        pesanGagal(e, 'Rincian barang pada nota ini belum bisa dimuat.'),
      );
    }
  }

  int _qtyGrupTanpaIni(Barang barang) {
    final tanpa = Map<String, int>.from(_keranjang)..remove(barang.id);
    return TransaksiHelper.qtyGrup(
      barang: barang,
      keranjang: tanpa,
      daftar: _katalog,
    );
  }

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

  Future<void> _bukaInput() async {
    if (!_bisaUbah || _simpan) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    final hasil = await Navigator.of(context).push<Map<String, int>>(
      ruteHalaman(
        InputPackLayar(
          namaToko: _nota.namaPelanggan,
          keranjangAwal: Map<String, int>.from(_keranjang),
          qtyTersimpan: Map<String, int>.from(_qtyTersimpan),
          daftarAwal: _katalog,
        ),
      ),
    );
    if (hasil == null || !mounted) return;
    _keranjang
      ..clear()
      ..addAll(hasil);
    _keranjang.removeWhere((_, qty) => qty <= 0);
    final kurang =
        _keranjang.keys.where((k) => !_katalog.any((b) => b.id == k)).toList();
    if (kurang.isNotEmpty) {
      try {
        final tambah = await _barangRepo.banyak(kurang);
        final byId = {for (final b in _katalog) b.id: b};
        for (final b in tambah) {
          byId[b.id] = b;
        }
        _katalog = byId.values.toList()
          ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _kirim() async {
    if (!_bisaUbah || _simpan) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    if (_kosong) {
      final ya = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Batalkan nota?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: IsiDialog(
            child: const Text(
              'Semua barang jumlahnya 0. Nota batal dan jumlah packing dikembalikan ke stok. Tidak bisa diubah lagi. Lanjutkan?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, batalkan'),
            ),
          ],
        ),
      );
      if (ya != true || !mounted) return;
    }

    setState(() => _simpan = true);
    final ids = {..._idAsal, ..._keranjang.keys};
    final baris = [
      for (final id in ids)
        {'id_barang': id, 'qty_packed': _keranjang[id] ?? 0},
    ];
    try {
      await _notaRepo.pack(_nota.idTransaksi, baris);
      if (!mounted) return;
      umpan(
        context,
        _kosong ? 'Nota dibatalkan.' : 'Packing tersimpan.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _simpan = false);
      umpan(context, pesanGagal(e, 'Packing belum tersimpan.'));
    }
  }

  Widget _bawah(ThemeData theme) {
    return BilahAksi(
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Total Pembayaran Final',
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
                        daftar: _katalog,
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
                      daftar: _katalog,
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
          if (_bisaUbah) ...[
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
                    onPressed:
                        _simpan || (!_kosong && _adaBarisStokNol) ? null : _kirim,
                    child: _simpan
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Simpan packing'),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dibeli = _dibeli;
    return Scaffold(
      appBar: AppBar(
        title: Text(_nota.namaPelanggan),
        actions: [
          if (_bisaUbah)
            IconButton(
              tooltip: 'Tambah / ubah item',
              onPressed: _muat || _simpan ? null : _bukaInput,
              icon: const Icon(Icons.arrow_forward_outlined),
            ),
        ],
      ),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  color: theme.colorScheme.primaryContainer.withAlpha(40),
                  child: Text(
                    'Total Pesanan: ${dibeli.length} Jenis Barang',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: dibeli.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.shopping_cart_outlined,
                                size: 64,
                                color: Tema.seed,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Keranjang packing kosong.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              if (_bisaUbah) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _bukaInput,
                                  child: const Text('Tambah barang'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: dibeli.length,
                          itemBuilder: (context, index) {
                            final barang = dibeli[index];
                            final qty = _keranjang[barang.id] ?? 0;
                            return KartuBarang(
                              barang: _kartu(barang, qty),
                              qtyInput: qty,
                              qtyGrup: TransaksiHelper.qtyGrup(
                                barang: barang,
                                keranjang: _keranjang,
                                daftar: _katalog,
                              ),
                              hargaDinamis: TransaksiHelper.hargaJual(
                                barang: barang,
                                keranjang: _keranjang,
                                daftar: _katalog,
                              ),
                              onTap: !_bisaUbah
                                  ? null
                                  : () => _setQty(barang.id, qty + 1),
                              onLongPress: !_bisaUbah
                                  ? null
                                  : () {
                                      DialogQty.show(
                                        context,
                                        barang: barang,
                                        qtySekarang: qty,
                                        qtyGrupTanpaIni:
                                            _qtyGrupTanpaIni(barang),
                                        onTerapkan: (n) => _setQty(barang.id, n),
                                      );
                                    },
                            );
                          },
                        ),
                ),
                _bawah(theme),
              ],
            ),
    );
  }
}
