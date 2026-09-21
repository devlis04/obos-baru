import 'dart:async';

import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/kartu_toko.dart';
import '../lantai.dart';
import '../uang.dart';
import '../umpan.dart';
import 'cek_nota_layar.dart';
import 'chip_status.dart';
import 'harga_tebus.dart';
import 'kunjungan_sesi.dart';
import 'nota_sheet.dart';
import 'retur_toko.dart';
import 'retur_toko_layar.dart';
import 'retur_toko_sheet.dart';
import 'scan_toko_layar.dart';
import 'toko_repo.dart';

class _NotaOutlet {
  _NotaOutlet(this.nota);

  RingkasNota nota;
  bool sudahDicek = false;
  bool batalLokal = false;
  Map<String, int> qtyTebus = {};
  List<ItemNota> item = [];

  bool get masihDikirim => nota.status == 'dikirim';

  bool get wajibKunciHariIni => masihDikirim && !nota.pending;

  int get actualTampil {
    if (qtyTebus.isEmpty) {
      if (nota.status == 'batal' || batalLokal) return 0;
      if (nota.omsetActual > 0) return nota.omsetActual;
      return nota.omsetPacked;
    }
    return omsetTebus(item, qtyTebus);
  }

  int get batalTampil {
    final s = nota.omsetPacked - actualTampil;
    return s > 0 ? s : 0;
  }

  int get omsetActualKartu {
    if (qtyTebus.isNotEmpty) return omsetTebus(item, qtyTebus);
    if (nota.status == 'batal' || batalLokal) return 0;
    if (nota.waktuActual != null || nota.status == 'terkirim') {
      return nota.omsetActual;
    }
    return 0;
  }
}

class OutletTokoLayar extends StatefulWidget {
  const OutletTokoLayar({
    super.key,
    required this.toko,
    required this.tanggal,
    this.lihatSaja = false,
  });

  final KartuToko toko;
  final DateTime tanggal;
  final bool lihatSaja;

  @override
  State<OutletTokoLayar> createState() => _OutletTokoLayarState();
}

class _OutletTokoLayarState extends State<OutletTokoLayar> {
  final _repo = TokoRepo(Supabase.instance.client);
  late KartuToko _toko;
  bool _muat = true;
  bool _kunciProses = false;
  List<_NotaOutlet> _nota = [];
  List<BarisReturToko> _retur = [];

