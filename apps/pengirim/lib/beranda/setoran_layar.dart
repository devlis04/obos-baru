import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lantai.dart';
import '../toko/retur_toko.dart';
import '../toko/toko_repo.dart';
import '../uang.dart';
import '../umpan.dart';
import 'ringkas_hari.dart';
import 'setoran_pengirim.dart';

class SetoranLayar extends StatefulWidget {
  const SetoranLayar({
    super.key,
    required this.tanggal,
    required this.ringkas,
    required this.rutePengirim,
  });

  final DateTime tanggal;
  final RingkasHari ringkas;
  final String rutePengirim;

  @override
  State<SetoranLayar> createState() => _SetoranLayarState();
}

class _SetoranLayarState extends State<SetoranLayar> {
  static const _bopMaks = 170000;
  final _repo = TokoRepo(Supabase.instance.client);
  final _transferCtrl = TextEditingController();
  final _tunaiCtrl = TextEditingController();
  final _bopCtrl = TextEditingController();
  final _kasbonSupirCtrl = TextEditingController();
  final _kasbonKenekCtrl = TextEditingController();
  bool _muat = true;
  bool _proses = false;
  bool _sudahSetor = false;
  bool _bisaUbah = false;
  bool _isiOtomatis = false;
  int _transferTersimpan = 0;
  int _tunaiTersimpan = 0;
  int _bopTersimpan = 0;
  int _kasbonSupirTersimpan = 0;
  int _kasbonKenekTersimpan = 0;
  String _dicatatOleh = '';
  String _dicatatRute = '';
  List<BarisReturRute> _returRute = [];

  RingkasHari get _ringkas => widget.ringkas;

  String get _teksHari => Uang.tanggal(widget.tanggal);

  String get _beritaTransfer {
    final rute = Uang.ruteGrup(widget.rutePengirim);
    final kode = rute.isEmpty ? 'SBGP' : rute;
    final d = widget.tanggal.day.toString().padLeft(2, '0');
    final b = widget.tanggal.month.toString().padLeft(2, '0');
    return '$kode/$d-$b-${widget.tanggal.year}';
  }

  int get _transfer => _angkaTeks(_transferCtrl.text);
  int get _tunai => _angkaTeks(_tunaiCtrl.text);
  int get _bop => _angkaTeks(_bopCtrl.text);
  int get _retur => _ringkas.omsetRetur;
  int get _kasbonSupir => _angkaTeks(_kasbonSupirCtrl.text);
  int get _kasbonKenek => _angkaTeks(_kasbonKenekCtrl.text);
  bool get _bopValid => _bop >= 0 && _bop <= _bopMaks;
  int get _uangSetor => _transfer + _tunai + _bop;
  int get _actualTampil => _ringkas.actualTampil;
  int get _selisih => _actualTampil - _uangSetor;
  bool get _kunciDulu => _ringkas.wajibKunci > 0;
  bool get _fieldAktif => _bisaUbah && !_kunciDulu && !_proses;

  bool _uangTerisi(TextEditingController ctrl) {
    final t = ctrl.text.trim();
    return t.isNotEmpty && t != '-';
  }

  bool get _semuaIsiSetor =>
      _uangTerisi(_transferCtrl) &&
      _uangTerisi(_tunaiCtrl) &&
      _uangTerisi(_bopCtrl);

  bool get _tampilSelisih => _fieldAktif && _semuaIsiSetor && _selisih != 0;
  int get _kasbonJumlah => _kasbonSupir + _kasbonKenek;

  bool get _kasbonCocok {
    if (!_semuaIsiSetor || _selisih == 0) return true;
    return _kasbonJumlah == _selisih.abs();
  }

  bool get _jumlahCocok =>
      _semuaIsiSetor && _transfer >= 0 && _tunai >= 0 && _kasbonCocok;

  bool get _bisaSetor =>
      _fieldAktif && !_proses && _jumlahCocok && _bopValid;

  @override
  void initState() {
    super.initState();
    _isiOtomatis = true;
    _transferCtrl.text = '-';
    _tunaiCtrl.text = '-';
    _bopCtrl.text = '-';
    _kasbonSupirCtrl.text = '-';
    _kasbonKenekCtrl.text = '-';
    _isiOtomatis = false;
    _muatStatus();
  }

  @override
  void dispose() {
    _transferCtrl.dispose();
    _tunaiCtrl.dispose();
    _bopCtrl.dispose();
    _kasbonSupirCtrl.dispose();
    _kasbonKenekCtrl.dispose();
    super.dispose();
  }

