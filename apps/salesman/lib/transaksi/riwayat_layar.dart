import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../barang/barang.dart';
import '../barang/barang_bloc.dart';
import '../barang/barang_event.dart';
import '../barang/barang_state.dart';
import '../jaringan.dart';
import '../pesan.dart';
import '../pelanggan/pelanggan.dart';
import '../pelanggan/pelanggan_cache.dart';
import 'package:obos_core/obos_core.dart';
import '../uang.dart';
import 'nota.dart';
import 'review_order_layar.dart';
import 'transaksi_cache.dart';
import 'transaksi_helper.dart';
import 'transaksi_repo.dart';

class RiwayatLayar extends StatefulWidget {
  const RiwayatLayar({
    super.key,
    this.toko,
    this.tanggal,
  }) : assert(toko != null || tanggal != null);

  final Pelanggan? toko;
  final DateTime? tanggal;

  @override
  State<RiwayatLayar> createState() => _RiwayatLayarState();
}

class _RiwayatLayarState extends State<RiwayatLayar> {
  final _repo = TransaksiRepo(Supabase.instance.client);
  bool _muat = true;
  List<Nota> _nota = [];
  int _antrian = 0;

  @override
  void initState() {
    super.initState();
    _muatNota();
  }

  void _snack(String pesan) {
    tampilPesan(context, pesan);
  }

  bool get _modeToko => widget.toko != null;

  bool get _tanggalHariIni {
    final t = widget.tanggal;
    if (t == null) return false;
    return MingguKunjungan.samaHari(t, DateTime.now());
  }

  String get _judul {
    if (_modeToko) {
      final nama = widget.toko!.nama.trim();
      return nama.isEmpty ? 'Riwayat transaksi' : nama;
    }
    if (_tanggalHariIni) return 'Rincian transaksi hari ini';
    return 'Rincian ${MingguKunjungan.tampil(widget.tanggal ?? DateTime.now())}';
  }

  Future<void> _muatNota() async {
    setState(() => _muat = true);
    try {
      await _repo.kirimTertunda();
      final List<Nota> data;
      if (_modeToko) {
        data = await _repo.untukToko(widget.toko!.id);
      } else {
        final t = widget.tanggal ?? DateTime.now();
        data = await _repo.untukRentang(
          dari: DateTime(t.year, t.month, t.day),
          sampai: DateTime(t.year, t.month, t.day, 23, 59, 59, 999),
        );
      }
      final antri = await TransaksiCache.jumlahSiapKirim();
      if (!mounted) return;
      setState(() {
        _nota = data;
        _antrian = antri;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      final antri = await TransaksiCache.jumlahSiapKirim();
      if (!mounted) return;
      setState(() {
        _nota = [];
        _antrian = antri;
        _muat = false;
      });
      _snack(
        Jaringan.mati(e)
            ? (_modeToko
                ? 'Tidak ada internet. Riwayat server dibatalkan. Nota di HP tetap ditampilkan.'
                : 'Tidak ada internet. Rincian nota tanggal ini dibatalkan.')
            : (_modeToko
                ? 'Riwayat transaksi toko ini belum bisa dimuat. Periksa internet, lalu tarik untuk menyegarkan.'
                : 'Rincian nota tanggal ini belum bisa dimuat. Periksa internet, lalu tarik untuk menyegarkan.'),
      );
    }
  }

  Color _warnaStatus(String label) {
    switch (label) {
      case 'Terkirim':
      case 'Sedang dikirim':
        return Colors.green;
      case 'Batal':
        return Colors.red;
      default:
        return Colors.amber.shade800;
    }
  }

  Widget _chip(String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tema.pxSudut),
        border: Border.all(color: warna, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: warna,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _chipStatus(Nota nota) =>
      _chip(nota.labelStatus, _warnaStatus(nota.labelStatus));

  Widget _uangRasio(String uang, String rasio) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          uang,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Tema.seed,
          ),
        ),
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

  Widget _nominal(Nota nota) {
    final order = TransaksiHelper.rp(nota.totalOrder);
    final rasioOrder = TransaksiHelper.rasioOmset(
      omset: nota.totalOrder,
      modal: nota.modalOrder,
    );
    if (!nota.punyaPacked) {
      return _uangRasio(order, rasioOrder);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _uangRasio('Order : $order', rasioOrder),
        const SizedBox(height: 2),
        _uangRasio(
          'Kiriman : ${TransaksiHelper.rp(nota.totalPacked)}',
          TransaksiHelper.rasioOmset(
            omset: nota.totalPacked,
            modal: nota.modalPacked,
          ),
        ),
        const SizedBox(height: 2),
        _uangRasio(
          'Actual : ${TransaksiHelper.rp(nota.totalActual)}',
          TransaksiHelper.rasioOmset(
            omset: nota.totalActual,
            modal: nota.modalActual,
          ),
        ),
      ],
    );
  }