  @override
  void initState() {
    super.initState();
    _toko = widget.toko;
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() => _muat = true);
    try {
      final list = await _repo.notaToko(widget.tanggal, _toko.idPelanggan);
      final kartu = await _repo.kartu(widget.tanggal);
      var retur = <BarisReturToko>[];
      try {
        retur = await _repo.returTokoLihat(widget.tanggal, _toko.idPelanggan);
      } catch (_) {}
      final sama = kartu.where((t) => t.idPelanggan == _toko.idPelanggan);
      if (!mounted) return;
      final lama = {for (final n in _nota) n.nota.idTransaksi: n};
      setState(() {
        if (sama.isNotEmpty) _toko = sama.first;
        _nota = [
          for (final ringkas in list)
            _salinLokal(_NotaOutlet(ringkas), lama[ringkas.idTransaksi]),
        ];
        _retur = retur;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      umpan(context, pesanGagal(e, 'Nota toko belum bisa dimuat.'));
    }
  }

  _NotaOutlet _salinLokal(_NotaOutlet baru, _NotaOutlet? lama) {
    if (lama == null || !baru.masihDikirim) return baru;
    baru.item = lama.item;
    if (baru.nota.pending) return baru;
    baru.sudahDicek = lama.sudahDicek;
    baru.batalLokal = lama.batalLokal;
    baru.qtyTebus = Map<String, int>.from(lama.qtyTebus);
    return baru;
  }

  Future<List<ItemNota>> _isi(String id) async {
    final ada = _nota.where((n) => n.nota.idTransaksi == id);
    if (ada.isNotEmpty && ada.first.item.isNotEmpty) return ada.first.item;
    final list = await _repo.item(id);
    for (final n in _nota) {
      if (n.nota.idTransaksi == id) n.item = list;
    }
    return list;
  }

  List<_NotaOutlet> get _wajibHariIni =>
      _nota.where((n) => n.wajibKunciHariIni).toList();

  List<_NotaOutlet> get _akanDikunci =>
      _nota.where((n) => n.masihDikirim && n.sudahDicek).toList();

  int get _nilaiNota {
    var n = 0;
    for (final nota in _nota) {
      if (nota.nota.pending && !nota.sudahDicek) continue;
      n += nota.actualTampil;
    }
    return n;
  }

  int get _nilaiRetur => _retur.fold<int>(0, (a, b) => a + b.nilai);

  int get _totalBayar {
    final s = _nilaiNota - _nilaiRetur;
    return s > 0 ? s : 0;
  }

  void _ganti(_NotaOutlet nota) {
    setState(() {
      _nota = [
        for (final n in _nota)
          n.nota.idTransaksi == nota.nota.idTransaksi ? nota : n,
      ];
    });
  }

  Future<bool> _konfirmasi({
    required String judul,
    required String isi,
    required String ya,
    bool bahaya = false,
  }) async {
    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: IsiDialog(child: Text(isi)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            style: bahaya
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ya),
          ),
        ],
      ),
    );
    return hasil == true;
  }

  Future<void> _pending(_NotaOutlet nota) async {
    if (!nota.nota.bisaPending) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    final ya = await _konfirmasi(
      judul: 'Pending nota?',
      isi:
          'Nota tetap dikirim, bukan dibatalkan. Barang kiriman tidak dikembalikan ke stok. '
          'Bisa dikunci hari ini setelah konfirmasi, atau muncul lagi besok. Lanjutkan?',
      ya: 'Ya, pending',
    );
    if (!ya || !mounted) return;
    try {
      await _repo.pendingNota(nota.nota.idTransaksi);
      if (!mounted) return;
      umpan(
        context,
        'Nota pending. Konfirmasi di toko ini jika toko minta dikirim hari ini.',
      );
      await _muatData();
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Pending belum tersimpan.'));
    }
  }

  Future<void> _batalkan(_NotaOutlet nota) async {
    final ya = await _konfirmasi(
      judul: 'Batalkan nota?',
      isi:
          'Nota ini dibatalkan di HP. Perubahan masuk ke server saat Kunci hasil toko. '
          'Jika keluar tanpa kunci, pembatalan ini dibuang. Lanjutkan?',
      ya: 'Ya, batalkan',
      bahaya: true,
    );
    if (!ya || !mounted) return;
    try {
      final item = await _isi(nota.nota.idTransaksi);
      if (!mounted) return;
      nota.item = item;
      nota.qtyTebus = {for (final it in item) it.idBarang: 0};
      nota.sudahDicek = true;
      nota.batalLokal = true;
      _ganti(nota);
      umpan(
        context,
        'Nota dibatalkan di HP. Tekan Kunci hasil toko agar masuk ke server.',
      );
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Rincian nota belum bisa dimuat.'));
    }
  }

  bool get _kembaliSaja => widget.lihatSaja || _toko.waktuKeluar != null;

  bool _bisaBukaKunci(_NotaOutlet nota) {
    if (widget.lihatSaja) return false;
    return nota.nota.status == 'terkirim' || nota.nota.status == 'batal';
  }

  Future<void> _bukaLaluUbah(_NotaOutlet nota) async {
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    try {
      final item = await _isi(nota.nota.idTransaksi);
      if (!mounted) return;
      nota.item = item;
      final qtyLama = {
        for (final it in item)
          it.idBarang: (nota.nota.status == 'batal' || nota.batalLokal)
              ? 0
              : (it.qtyActual ?? 0),
      };
      await _repo.bukaKunciNota(nota.nota.idTransaksi);
      if (!mounted) return;
      nota.qtyTebus = qtyLama;
      nota.sudahDicek = false;
      nota.batalLokal = false;
      nota.nota = nota.nota.salinDikirim();
      _ganti(nota);
      final hasil = await Navigator.of(context).push<CekNotaHasil>(
        ruteHalaman(
          CekNotaLayar(
            namaToko: _toko.nama,
            nota: nota.nota,
            qtyAwal: qtyLama,
          ),
        ),
      );
      if (!mounted || hasil == null) return;
      nota.qtyTebus = hasil.qtyTebus;
      nota.sudahDicek = true;
      nota.batalLokal = hasil.dibatalkan;
      _ganti(nota);
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Nota terkunci belum bisa diubah.'));
    }
  }

  Future<void> _ubah(_NotaOutlet nota) async {
    try {
      final item = await _isi(nota.nota.idTransaksi);
      if (!mounted) return;
      nota.item = item;
      final hasil = await Navigator.of(context).push<CekNotaHasil>(
        ruteHalaman(
          CekNotaLayar(
            namaToko: _toko.nama,
            nota: nota.nota,
            qtyAwal: nota.qtyTebus,
          ),
        ),
      );
      if (!mounted || hasil == null) return;
      nota.qtyTebus = hasil.qtyTebus;
      nota.sudahDicek = true;
      nota.batalLokal = hasil.dibatalkan;
      _ganti(nota);
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Gagal memuat isi nota.'));
    }
  }

  Future<void> _tampilkanSheet(_NotaOutlet nota) async {
    List<ItemNota> items;
    try {
      items = await _isi(nota.nota.idTransaksi);
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Rincian nota belum bisa dimuat.'));
      return;
    }
    if (!mounted) return;
    nota.item = items;
    final qty = nota.qtyTebus.isNotEmpty
        ? nota.qtyTebus
        : {
            for (final it in items)
              it.idBarang: (nota.nota.status == 'batal' || nota.batalLokal)
                  ? 0
                  : (it.qtyActual ?? 0),
          };
    final actualSheet = omsetTebus(items, qty);
    final bisaAksi = nota.masihDikirim && !nota.batalLokal;
    final bisaBuka = _bisaBukaKunci(nota);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
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
                  _toko.nama.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Nota: ${nota.nota.idTransaksi}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Order ${Uang.tanggalJam(nota.nota.waktuOrder)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (bisaAksi)
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _ubah(nota);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Ubah'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: nota.nota.bisaPending
                              ? TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    foregroundColor: Colors.orange.shade800,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _pending(nota);
                                  },
                                  icon: const Icon(
                                    Icons.schedule_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Pending'),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: Size.zero,
                              foregroundColor: Colors.red,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _batalkan(nota);
                            },
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Batalkan'),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (nota.batalLokal)
                  Text(
                    'Nota dibatalkan di HP. Menunggu Kunci hasil toko.',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (nota.nota.pending)
                  Text(
                    'Pending. Konfirmasi lalu kunci jika toko minta dikirim sekarang.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => barisBarangNota(
                        items[i],
                        qtyTebus: qty[items[i].idBarang],
                        hargaTebus: hargaJualTebus(
                          item: items[i],
                          semua: items,
                          qty: qty,
                        ),
                      ),
                    ),
                  ),
                const Divider(height: 24),
                barisUangNota(
                  'Order',
                  nota.nota.omsetOrder,
                  Uang.rasioOmset(
                    omset: nota.nota.omsetOrder,
                    modal: items.fold(0, (s, i) => s + i.qtyOrder * i.hargaBeli),
                  ),
                ),
                const SizedBox(height: 8),
                barisUangNota(
                  'Kiriman',
                  nota.nota.omsetPacked,
                  Uang.rasioOmset(
                    omset: nota.nota.omsetPacked,
                    modal: items.fold(0, (s, i) => s + i.qtyPacked * i.hargaBeli),
                  ),
                ),
                const SizedBox(height: 8),
                barisUangNota(
                  'Actual',
                  actualSheet,
                  Uang.rasioOmset(
                    omset: actualSheet,
                    modal: modalDariQty(items, qty),
                  ),
                ),
                const SizedBox(height: 16),
                if (bisaAksi)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: nota.sudahDicek
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              nota.sudahDicek = true;
                              _ganti(nota);
                            },
                      child: Text(
                        nota.sudahDicek ? 'Sudah dikonfirmasi' : 'Konfirmasi',
                      ),
                    ),
                  )
                else if (bisaBuka)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _bukaLaluUbah(nota);
                      },
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Ubah tebus'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _kunciHasilToko() async {
    final wajib = _wajibHariIni;
    final belum = _akanDikunci;
    if (belum.isEmpty || _kunciProses) return;
    if (!wajib.every((n) => n.sudahDicek)) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    final ya = await _konfirmasi(
      judul: 'Kunci hasil toko?',
      isi:
          'Toko harus membayar ${Uang.rp(_totalBayar)}'
          '${_nilaiRetur > 0 ? ' (retur ${Uang.rp(_nilaiRetur)})' : ''}. '
          '${belum.length} nota yang sudah dicek akan dikunci. '
          'Pending yang belum dikonfirmasi tidak dikunci.',
      ya: 'Ya, kunci',
    );
    if (!ya || !mounted) return;
    setState(() => _kunciProses = true);
    var unggah = 0;
    try {
      for (final n in belum) {
        final item = n.item.isEmpty ? await _isi(n.nota.idTransaksi) : n.item;
        n.item = item;
        final qty = n.qtyTebus.isNotEmpty
            ? n.qtyTebus
            : {for (final it in item) it.idBarang: it.qtyPacked};
        final baris = [
          for (final it in item)
            {'id_barang': it.idBarang, 'qty_actual': qty[it.idBarang] ?? 0},
        ];
        await _repo.kunciNota(
          idTransaksi: n.nota.idTransaksi,
          baris: baris,
        );
        unggah++;
      }
      if (!mounted) return;
      umpan(
        context,
        unggah == 1
            ? '1 nota dikunci.'
            : '$unggah nota dikunci.',
      );
      await _muatData();
    } catch (e) {
      if (!mounted) return;
      umpan(
        context,
        pesanGagal(
          e,
          unggah > 0
              ? 'Sebagian nota belum terkunci. Periksa status nota, lalu coba lagi.'
              : 'Nota belum terkunci.',
        ),
      );
    } finally {
      if (mounted) setState(() => _kunciProses = false);
    }
  }

  Future<void> _selesaiKunjungan() async {
    if (_kembaliSaja) {
      await KunjunganSesi.keluarKeDaftar();
      return;
    }
    if (_wajibHariIni.isNotEmpty) {
      umpan(
        context,
        'Tekan "Kunci hasil toko" dulu sebelum check-out. '
        'Nota pending boleh dibiarkan.',
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      ruteHalaman(ScanTokoLayar(toko: _toko, keluar: true)),
    );
    if (ok == true && mounted) await KunjunganSesi.keluarKeDaftar();
  }

  Future<void> _muatRetur() async {
    try {
      final retur = await _repo.returTokoLihat(
        widget.tanggal,
        _toko.idPelanggan,
      );
      if (!mounted) return;
      setState(() => _retur = retur);
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Retur toko belum bisa dimuat.'));
    }
  }

  Future<void> _bukaEditorRetur() async {
    await Navigator.of(context).push<bool>(
      ruteHalaman(
        ReturTokoLayar(
          namaToko: _toko.nama,
          idPelanggan: _toko.idPelanggan,
          tanggal: widget.tanggal,
        ),
      ),
    );
    if (!mounted) return;
    await _muatRetur();
  }

  Future<void> _batalSemuaRetur() async {
    final ya = await _konfirmasi(
      judul: 'Batalkan retur?',
      isi:
          'Semua barang retur di toko ini hari ini akan dihapus. '
          'Stok packing dikembalikan seperti membatalkan nota. '
          'Tagihan toko kembali tanpa potongan retur. Lanjutkan?',
      ya: 'Ya, batalkan',
      bahaya: true,
    );
    if (!ya || !mounted) return;
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    try {
      final ok = await _repo.returTokoSimpan(
        tanggal: widget.tanggal,
        idPelanggan: _toko.idPelanggan,
        baris: const [],
      );
      if (!mounted) return;
      if (ok) {
        umpan(context, 'Retur toko dibatalkan.');
        await _muatRetur();
      } else {
        umpan(context, 'Retur belum bisa dibatalkan.');
      }
    } catch (e) {
      if (!mounted) return;
      umpan(context, pesanGagal(e, 'Retur belum bisa dibatalkan.'));
    }
  }

  Future<void> _bukaRetur() async {
    if (widget.lihatSaja && _retur.isEmpty) return;
    if (_retur.isEmpty) {
      await _bukaEditorRetur();
      return;
    }
    final aksi = await tampilkanReturTokoSheet(
      context: context,
      namaToko: _toko.nama,
      baris: _retur,
    );
    if (!mounted || aksi == null) return;
    if (widget.lihatSaja) return;
    if (aksi == AksiReturToko.edit) {
      await _bukaEditorRetur();
    } else {
      await _batalSemuaRetur();
    }
  }

  Widget _chipCek(_NotaOutlet nota) {
    final sudah = nota.sudahDicek || !nota.masihDikirim;
    final warna = sudah ? Colors.green : Colors.amber.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: Tema.sudut,
        border: Border.all(color: warna, width: 1.2),
      ),
      child: Text(
        sudah ? 'Sudah di cek' : 'Belum di cek',
        style: TextStyle(
          color: warna,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _chipWaktu(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: Tema.sudut,
        border: Border.all(color: Tema.seed, width: 1.2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Tema.seed,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

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

  Widget _nominal(_NotaOutlet nota) {
    final n = nota.nota;
    final rasioOrder = _rasioDariItem(
      omset: n.omsetOrder,
      items: nota.item,
      qty: (it) => it.qtyOrder,
      cadangan: n.labaOrder,
    );
    if (!n.sudahPack) {
      return _uangRasio(Uang.rp(n.omsetOrder), rasioOrder);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _uangRasio('Order : ${Uang.rp(n.omsetOrder)}', rasioOrder),
        const SizedBox(height: 2),
        _uangRasio(
          'Kiriman : ${Uang.rp(n.omsetPacked)}',
          _rasioDariItem(
            omset: n.omsetPacked,
            items: nota.item,
            qty: (it) => it.qtyPacked,
            cadangan: n.labaPacked,
          ),
        ),
        const SizedBox(height: 2),
        _uangRasio(
          'Actual : ${Uang.rp(nota.omsetActualKartu)}',
          _rasioActual(nota),
        ),
      ],
    );
  }

  String _rasioDariItem({
    required int omset,
    required List<ItemNota> items,
    required int Function(ItemNota) qty,
    int? cadangan,
  }) {
    if (items.isNotEmpty) {
      var modal = 0;
      for (final it in items) {
        final q = qty(it);
        if (q > 0) modal += q * it.hargaBeli;
      }
      return Uang.rasioOmset(omset: omset, modal: modal);
    }
    return Uang.rasioLaba(omset: omset, laba: cadangan);
  }

  String _rasioActual(_NotaOutlet nota) {
    final omset = nota.omsetActualKartu;
    if (nota.item.isEmpty) {
      return Uang.rasioLaba(omset: omset, laba: nota.nota.labaActual);
    }
    final qty = nota.qtyTebus.isNotEmpty
        ? nota.qtyTebus
        : {
            for (final it in nota.item) it.idBarang: it.qtyActual ?? 0,
          };
    return Uang.rasioOmset(omset: omset, modal: modalDariQty(nota.item, qty));
  }

  Widget _kartuNota(_NotaOutlet nota) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _tampilkanSheet(nota),
        borderRadius: Tema.sudut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: Tema.sudut,
            border: Border.all(color: Tema.seed, width: 1.2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nota.nota.idTransaksi,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Tema.seed,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Order ${Uang.tanggalJam(nota.nota.waktuOrder)}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _chipCek(nota),
                  if (nota.nota.pending) ...[
                    const SizedBox(height: 6),
                    chipStatusNota('Pending'),
                  ],
                  if (nota.batalTampil > 0) ...[
                    const SizedBox(height: 6),
                    chipStatusNota('Batal ${Uang.rp(nota.batalTampil)}'),
                  ],
                  const SizedBox(height: 6),
                  _nominal(nota),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blokPembayaran() {
    final wajib = _wajibHariIni;
    final akanKunci = _akanDikunci;
    final bisaKunci =
        !_kunciProses &&
        akanKunci.isNotEmpty &&
        wajib.every((n) => n.sudahDicek);
    return Column(
      children: [
        const SizedBox(height: 4),
        const Text(
          'Total yang harus dibayar',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        if (_nilaiRetur > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Nota ${Uang.rp(_nilaiNota)} − retur ${Uang.rp(_nilaiRetur)}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          Uang.rp(_totalBayar),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Tema.seed,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: bisaKunci ? _kunciHasilToko : null,
            child: _kunciProses
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    akanKunci.isNotEmpty
                        ? 'Kunci hasil toko'
                        : (_nota.any((n) => n.masihDikirim && n.nota.pending)
                            ? 'Pending boleh dikunci nanti'
                            : 'Semua nota sudah dikunci'),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        umpan(
          context,
          _kembaliSaja
              ? 'Masih di toko ini. Tekan "Kembali ke rute" di bawah.'
              : 'Kunjungan masih berlangsung. Tekan "Selesai kunjungan" di bawah, lalu scan barcode toko.',
        );
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Tema.biru,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          centerTitle: true,
        ),
        body: _muat
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                child: Column(
                  children: [
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _toko.nama.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _toko.idPelanggan.isEmpty
                                    ? 'Kode toko belum ada'
                                    : 'Kode Toko: ${_toko.idPelanggan}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              if (_toko.ruteSales.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Rute: ${_toko.ruteSales}',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const Divider(height: 16),
                              Row(
                                children: [
                                  _chipWaktu(
                                    'In: ${_toko.waktuMasuk == null ? '-' : Uang.jam(_toko.waktuMasuk!)}',
                                  ),
                                  const SizedBox(width: 8),
                                  _chipWaktu(
                                    'Out: ${_toko.waktuKeluar == null ? '-' : Uang.jam(_toko.waktuKeluar!)}',
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              Expanded(
                                child: _nota.isEmpty
                                    ? const Center(
                                        child: Text('Tidak ada nota.'),
                                      )
                                    : ListView.separated(
                                        padding: EdgeInsets.zero,
                                        itemCount: _nota.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (context, i) =>
                                            _kartuNota(_nota[i]),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.lihatSaja && _retur.isEmpty
                            ? null
                            : _bukaRetur,
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: Text(
                          _retur.isEmpty
                              ? 'Retur barang ke gudang'
                              : 'Retur ${_retur.length} barang',
                        ),
                      ),
                    ),
                    _blokPembayaran(),
                    const SizedBox(height: 8),
                    _TombolKeluarKunjungan(
                      waktuMasuk: _toko.waktuMasuk,
                      lihatSaja: _kembaliSaja,
                      onPressed: _selesaiKunjungan,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TombolKeluarKunjungan extends StatefulWidget {
  const _TombolKeluarKunjungan({
    required this.waktuMasuk,
    required this.onPressed,
    this.lihatSaja = false,
  });

  final DateTime? waktuMasuk;
  final VoidCallback onPressed;
  final bool lihatSaja;

  @override
  State<_TombolKeluarKunjungan> createState() => _TombolKeluarKunjunganState();
}

class _TombolKeluarKunjunganState extends State<_TombolKeluarKunjungan> {
  Timer? _timer;
  int _sisa = 0;
  bool _kunci = false;

  @override
  void initState() {
    super.initState();
    if (widget.lihatSaja) return;
    final masuk = widget.waktuMasuk;
    if (masuk == null) return;
    final elapsed = DateTime.now().difference(masuk).inSeconds;
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

  @override
  Widget build(BuildContext context) {
    final gaya = FilledButton.styleFrom(
      backgroundColor: _kunci
          ? Colors.grey.shade400
          : widget.lihatSaja
              ? Tema.seed
              : Colors.red.shade700,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey.shade400,
      disabledForegroundColor: Colors.white,
    );
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        style: gaya,
        onPressed: _kunci ? null : widget.onPressed,
        icon: Icon(
          _kunci
              ? Icons.lock_clock_outlined
              : widget.lihatSaja
                  ? Icons.storefront_outlined
                  : Icons.logout_outlined,
        ),
        label: Text(
          _kunci
              ? 'Tunggu sisa kunjungan ($_sisa s)'
              : widget.lihatSaja
                  ? 'Kembali ke rute'
                  : 'Selesai kunjungan',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}