  int _angkaTeks(String s) {
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  void _isiKolom(TextEditingController ctrl, int n) {
    final teks = Uang.angka(n);
    if (ctrl.text == teks) return;
    _isiOtomatis = true;
    ctrl.text = teks;
    ctrl.selection = TextSelection.collapsed(offset: teks.length);
    _isiOtomatis = false;
  }

  Future<void> _muatStatus() async {
    try {
      final data = await _repo.setoranLihat();
      var daftarRetur = <BarisReturRute>[];
      var gagalRetur = '';
      try {
        daftarRetur = await _repo.returRuteLihat(widget.tanggal);
      } catch (e) {
        gagalRetur = pesanGagal(e, 'Daftar retur belum bisa dimuat.');
      }
      if (!mounted) return;
      if (data.sudahAda) {
        _isiKolom(_transferCtrl, data.transfer);
        _isiKolom(_tunaiCtrl, data.tunai);
        _isiKolom(_bopCtrl, data.bop);
        _isiKolom(_kasbonSupirCtrl, data.kasbonSupir);
        _isiKolom(_kasbonKenekCtrl, data.kasbonKenek);
      }
      setState(() {
        _sudahSetor = data.sudahAda;
        _bisaUbah = data.bisaUbah;
        _transferTersimpan = data.transfer;
        _tunaiTersimpan = data.tunai;
        _bopTersimpan = data.bop;
        _kasbonSupirTersimpan = data.kasbonSupir;
        _kasbonKenekTersimpan = data.kasbonKenek;
        _dicatatOleh = data.dicatatOleh;
        _dicatatRute = data.dicatatRute;
        _returRute = daftarRetur;
        _muat = false;
      });
      if (gagalRetur.isNotEmpty) {
        umpan(context, gagalRetur);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      umpan(context, pesanGagal(e, 'Status setoran belum bisa dimuat.'));
    }
  }

  Future<void> _tampilkanSheetRetur() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final grup = <String, List<BarisReturRute>>{};
        for (final b in _returRute) {
          final kunci = b.namaToko.isEmpty ? b.idPelanggan : b.namaToko;
          grup.putIfAbsent(kunci, () => []).add(b);
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Retur toko',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nilai retur mengurangi actual setoran.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (_returRute.isEmpty)
                  Text(
                    'Belum ada retur.',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in grup.entries) ...[
                          Text(
                            e.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final b in e.value)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${b.nama.isEmpty ? b.kode : b.nama}'
                                      '${b.kode.isEmpty ? '' : ' · ${b.kode}'}'
                                      ' · ${b.qty} pcs',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    Uang.rp(b.nilai),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Subtotal ${Uang.rp(e.value.fold<int>(0, (a, b) => a + b.nilai))}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.red,
                              ),
                            ),
                          ),
                          const Divider(height: 20),
                        ],
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Total ${Uang.rp(_retur)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
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
      },
    );
  }

  Future<void> _tampilkanSheetKasbon() async {
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
          child: StatefulBuilder(
            builder: (context, setSheet) {
              final perlu = _selisih.abs();
              final isi = _kasbonSupir + _kasbonKenek;
              final sisa = perlu - isi;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kasbon selisih',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selisih > 0
                          ? 'Selisih kurang : Rp ${Uang.angka(perlu)}'
                          : 'Selisih lebih : Rp ${Uang.angka(perlu)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Text(
                      'Ditanggung supir dan kenek.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _fieldUang(
                      label: 'Supir',
                      controller: _kasbonSupirCtrl,
                      onChanged: (_) => setSheet(() {}),
                      enabled: true,
                    ),
                    const SizedBox(height: 12),
                    _fieldUang(
                      label: 'Kenek',
                      controller: _kasbonKenekCtrl,
                      onChanged: (_) => setSheet(() {}),
                      enabled: true,
                    ),
                    if (sisa != 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        sisa > 0
                            ? 'Sisa kasbon : Rp ${Uang.angka(sisa)}'
                            : 'Kasbon lebih : Rp ${Uang.angka(-sisa)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {});
                        },
                        child: const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<bool> _konfirmasi(String isi, String ya) async {
    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Setoran', style: TextStyle(fontWeight: FontWeight.bold)),
        content: IsiDialog(child: Text(isi)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ya),
          ),
        ],
      ),
    );
    return hasil == true;
  }

  Future<void> _setor() async {
    if (!_bisaSetor) {
      if (_kunciDulu) {
        umpan(
          context,
          'Masih ada ${_ringkas.wajibKunci} nota yang belum dikunci. '
          'Selesaikan dulu, lalu setor.',
        );
      } else if (!_bisaUbah) {
        umpan(context, 'Buku setoran sudah ditutup. Setoran tidak bisa diubah.');
      } else if (!_bopValid) {
        umpan(context, 'BOP maksimal Rp ${Uang.angka(_bopMaks)} per hari.');
      } else if (!_kasbonCocok) {
        umpan(
          context,
          'Kasbon supir + kenek harus sama dengan selisih '
          'Rp ${Uang.angka(_selisih.abs())}.',
        );
      }
      return;
    }
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    final kasbonTeks = _kasbonJumlah > 0
        ? '\nKasbon supir Rp ${Uang.angka(_kasbonSupir)}\n'
            'Kasbon kenek Rp ${Uang.angka(_kasbonKenek)}'
        : '';
    final ya = await _konfirmasi(
      'Setor actual $_teksHari Rp ${Uang.angka(_actualTampil)}?\n'
      'Transfer Rp ${Uang.angka(_transfer)}\n'
      'Tunai Rp ${Uang.angka(_tunai)}\n'
      'BOP Rp ${Uang.angka(_bop)}\n'
      'Retur Rp ${Uang.angka(_retur)}'
      '$kasbonTeks'
      '${_ringkas.omsetPending > 0 ? '\n\nMasih ada nota pending. Pending tidak masuk setoran ini.' : ''}',
      _sudahSetor ? 'Simpan setoran' : 'Setor',
    );
    if (!ya || !mounted) return;
    setState(() => _proses = true);
    try {
      final ok = await _repo.setoranSimpan(
        SetoranPengirim(
          transfer: _transfer,
          tunai: _tunai,
          bop: _bop,
          kasbonSupir: _selisih == 0 ? 0 : _kasbonSupir,
          kasbonKenek: _selisih == 0 ? 0 : _kasbonKenek,
          sudahAda: _sudahSetor,
          bisaUbah: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        umpan(
          context,
          _sudahSetor
              ? 'Setoran diperbarui. Bisa diubah lagi selama buku terbuka.'
              : 'Setoran $_teksHari dicatat. Bisa diubah lagi selama buku terbuka.',
        );
        setState(() => _proses = false);
        await _muatStatus();
        return;
      }
      setState(() => _proses = false);
      umpan(context, 'Setoran belum tersimpan.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      umpan(context, pesanGagal(e, 'Setoran belum tersimpan.'));
    }
  }

  Widget _ikonAksi({
    required String tooltip,
    required IconData ikon,
    required Color warna,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      iconSize: 20,
      onPressed: onPressed,
      icon: Icon(ikon, color: warna),
    );
  }

  Widget _barisUang({
    required String label,
    required int nilai,
    int? laba,
    Color? warna,
    Widget? aksi,
  }) {
    final gaya = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      height: 1.2,
      color: warna ?? Tema.seed,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            SizedBox(
              width: 102,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gaya,
              ),
            ),
            Expanded(
              child: Text(Uang.rp(nilai), textAlign: TextAlign.right, style: gaya),
            ),
            SizedBox(
              width: 36,
              child: aksi ??
                  (laba == null
                      ? const SizedBox.shrink()
                      : Text(
                          Uang.rasioLaba(omset: nilai, laba: laba),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldUang({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required bool enabled,
    Widget? aksi,
  }) {
    const gaya = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Tema.seed,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 102,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gaya,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: const [_FormatRibuan()],
              onChanged: onChanged,
              onTap: () {
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              },
              style: gaya,
              decoration: const InputDecoration(
                isDense: true,
                prefixText: 'Rp ',
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ),
          SizedBox(width: 36, child: aksi ?? const SizedBox.shrink()),
        ],
      ),
    );
  }

  String get _teksTombol {
    if (!_bisaUbah && _sudahSetor) return 'Sudah disetor';
    if (!_bisaSetor) {
      return _sudahSetor ? 'Simpan setoran -' : 'Setor -';
    }
    if (_sudahSetor) {
      return 'Simpan setoran Rp ${Uang.angka(_actualTampil)}';
    }
    return 'Setor Rp ${Uang.angka(_actualTampil)}';
  }

  @override
  Widget build(BuildContext context) {
    final tampilIsian = _fieldAktif || (_bisaUbah && _kunciDulu);
    final transferTampil = _sudahSetor ? _transferTersimpan : _transfer;
    final tunaiTampil = _sudahSetor ? _tunaiTersimpan : _tunai;
    final bopTampil = _sudahSetor ? _bopTersimpan : _bop;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tema.biru,
        foregroundColor: Colors.white,
        title: const Text('Setoran'),
        centerTitle: true,
      ),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Pengiriman $_teksHari',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        '${_ringkas.jumlahToko} toko · ${_ringkas.jumlahNota} nota',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (_sudahSetor &&
                                          (_dicatatOleh.isNotEmpty ||
                                              _dicatatRute.isNotEmpty))
                                        Text(
                                          _dicatatOleh.isEmpty
                                              ? 'Dicatat $_dicatatRute'
                                              : _dicatatRute.isEmpty
                                                  ? 'Dicatat oleh $_dicatatOleh'
                                                  : 'Dicatat oleh $_dicatatOleh · $_dicatatRute',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const Divider(height: 10),
                                      _barisUang(
                                        label: 'Order',
                                        nilai: _ringkas.omsetOrder,
                                        laba: _ringkas.labaOrder,
                                      ),
                                      _barisUang(
                                        label: 'Kiriman',
                                        nilai: _ringkas.omsetPacked,
                                        laba: _ringkas.labaPacked,
                                      ),
                                      _barisUang(
                                        label: 'Pending',
                                        nilai: _ringkas.omsetPending,
                                        warna: Colors.orange.shade800,
                                      ),
                                      _barisUang(
                                        label: 'Batal',
                                        nilai: _ringkas.omsetBatal,
                                        warna: Colors.red,
                                      ),
                                      _barisUang(
                                        label: 'Retur',
                                        nilai: _retur,
                                        warna: Colors.red,
                                        aksi: _ikonAksi(
                                          tooltip: 'Daftar retur toko',
                                          ikon: Icons.storefront_outlined,
                                          warna: Colors.red,
                                          onPressed: _tampilkanSheetRetur,
                                        ),
                                      ),
                                      _barisUang(
                                        label: 'Actual',
                                        nilai: _actualTampil,
                                        laba: _ringkas.labaActual,
                                      ),
                                      const Text(
                                        'Rincian setor',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Actual = transfer + tunai + BOP',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (!tampilIsian) ...[
                                        const SizedBox(height: 4),
                                        _barisUang(
                                          label: 'Transfer',
                                          nilai: transferTampil,
                                        ),
                                        _barisUang(
                                          label: 'Tunai',
                                          nilai: tunaiTampil,
                                        ),
                                        _barisUang(label: 'BOP', nilai: bopTampil),
                                        if (_kasbonSupirTersimpan > 0 ||
                                            _kasbonKenekTersimpan > 0) ...[
                                          _barisUang(
                                            label: 'Kasbon supir',
                                            nilai: _kasbonSupirTersimpan,
                                            warna: Colors.red,
                                          ),
                                          _barisUang(
                                            label: 'Kasbon kenek',
                                            nilai: _kasbonKenekTersimpan,
                                            warna: Colors.red,
                                          ),
                                        ],
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (tampilIsian) ...[
                          const SizedBox(height: 4),
                          _fieldUang(
                            label: 'Transfer',
                            controller: _transferCtrl,
                            onChanged: (_) {
                              if (_isiOtomatis) return;
                              setState(() {});
                            },
                            enabled: _fieldAktif,
                          ),
                          Text(
                            'Berita: $_beritaTransfer',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _fieldUang(
                            label: 'Tunai',
                            controller: _tunaiCtrl,
                            onChanged: (_) {
                              if (_isiOtomatis) return;
                              setState(() {});
                            },
                            enabled: _fieldAktif,
                          ),
                          _fieldUang(
                            label: 'BOP',
                            controller: _bopCtrl,
                            onChanged: (_) {
                              if (_isiOtomatis) return;
                              if (_bop > _bopMaks) {
                                _isiKolom(_bopCtrl, _bopMaks);
                                umpan(
                                  context,
                                  'BOP maksimal Rp ${Uang.angka(_bopMaks)} per hari.',
                                );
                              }
                              setState(() {});
                            },
                            enabled: _fieldAktif,
                          ),
                          if (_tampilSelisih) ...[
                            _barisUang(
                              label: _selisih > 0 ? 'Kurang' : 'Lebih',
                              nilai: _selisih > 0 ? _selisih : -_selisih,
                              warna: Colors.red,
                              aksi: _ikonAksi(
                                tooltip: 'Kasbon supir & kenek',
                                ikon: Icons.people_outline,
                                warna: Colors.red,
                                onPressed: _tampilkanSheetKasbon,
                              ),
                            ),
                            if (_kasbonJumlah > 0) ...[
                              _barisUang(
                                label: 'Kasbon supir',
                                nilai: _kasbonSupir,
                                warna: Colors.red,
                              ),
                              _barisUang(
                                label: 'Kasbon kenek',
                                nilai: _kasbonKenek,
                                warna: Colors.red,
                              ),
                            ],
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 10,
                  shadowColor: Colors.black26,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _bisaSetor ? _setor : null,
                        child: _proses
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_teksTombol),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FormatRibuan extends TextInputFormatter {
  const _FormatRibuan();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '-',
        selection: TextSelection.collapsed(offset: 1),
      );
    }
    final teks = Uang.angka(int.parse(digits));
    return TextEditingValue(
      text: teks,
      selection: TextSelection.collapsed(offset: teks.length),
    );
  }
}