  Widget _kolomUang(
    int nilai,
    String rasio, {
    TextStyle gayaUang = const TextStyle(fontWeight: FontWeight.bold),
    TextStyle? gayaRasio,
  }) {
    final angka = gayaUang.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      width: 168,
      child: Row(
        children: [
          Text('Rp', style: angka),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              Uang.angka(nilai),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: angka,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            child: Text(
              rasio,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: gayaRasio ??
                  TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRasio(int nilai, String rasio) {
    return _kolomUang(
      nilai,
      rasio,
      gayaUang: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Tema.seed,
      ),
      gayaRasio: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: Colors.grey.shade600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _barisTotal(String label, int nilai, String rasio) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _totalRasio(nilai, rasio),
          ),
        ),
      ],
    );
  }

  Future<List<Barang>> _katalog() async {
    final bloc = context.read<BarangBloc>();
    final sekarang = bloc.state;
    if (sekarang is BarangSiap && sekarang.daftar.isNotEmpty) {
      return sekarang.daftar;
    }
    try {
      final next = bloc.stream.firstWhere((s) => s is! BarangMemuat);
      bloc.add(MuatBarang());
      final hasil = await next;
      if (hasil is BarangSiap) return hasil.daftar;
    } catch (_) {}
    return const [];
  }

  Future<Pelanggan> _tokoNota(Nota nota) async {
    final ada = widget.toko;
    if (ada != null) return ada;
    final semua = await PelangganCache.semua();
    for (final t in semua) {
      if (t.id == nota.idPelanggan) return t;
    }
    return Pelanggan(
      id: nota.idPelanggan,
      nama: nota.namaPelanggan,
      rute: nota.rute,
    );
  }

