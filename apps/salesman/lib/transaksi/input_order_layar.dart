import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../barang/barang.dart';
import '../barang/barang_bloc.dart';
import '../barang/barang_event.dart';
import '../barang/barang_pdf.dart';
import '../barang/barang_state.dart';
import '../barang/dialog_pesan_katalog.dart';
import '../pelanggan/pelanggan.dart';
import 'package:obos_core/obos_core.dart';
import 'bilah_aksi.dart';
import 'dialog_qty.dart';
import 'hasil_review.dart';
import 'kartu_barang.dart';
import 'review_order_layar.dart';
import 'transaksi_helper.dart';

class InputOrderLayar extends StatefulWidget {
  const InputOrderLayar({
    super.key,
    required this.toko,
    this.keranjangAwal,
    this.kembaliKeReview = false,
    this.idNotaEdit,
  });

  final Pelanggan toko;
  final Map<String, int>? keranjangAwal;
  final bool kembaliKeReview;
  final String? idNotaEdit;

  @override
  State<InputOrderLayar> createState() => _InputOrderLayarState();
}

class _InputOrderLayarState extends State<InputOrderLayar> {
  final Map<String, int> _keranjang = {};
  final _cari = TextEditingController();
  String _query = '';
  bool _sedangUnduhPdf = false;

