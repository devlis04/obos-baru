import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../barang/barang.dart';
import '../pelanggan/pelanggan.dart';
import 'package:obos_core/obos_core.dart';
import 'bilah_aksi.dart';
import 'dialog_qty.dart';
import 'hasil_review.dart';
import 'input_order_layar.dart';
import 'kartu_barang.dart';
import 'transaksi_helper.dart';
import 'transaksi_repo.dart';

class ReviewOrderLayar extends StatefulWidget {
  const ReviewOrderLayar({
    super.key,
    required this.toko,
    required this.keranjangAwal,
    required this.daftar,
    this.bukaInputDariAppBar = false,
    this.idNotaEdit,
  });

  final Pelanggan toko;
  final Map<String, int> keranjangAwal;
  final List<Barang> daftar;
  final bool bukaInputDariAppBar;
  final String? idNotaEdit;

  @override
  State<ReviewOrderLayar> createState() => _ReviewOrderLayarState();
}

class _ReviewOrderLayarState extends State<ReviewOrderLayar> {
  final Map<String, int> _keranjang = {};
  List<Barang> _dibeli = [];
  bool _simpan = false;
  final _repo = TransaksiRepo(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _keranjang.addAll(widget.keranjangAwal);
    _dibeli = _susun();
  }

  List<Barang> _susun() {
    return widget.daftar.where((b) {
      return (_keranjang[b.id] ?? 0) > 0;
    }).toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
  }

  void _segar() {
    setState(() => _dibeli = _susun());
  }

  int _qtyGrupTanpaIni(Barang barang) {
    final tanpa = Map<String, int>.from(_keranjang)..remove(barang.id);
    return TransaksiHelper.qtyGrup(
      barang: barang,
      keranjang: tanpa,
      daftar: widget.daftar,
    );
  }

  HasilReview _hasil(bool selesai, {String? pesan}) {
    return HasilReview(
      keranjang: Map<String, int>.from(_keranjang),
      selesai: selesai,
      pesan: pesan,
    );
  }

  Future<void> _bukaInput() async {
    final hasil = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => InputOrderLayar(
          toko: widget.toko,
          keranjangAwal: Map<String, int>.from(_keranjang),
          kembaliKeReview: true,
          idNotaEdit: widget.idNotaEdit,
        ),
      ),
    );
    if (!mounted || hasil == null) return;
    setState(() {
      _keranjang
        ..clear()
        ..addAll(hasil);
      _dibeli = _susun();
    });
  }

  Future<void> _simpanNota() async {
    if (_simpan) return;
    setState(() => _simpan = true);
    final hasil = await _repo.simpan(
      idPelanggan: widget.toko.id,
      namaPelanggan: widget.toko.nama,
      keranjang: Map<String, int>.from(_keranjang),
      daftar: widget.daftar,
      idTransaksi: widget.idNotaEdit,
    );
    if (!mounted) return;
    setState(() => _simpan = false);
    if (!hasil.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasil.pesan,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      HasilReview(
        keranjang: const {},
        selesai: true,
        pesan: hasil.pesan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kosong = !_keranjang.values.any((q) => q > 0);
    final labelSimpan =
        (widget.idNotaEdit ?? '').trim().isEmpty ? 'Simpan' : 'Simpan Perubahan';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _hasil(false));
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.toko.nama),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_outlined),
            onPressed: () => Navigator.pop(context, _hasil(false)),
          ),
          actions: [
            if (widget.bukaInputDariAppBar)
              IconButton(
                tooltip: 'Pilih barang',
                icon: const Icon(Icons.arrow_forward_outlined),
                onPressed: _bukaInput,
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              color: theme.colorScheme.primaryContainer.withAlpha(40),
              child: Text(
                'Total Pesanan: ${_dibeli.length} Jenis Barang',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Expanded(
              child: _dibeli.isEmpty
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
                            'Keranjang belanja kosong.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: widget.bukaInputDariAppBar
                                ? _bukaInput
                                : () => Navigator.pop(context, _hasil(false)),
                            child: const Text('Kembali Pilih Barang'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _dibeli.length,
                      itemBuilder: (context, index) {
                        final barang = _dibeli[index];
                        final qty = _keranjang[barang.id] ?? 0;
                        final harga = TransaksiHelper.hargaJual(
                          barang: barang,
                          keranjang: _keranjang,
                          daftar: widget.daftar,
                        );
                        return KartuBarang(
                          barang: barang,
                          qtyInput: qty,
                          qtyGrup: TransaksiHelper.qtyGrup(
                            barang: barang,
                            keranjang: _keranjang,
                            daftar: widget.daftar,
                          ),
                          hargaDinamis: harga,
                          onTap: () {
                            setState(() {
                              _keranjang[barang.id] = qty + 1;
                            });
                            _segar();
                          },
                          onLongPress: () {
                            DialogQty.show(
                              context,
                              barang: barang,
                              qtySekarang: qty,
                              qtyGrupTanpaIni: _qtyGrupTanpaIni(barang),
                              onTerapkan: (baru) {
                                setState(() {
                                  if (baru <= 0) {
                                    _keranjang.remove(barang.id);
                                  } else {
                                    _keranjang[barang.id] = baru;
                                  }
                                });
                                _segar();
                              },
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
                                daftar: widget.daftar,
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
                              daftar: widget.daftar,
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
                          onPressed: kosong || _simpan ? null : _simpanNota,
                          child: _simpan
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(labelSimpan),
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