  Future<void> _ubahNota(Nota nota) async {
    if (!nota.bisaDiubah) return;
    if (nota.keranjang.isEmpty) {
      _snack('Isi nota belum bisa dimuat. Periksa internet, lalu coba lagi.');
      return;
    }
    final daftar = await _katalog();
    if (!mounted) return;
    if (daftar.isEmpty) {
      _snack(
        'Katalog barang belum ada. Sambungkan internet, lalu coba lagi.',
      );
      return;
    }
    final toko = await _tokoNota(nota);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewOrderLayar(
          toko: toko,
          keranjangAwal: nota.keranjang,
          daftar: daftar,
          idNotaEdit: nota.id,
          bukaInputDariAppBar: true,
        ),
      ),
    );
    if (mounted) await _muatNota();
  }

  Future<void> _konfirmasiBatal(Nota nota) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Batalkan nota?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: IsiDialog(
          child: const Text(
            'Nota yang dibatalkan tidak bisa diubah lagi. Lanjutkan?',
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
    final hasil = await _repo.batal(nota);
    if (!mounted) return;
    _snack(hasil.pesan);
    if (hasil.ok) await _muatNota();
  }

  Widget _tombolAksi(Nota nota, {VoidCallback? sebelum}) {
    final gaya = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: Size.zero,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          style: gaya,
          onPressed: () {
            sebelum?.call();
            _ubahNota(nota);
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Ubah'),
        ),
        TextButton.icon(
          style: gaya.copyWith(foregroundColor: WidgetStateProperty.all(Colors.red)),
          onPressed: () {
            sebelum?.call();
            _konfirmasiBatal(nota);
          },
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Batalkan'),
        ),
      ],
    );
  }

  Future<void> _sheetBatal(Nota nota) async {
    final daftar = <({String nama, int qty, int nilai})>[];
    for (final it in nota.items) {
      if (it.qtyActual == null || it.qtyPacked == null) continue;
      final qty = it.qtyPacked! - it.qtyActual!;
      final nilai = it.omsetPacked - it.omsetActual;
      if (qty <= 0 && nilai <= 0) continue;
      daftar.add((
        nama: it.nama.trim().isEmpty ? it.idBarang : it.nama,
        qty: qty > 0 ? qty : 0,
        nilai: nilai > 0 ? nilai : 0,
      ));
    }
    daftar.sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    if (daftar.isEmpty) {
      _snack('Rincian barang batal belum bisa ditampilkan.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final tinggi = MediaQuery.of(ctx).size.height * 0.6;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: tinggi),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Barang dibatalkan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  'Nota: ${nota.id}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Batal ${TransaksiHelper.rp(nota.nilaiBatal)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const Divider(height: 24),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: daftar.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = daftar[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.nama,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Jumlah ${item.qty}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                TransaksiHelper.rp(item.nilai),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _barisLapisan(
    BarisNota item, {
    required bool tampilPacked,
    required bool tampilActual,
  }) {
    final gayaKiri = TextStyle(color: Colors.grey.shade600, fontSize: 12);
    const gayaNilai = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Tema.seed,
    );
    final gayaRasio = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 11,
      color: Colors.grey.shade600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget baris({
      required String label,
      required int qty,
      required int harga,
      required int subtotal,
      required String rasio,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 58,
              child: Text(label, style: gayaKiri),
            ),
            Expanded(
              child: Text(
                ': $qty pcs x ${Uang.rp(harga)}',
                style: gayaKiri,
              ),
            ),
            Text(Uang.rp(subtotal), style: gayaNilai),
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              child: Text(
                rasio,
                maxLines: 1,
                textAlign: TextAlign.right,
                style: gayaRasio,
              ),
            ),
          ],
        ),
      );
    }

    final packedQty = item.qtyPacked ?? 0;
    final packedHarga = item.hargaJualPacked ?? item.hargaJualOrder;
    final packedBeli = item.hargaBeliPacked ?? item.hargaBeliOrder;
    final actualQty = item.qtyActual;
    final actualHarga = item.hargaJualActual ??
        (item.hargaJualOrder > 0 ? item.hargaJualOrder : packedHarga);
    final actualBeli = item.hargaBeliActual ?? packedBeli;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.nama.isEmpty ? 'Barang' : item.nama,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        baris(
          label: 'Order',
          qty: item.qtyOrder,
          harga: item.hargaJualOrder,
          subtotal: item.omsetOrder,
          rasio: TransaksiHelper.rasioItem(
            hargaJual: item.hargaJualOrder,
            hargaBeli: item.hargaBeliOrder,
          ),
        ),
        if (tampilPacked)
          baris(
            label: 'Kiriman',
            qty: packedQty,
            harga: packedHarga,
            subtotal: item.omsetPacked,
            rasio: TransaksiHelper.rasioItem(
              hargaJual: packedHarga,
              hargaBeli: packedBeli,
            ),
          ),
        if (tampilActual)
          baris(
            label: 'Actual',
            qty: actualQty ?? 0,
            harga: actualHarga,
            subtotal: item.omsetActual,
            rasio: TransaksiHelper.rasioItem(
              hargaJual: actualHarga,
              hargaBeli: actualBeli,
            ),
          ),
      ],
    );
  }

  Future<List<BarisNota>> _muatItemSheet(Nota nota) async {
    try {
      final cloud = await _repo.itemNota(nota.id);
      if (cloud.isNotEmpty) return cloud;
    } catch (_) {}
    final lokal = [...nota.items]
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    return lokal;
  }

  Future<void> _sheetNota(Nota nota) async {
    if (!mounted) return;
    final futureItem = _muatItemSheet(nota);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return FutureBuilder<List<BarisNota>>(
          future: futureItem,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Rincian barang pada nota ini belum bisa ditampilkan.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final items = snapshot.data ?? [];
            final tanggal = Nota.teksWaktu(nota.waktuOrder);
            final namaToko = (nota.namaPelanggan.isEmpty
                    ? (widget.toko?.nama ?? '')
                    : nota.namaPelanggan)
                .toUpperCase();
            int omset(int Function(BarisNota) f) =>
                items.fold(0, (s, i) => s + f(i));
            int modal(int Function(BarisNota) f) =>
                items.fold(0, (s, i) => s + f(i));
            final totalOrder = omset((i) => i.omsetOrder);
            final modalOrder = modal((i) => i.modalOrder);
            final totalPacked = omset((i) => i.omsetPacked);
            final modalPacked = modal((i) => i.modalPacked);
            final totalActual = omset((i) => i.omsetActual);
            final modalActual = modal((i) => i.modalActual);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      namaToko,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Nota: ${nota.id}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (tanggal.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tanggal,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chipStatus(nota),
                        if (nota.lokal) ...[
                          const SizedBox(width: 6),
                          _chip('Belum unggah', Colors.orange.shade800),
                        ],
                        if (nota.pendingKirim) ...[
                          const SizedBox(width: 6),
                          _chip('Pending', Colors.orange.shade800),
                        ],
                        if (nota.bisaDiubah) ...[
                          const Spacer(),
                          _tombolAksi(
                            nota,
                            sebelum: () => Navigator.pop(ctx),
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 24),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Rincian barang pada nota ini belum bisa ditampilkan.',
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, idx) => _barisLapisan(
                            items[idx],
                            tampilPacked: nota.tampilPacked,
                            tampilActual: nota.tampilActual,
                          ),
                        ),
                      ),
                    const Divider(height: 24),
                    _barisTotal(
                      'Order',
                      totalOrder,
                      TransaksiHelper.rasioOmset(
                        omset: totalOrder,
                        modal: modalOrder,
                      ),
                    ),
                    if (nota.tampilPacked) ...[
                      const SizedBox(height: 8),
                      _barisTotal(
                        'Kiriman',
                        totalPacked,
                        TransaksiHelper.rasioOmset(
                          omset: totalPacked,
                          modal: modalPacked,
                        ),
                      ),
                    ],
                    if (nota.tampilActual) ...[
                      const SizedBox(height: 8),
                      _barisTotal(
                        'Actual',
                        totalActual,
                        TransaksiHelper.rasioOmset(
                          omset: totalActual,
                          modal: modalActual,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_judul),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _muat
              ? LinearProgressIndicator(
                  backgroundColor: theme.colorScheme.primary.withAlpha(30),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                )
              : const SizedBox(height: 4),
        ),
      ),
      body: _muat
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            )
          : Column(
              children: [
                if (_antrian > 0)
                  Material(
                    color: Tema.kuning,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _antrian == 1
                              ? '1 nota belum terunggah. Akan dicoba lagi saat ada internet.'
                              : '$_antrian nota belum terunggah. Akan dicoba lagi saat ada internet.',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
              onRefresh: _muatNota,
              child: _nota.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 160),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _modeToko
                                  ? 'Belum ada nota untuk toko ini.'
                                  : 'Belum ada nota untuk tanggal ini.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      itemCount: _nota.length,
                      itemBuilder: (context, index) {
                        final nota = _nota[index];
                        final tanggal = Nota.teksWaktu(nota.waktuOrder);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            onTap: () => _sheetNota(nota),
                            borderRadius: Tema.sudut,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nota.namaPelanggan.isEmpty
                                              ? (widget.toko?.nama ?? '')
                                              : nota.namaPelanggan,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          'Nota: ${nota.id}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (tanggal.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            tanggal,
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _chipStatus(nota),
                                      if (nota.lokal)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: _chip(
                                            'Belum unggah',
                                            Colors.orange.shade800,
                                          ),
                                        ),
                                      if (nota.pendingKirim)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: _chip(
                                            'Pending',
                                            Colors.orange.shade800,
                                          ),
                                        ),
                                      if (nota.nilaiBatal > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: InkWell(
                                            onTap: () => _sheetBatal(nota),
                                            borderRadius: BorderRadius.circular(
                                              Tema.pxSudut,
                                            ),
                                            child: _chip(
                                              'Batal ${TransaksiHelper.rp(nota.nilaiBatal)}',
                                              Colors.red,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      _nominal(nota),
                                    ],
                                  ),
                                ],
                              ),
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