  @override
  void initState() {
    super.initState();
    if (widget.keranjangAwal != null) {
      _keranjang.addAll(widget.keranjangAwal!);
    }
    context.read<BarangBloc>().add(MuatBarang());
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  bool get _adaIsi => _keranjang.values.any((q) => q > 0);

  int _qtyGrupTanpaIni(Barang barang, List<Barang> daftar) {
    final tanpa = Map<String, int>.from(_keranjang)..remove(barang.id);
    return TransaksiHelper.qtyGrup(
      barang: barang,
      keranjang: tanpa,
      daftar: daftar,
    );
  }

  void _snack(String pesan, {Color? warna, Color? teks}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: warna,
        content: Text(
          pesan,
          style: TextStyle(color: teks, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _cobaUnduh() async {
    context.read<BarangBloc>().add(MuatBarang(paksa: true));
  }

  Future<void> _pilihUnduhan(List<Barang> daftar) async {
    if (_sedangUnduhPdf) return;
    final pilihan = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Pilih unduhan',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Katalog / daftar harga'),
                  subtitle: const Text('PDF harga jual dan strata'),
                  onTap: () => Navigator.pop(ctx, 'harga'),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Perbarui stok'),
                  subtitle: const Text(
                    'Ambil stok terbaru dari server, lalu PDF',
                  ),
                  onTap: () => Navigator.pop(ctx, 'stok'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || pilihan == null) return;
    if (pilihan == 'harga') {
      await _unduhPdfHarga(daftar);
    } else if (pilihan == 'stok') {
      await _unduhPdfStok();
    }
  }

  Future<void> _unduhPdfHarga(List<Barang> daftar) async {
    if (_sedangUnduhPdf) return;
    if (daftar.isEmpty) {
      _snack(
        'Belum ada daftar barang untuk diunduh. Muat katalog dulu, lalu coba lagi.',
        warna: const Color(0xFFF9A825),
        teks: Colors.black,
      );
      return;
    }
    setState(() => _sedangUnduhPdf = true);
    try {
      await BarangPdf.bagikanHarga(daftar);
    } catch (_) {
      if (!mounted) return;
      _snack(
        'Daftar harga belum bisa dibuat. Periksa koneksi, lalu coba lagi.',
        warna: const Color(0xFFC62828),
      );
    } finally {
      if (mounted) setState(() => _sedangUnduhPdf = false);
    }
  }

  Future<void> _unduhPdfStok() async {
    if (_sedangUnduhPdf) return;
    setState(() => _sedangUnduhPdf = true);
    try {
      final bloc = context.read<BarangBloc>();
      final next = bloc.stream.firstWhere(
        (s) => s is BarangSiap || s is BarangKosongNet || s is BarangGagal,
      );
      bloc.add(MuatBarang(paksa: true));
      final hasil = await next;
      if (!mounted) return;
      if (hasil is! BarangSiap || hasil.daftar.isEmpty) {
        _snack(
          'Stok belum bisa diunduh. Muat katalog dulu, lalu coba lagi.',
          warna: const Color(0xFFF9A825),
          teks: Colors.black,
        );
        return;
      }
      await BarangPdf.bagikanStok(hasil.daftar);
    } catch (_) {
      if (!mounted) return;
      _snack(
        'Daftar stok belum bisa dibuat. Periksa internet, lalu coba lagi.',
        warna: const Color(0xFFC62828),
      );
    } finally {
      if (mounted) setState(() => _sedangUnduhPdf = false);
    }
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
            'Apakah Anda yakin ingin menghapus semua kuantitas produk yang sudah Anda pilih?',
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
              setState(_keranjang.clear);
              Navigator.pop(ctx);
              _snack(
                'Keranjang sudah dikosongkan.',
                warna: const Color(0xFF2E7D32),
              );
            },
            child: const Text('Ya, kosongkan'),
          ),
        ],
      ),
    );
  }

  void _keluar() => Navigator.pop(context, _keranjang);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _keluar();
      },
      child: BlocConsumer<BarangBloc, BarangState>(
        listener: (context, state) {
          if (state is BarangKosongNet) {
            _snack(
              'Tidak ada internet. Sambungkan internet, lalu unduh katalog barang.',
              warna: const Color(0xFFF9A825),
              teks: Colors.black,
            );
          }
        },
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Input order'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_outlined),
                onPressed: _keluar,
              ),
              actions: [
                if (state is BarangSiap) ...[
                  IconButton(
                    tooltip: 'Unduh katalog atau stok',
                    onPressed: state.daftar.isEmpty || _sedangUnduhPdf
                        ? null
                        : () => _pilihUnduhan(state.daftar),
                    icon: _sedangUnduhPdf
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: 'Pembaruan katalog',
                    onPressed: () => DialogPesanKatalog.show(context),
                    icon: Badge(
                      isLabelVisible: state.belumDibaca > 0,
                      label: Text(
                        state.belumDibaca > 9 ? '9+' : '${state.belumDibaca}',
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      foregroundColor: _adaIsi ? Colors.red : Tema.seed,
                      disabledForegroundColor: Tema.seed,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Kosongkan semua jumlah',
                    onPressed: _adaIsi ? _kosongkan : null,
                  ),
                ],
                const SizedBox(width: 8),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: state is BarangMemuat
                    ? LinearProgressIndicator(
                        backgroundColor: theme.colorScheme.primary.withAlpha(30),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      )
                    : const SizedBox(height: 4),
              ),
            ),
            body: _badan(state, theme),
          );
        },
      ),
    );
  }

  Widget _badan(BarangState state, ThemeData theme) {
    if (state is BarangMemuat || state is BarangAwal) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 5,
        itemBuilder: (context, index) => const Card(
          margin: EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              height: 48,
              child: ColoredBox(color: Colors.black12),
            ),
          ),
        ),
      );
    }

    if (state is BarangKosongNet || state is BarangGagal) {
      final pesan = state is BarangGagal
          ? state.pesan
          : 'Katalog barang belum terunduh.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                state is BarangGagal
                    ? Icons.error_outline
                    : Icons.cloud_off_outlined,
                color: Tema.seed,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                pesan,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _cobaUnduh,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is! BarangSiap) return const SizedBox.shrink();

    final daftar = state.daftar;
    final saring = daftar.where((b) {
      final q = _query;
      if (q.isEmpty) return true;
      return b.nama.toLowerCase().contains(q) || b.id.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: TextField(
            controller: _cari,
            decoration: InputDecoration(
              hintText: 'Cari nama atau id barang...',
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_outlined),
                      onPressed: () {
                        setState(() {
                          _cari.clear();
                          _query = '';
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() => _query = value.trim().toLowerCase());
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              context.read<BarangBloc>().add(MuatBarang(paksa: true));
              await context.read<BarangBloc>().stream.firstWhere(
                    (s) => s is! BarangMemuat,
                  );
            },
            child: saring.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.35,
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
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: saring.length,
                    itemBuilder: (context, index) {
                      final barang = saring[index];
                      final qty = _keranjang[barang.id] ?? 0;
                      final harga = TransaksiHelper.hargaJual(
                        barang: barang,
                        keranjang: _keranjang,
                        daftar: daftar,
                      );
                      return KartuBarang(
                        barang: barang,
                        qtyInput: qty,
                        qtyGrup: TransaksiHelper.qtyGrup(
                          barang: barang,
                          keranjang: _keranjang,
                          daftar: daftar,
                        ),
                        hargaDinamis: harga,
                        onTap: () {
                          setState(() {
                            _keranjang[barang.id] = qty + 1;
                          });
                        },
                        onLongPress: () {
                          DialogQty.show(
                            context,
                            barang: barang,
                            qtySekarang: qty,
                            qtyGrupTanpaIni: _qtyGrupTanpaIni(barang, daftar),
                            onTerapkan: (baru) {
                              setState(() {
                                if (baru <= 0) {
                                  _keranjang.remove(barang.id);
                                } else {
                                  _keranjang[barang.id] = baru;
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
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
                      onPressed: !_adaIsi
                          ? null
                          : () async {
                              if (widget.kembaliKeReview) {
                                Navigator.pop(context, _keranjang);
                                return;
                              }
                              final hasil =
                                  await Navigator.push<HasilReview>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReviewOrderLayar(
                                    toko: widget.toko,
                                    keranjangAwal: Map<String, int>.from(
                                      _keranjang,
                                    ),
                                    daftar: daftar,
                                    idNotaEdit: widget.idNotaEdit,
                                  ),
                                ),
                              );
                              if (hasil == null || !mounted) return;
                              setState(() {
                                _keranjang
                                  ..clear()
                                  ..addAll(hasil.keranjang);
                              });
                              if (!hasil.selesai) return;
                              final pesan = hasil.pesan;
                              if (pesan != null && pesan.isNotEmpty) {
                                _snack(
                                  pesan,
                                  warna: const Color(0xFF2E7D32),
                                );
                              }
                              await Future<void>.delayed(
                                const Duration(milliseconds: 700),
                              );
                              if (!mounted) return;
                              Navigator.pop(context, hasil.keranjang);
                            },
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
    );
  }
}
