import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:obos_core/obos_core.dart';

import '../jaringan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'barang.dart';
import 'barang_repo.dart';

class BarangPanel extends StatefulWidget {
  const BarangPanel({
    super.key,
    this.awal,
    required this.onTersimpan,
    this.tampilKop = true,
  });

  final Barang? awal;
  final ValueChanged<Barang> onTersimpan;
  final bool tampilKop;

  @override
  State<BarangPanel> createState() => _BarangPanelState();
}

class _BarangPanelState extends State<BarangPanel> {
  final _repo = BarangRepo(Supabase.instance.client);
  late final TextEditingController _id;
  late final TextEditingController _nama;
  late final TextEditingController _satuan;
  late final TextEditingController _rincian;
  late final TextEditingController _grup;
  late final TextEditingController _kategori;
  late final TextEditingController _beli;
  late final TextEditingController _jual;
  late final TextEditingController _pengurang;
  late final TextEditingController _stok;
  late final List<TextEditingController> _min;
  late final List<TextEditingController> _harga;
  late bool _aktif;
  bool _proses = false;
  List<({int id, String nama})> _supplier = [];
  List<({int id, String nama, int harga, bool utama})> _pemasok = [];
  int? _idUtama;

  bool get _beliIkutUtama {
    if (_idUtama == null) return false;
    for (final p in _pemasok) {
      if (p.id == _idUtama && p.harga > 0) return true;
    }
    return false;
  }

  int? get _hargaUtamaPilih {
    if (_idUtama == null) return null;
    for (final p in _pemasok) {
      if (p.id == _idUtama) return p.harga;
    }
    return null;
  }

  bool get _akanSkalakan {
    final h = _hargaUtamaPilih;
    if (h == null || h <= 0) return false;
    final lama = widget.awal?.hargaBeli ?? 0;
    return lama > 0 && h != lama;
  }

  String get _namaUtama {
    for (final s in _supplier) {
      if (s.id == _idUtama) return s.nama;
    }
    for (final p in _pemasok) {
      if (p.id == _idUtama) return p.nama;
    }
    return 'Pemasok utama';
  }

  static final _digit = FilteringTextInputFormatter.digitsOnly;
  static final _qty = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  static const _pad = EdgeInsets.symmetric(horizontal: 10, vertical: 8);

  @override
  void initState() {
    super.initState();
    _id = TextEditingController();
    _nama = TextEditingController();
    _satuan = TextEditingController();
    _rincian = TextEditingController();
    _grup = TextEditingController();
    _kategori = TextEditingController();
    _beli = TextEditingController();
    _jual = TextEditingController();
    _pengurang = TextEditingController();
    _stok = TextEditingController();
    _min = List.generate(5, (_) => TextEditingController());
    _harga = List.generate(5, (_) => TextEditingController());
    _isiDari(widget.awal);
    _beli.addListener(_ubahHarga);
    _jual.addListener(_ubahHarga);
    _pengurang.addListener(_ubahHarga);
    for (final c in _min) {
      c.addListener(_ubahHarga);
    }
    unawaited(_muatPemasok());
  }

  @override
  void didUpdateWidget(BarangPanel old) {
    super.didUpdateWidget(old);
    if (old.awal == null || widget.awal == null) {
      if (old.awal?.id != widget.awal?.id) {
        _isiDari(widget.awal);
        unawaited(_muatPemasok());
      }
    } else if (!old.awal!.samaIsi(widget.awal!)) {
      _isiDari(widget.awal);
      unawaited(_muatPemasok());
    }
  }

  void _isiDari(Barang? a) {
    _id.text = a?.id ?? '';
    final pecah = Barang.pecahNama(a?.nama ?? '');
    _nama.text = pecah.nama;
    _satuan.text = pecah.satuan;
    _rincian.text = pecah.rincian;
    _grup.text = a?.idGrup ?? '';
    _kategori.text = a?.kategori ?? '';
    _beli.text = a == null || a.hargaBeli == 0 ? '' : '${a.hargaBeli}';
    _jual.text = a == null || a.hargaJual == 0 ? '' : '${a.hargaJual}';
    _pengurang.text =
        a == null || a.pengurangStrata == 0 ? '' : '${a.pengurangStrata}';
    _stok.text = a == null ? '0' : Uang.qty(a.stok);
    final mins = [
      a?.minStrat1 ?? 0,
      a?.minStrat2 ?? 0,
      a?.minStrat3 ?? 0,
      a?.minStrat4 ?? 0,
      a?.minStrat5 ?? 0,
    ];
    for (var i = 0; i < 5; i++) {
      _min[i].text = mins[i] == 0 ? '' : '${mins[i]}';
    }
    _aktif = a?.aktif ?? true;
    _isiJualStrata();
  }

  @override
  void dispose() {
    _id.dispose();
    _nama.dispose();
    _satuan.dispose();
    _rincian.dispose();
    _grup.dispose();
    _kategori.dispose();
    _beli.removeListener(_ubahHarga);
    _jual.removeListener(_ubahHarga);
    _pengurang.removeListener(_ubahHarga);
    _beli.dispose();
    _jual.dispose();
    _pengurang.dispose();
    _stok.dispose();
    for (final c in _min) {
      c.removeListener(_ubahHarga);
      c.dispose();
    }
    for (final c in _harga) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muatPemasok() async {
    final id = (widget.awal?.id ?? _id.text).trim();
    try {
      final daftar = await _repo.daftarSupplier();
      var harga = <({int id, String nama, int harga, bool utama})>[];
      int? utama;
      if (id.isNotEmpty) {
        harga = await _repo.pemasok(id);
        utama = await _repo.pemasokUtama(id);
      }
      if (!mounted) return;
      setState(() {
        _supplier = daftar;
        _pemasok = harga;
        _idUtama = utama;
        var n = 0;
        if (utama != null) {
          for (final p in harga) {
            if (p.id == utama) {
              n = p.harga;
              break;
            }
          }
        }
        if (n > 0) _beli.text = '$n';
      });
    } catch (_) {}
  }

  void _ubahHarga() {
    _isiJualStrata();
    if (mounted) setState(() {});
  }

  int _jualStrata(int i) {
    if (_min[i].text.trim().isEmpty) return 0;
    if (_jual.text.trim().isEmpty || _pengurang.text.trim().isEmpty) return 0;
    return _angka(_jual) - _angka(_pengurang) * (i + 1);
  }

  void _isiJualStrata() {
    for (var i = 0; i < 5; i++) {
      final n = _jualStrata(i);
      final teks = n <= 0 ? '' : '$n';
      if (_harga[i].text != teks) _harga[i].text = teks;
    }
  }

  String _teksLabaDari(TextEditingController jualCtrl) {
    if (jualCtrl.text.trim().isEmpty) return '—';
    final beli = _angka(_beli);
    if (_beli.text.trim().isEmpty || beli <= 0) return '—';
    final jual = _angka(jualCtrl);
    final persen = ((jual - beli) / beli) * 100;
    return '${persen.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Color _warnaLabaDari(TextEditingController jualCtrl) {
    if (jualCtrl.text.trim().isEmpty) return Colors.grey;
    final beli = _angka(_beli);
    final jual = _angka(jualCtrl);
    if (_beli.text.trim().isEmpty || beli <= 0) return Colors.grey;
    if (jual > beli) return Colors.green.shade700;
    if (jual < beli) return Colors.red;
    return Colors.grey;
  }

  Widget _labaDiKanan(TextEditingController jualCtrl) {
    return SizedBox(
      width: 64,
      child: Text(
        _teksLabaDari(jualCtrl),
        textAlign: TextAlign.left,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: _warnaLabaDari(jualCtrl),
        ),
      ),
    );
  }

  int _angka(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  num _qtyAngka() => Uang.qtyTeks(_stok.text);

  Barang _dariForm({num? stok}) {
    return Barang(
      id: _id.text.trim(),
      idGrup: _grup.text.trim(),
      nama: Barang.gabungNama(
        nama: _nama.text,
        satuan: _satuan.text,
        rincian: _rincian.text,
      ),
      kategori: _kategori.text.trim(),
      stok: stok ?? _qtyAngka(),
      sisaBuku: widget.awal?.sisaBuku,
      hargaBeli: _angka(_beli),
      hargaJual: _angka(_jual),
      minStrat1: _angka(_min[0]),
      jualStrat1: _jualStrata(0),
      minStrat2: _angka(_min[1]),
      jualStrat2: _jualStrata(1),
      minStrat3: _angka(_min[2]),
      jualStrat3: _jualStrata(2),
      minStrat4: _angka(_min[3]),
      jualStrat4: _jualStrata(3),
      minStrat5: _angka(_min[4]),
      jualStrat5: _jualStrata(4),
      pengurangStrata: _angka(_pengurang),
      aktif: _aktif,
    );
  }

  Future<void> _simpanMaster() async {
    if (widget.awal == null) {
      tampilPesan(context, 'SKU baru hanya dari Barang masuk.');
      return;
    }
    if (_id.text.trim().isEmpty || _nama.text.trim().isEmpty) {
      tampilPesan(context, 'Id dan nama wajib diisi.');
      return;
    }
    if (_satuan.text.trim().isEmpty) {
      tampilPesan(context, 'Satuan wajib diisi.');
      return;
    }
    if (_beli.text.trim().isEmpty || _jual.text.trim().isEmpty) {
      tampilPesan(context, 'Harga beli dan harga jual wajib diisi.');
      return;
    }
    if (!_akanSkalakan && _angka(_jual) <= _angka(_beli)) {
      tampilPesan(
        context,
        'Harga jual harus lebih besar dari harga beli.',
      );
      return;
    }
    final pakaiStrata = _min.any((c) => c.text.trim().isNotEmpty);
    if (pakaiStrata && _pengurang.text.trim().isEmpty) {
      tampilPesan(
        context,
        'Nilai pengurang wajib diisi jika strata dipakai.',
      );
      return;
    }
    if (!_akanSkalakan) {
      for (var i = 0; i < 5; i++) {
        if (_min[i].text.trim().isEmpty) continue;
        if (_jualStrata(i) <= _angka(_beli)) {
          tampilPesan(
            context,
            'Harga jual strata harus lebih besar dari harga beli.',
          );
          return;
        }
      }
    }
    setState(() => _proses = true);
    try {
      var simpan = await _repo.simpan(_dariForm());
      if (!mounted) return;
      if (widget.awal == null) {
        final minta = _qtyAngka();
        if (minta != simpan.stok) {
          try {
            final n = await _repo.setStok(simpan.id, minta);
            if (!mounted) return;
            simpan = _dariForm(stok: n);
          } catch (e) {
            if (!mounted) return;
            setState(() => _proses = false);
            tampilPesan(
              context,
              'Barang disimpan. Stok belum: ${pesanGagal(e, 'gagal disimpan.')}',
            );
            widget.onTersimpan(simpan);
            return;
          }
        }
      }
      setState(() => _proses = false);
      try {
        await _repo.setPemasokUtama(simpan.id, _idUtama);
      } catch (e) {
        if (!mounted) return;
        tampilPesan(
          context,
          'Barang disimpan. Pemasok utama belum: ${pesanGagal(e, 'gagal.')}',
        );
        widget.onTersimpan(simpan);
        return;
      }
      if (!mounted) return;
      await _muatPemasok();
      if (!mounted) return;
      try {
        final list = await _repo.katalog(simpan.id);
        final ketemu = list.where((b) => b.id == simpan.id);
        if (ketemu.isNotEmpty) simpan = ketemu.first;
      } catch (_) {}
      if (!mounted) return;
      tampilPesan(context, 'Barang disimpan.');
      widget.onTersimpan(simpan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Barang belum tersimpan.'
            : pesanGagal(e, 'Barang belum tersimpan.'),
      );
    }
  }

  Future<void> _simpanStok() async {
    final id = widget.awal?.id ?? _id.text.trim();
    if (widget.awal == null || id.isEmpty) {
      tampilPesan(context, 'Simpan barang dulu, lalu ubah stok.');
      return;
    }
    setState(() => _proses = true);
    try {
      final n = await _repo.setStok(id, _qtyAngka());
      if (!mounted) return;
      final baru = _dariForm(stok: n);
      setState(() => _proses = false);
      tampilPesan(
        context,
        'Stok master disimpan. Sisa packing gudang tidak diubah dari tombol ini (kecuali buku terbuka: stok awal/fisik ikut selisih).',
      );
      widget.onTersimpan(baru);
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Stok belum tersimpan.'
            : pesanGagal(e, 'Stok belum tersimpan.'),
      );
    }
  }

  InputDecoration _isi(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: _pad,
      );

  double _lebarIsi(String teks, String label, {double min = 92, double max = 220}) {
    final n = teks.trim().isEmpty ? label.length + 2 : teks.trim().length;
    return (32 + n * 7.4).clamp(min, max);
  }

  Widget _fieldTeks(
    TextEditingController c,
    String label, {
    double min = 92,
    double max = 220,
    bool enabled = true,
  }) {
    return SizedBox(
      width: _lebarIsi(c.text, label, min: min, max: max),
      child: TextField(
        controller: c,
        enabled: enabled,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 14),
        decoration: _isi(label),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _angkaField(
    TextEditingController c,
    String label, {
    bool bacaSaja = false,
    double min = 92,
    double max = 140,
  }) {
    return SizedBox(
      width: _lebarIsi(c.text, label, min: min, max: max),
      child: TextField(
        controller: c,
        readOnly: bacaSaja,
        enableInteractiveSelection: !bacaSaja,
        keyboardType: TextInputType.number,
        inputFormatters: [_digit],
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 14),
        decoration: _isi(label),
        onChanged: bacaSaja ? null : (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        visualDensity: VisualDensity.compact,
        textTheme: Theme.of(context).textTheme.copyWith(
          bodyLarge: const TextStyle(fontSize: 14, height: 1.2),
          titleMedium: const TextStyle(fontSize: 14, height: 1.2),
        ),
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
          labelStyle: const TextStyle(fontSize: 14),
          floatingLabelStyle: const TextStyle(fontSize: 14, color: Tema.biru),
          hintStyle: const TextStyle(fontSize: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Tema.biru,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(64, 32),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Tema.biru,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(64, 32),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.tampilKop) ...[
            Text(
              'Ubah barang',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Tema.biru,
              ),
            ),
            const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: _aktif
                  ? FilledButton(
                      onPressed: () => setState(() => _aktif = false),
                      child: const Text('Aktif di katalog lapangan'),
                    )
                  : OutlinedButton(
                      onPressed: () => setState(() => _aktif = true),
                      child: const Text('Aktif di katalog lapangan'),
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _fieldTeks(_id, 'Id', min: 88, max: 140, enabled: false),
                        _fieldTeks(_grup, 'Grup', min: 88, max: 140),
                        _fieldTeks(_nama, 'Nama barang', min: 160, max: 280),
                        _fieldTeks(_satuan, 'Satuan', min: 80, max: 120),
                        _fieldTeks(_rincian, 'Rincian', min: 88, max: 160),
                        _fieldTeks(_kategori, 'Kategori', min: 88, max: 180),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Pemasok',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: _lebarIsi(_namaUtama, 'Pemasok utama', min: 160, max: 260),
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('utama-${_idUtama ?? 0}-${_supplier.length}'),
                        initialValue: _idUtama != null &&
                                (_supplier.any((s) => s.id == _idUtama) ||
                                    _pemasok.any((s) => s.id == _idUtama))
                            ? _idUtama
                            : 0,
                        isDense: true,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                        decoration: _isi('Pemasok utama'),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('(tidak ada)'),
                          ),
                          for (final s in [
                            ..._supplier,
                            for (final p in _pemasok)
                              if (!_supplier.any((x) => x.id == p.id))
                                (id: p.id, nama: p.nama),
                          ])
                            DropdownMenuItem(
                              value: s.id,
                              child: Text(s.nama, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      onChanged: (v) {
                        setState(() {
                          _idUtama = (v == null || v <= 0) ? null : v;
                          final h = _hargaUtamaPilih;
                          if (h != null && h > 0) _beli.text = '$h';
                        });
                      },
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_pemasok.isEmpty)
                      Text(
                        'Harga per pemasok terisi dari Barang masuk.',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      )
                    else ...[
                      for (final p in _pemasok.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: Text(
                                  p.utama ? '${p.nama} · utama' : p.nama,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: p.utama
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Rp ${Uang.angka(p.harga)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_pemasok.length > 5)
                        Text(
                          'dan ${_pemasok.length - 5} pemasok lain',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _angkaField(
                          _beli,
                          'Harga beli',
                          bacaSaja: _beliIkutUtama,
                          min: 108,
                          max: 140,
                        ),
                        _angkaField(_jual, 'Harga jual', min: 108, max: 140),
                        _labaDiKanan(_jual),
                      ],
                    ),
                    if (_beliIkutUtama)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _akanSkalakan
                              ? 'Modal ikut pemasok utama. Setelah simpan, jual dan strata diskalakan (pembulatan Rp 500).'
                              : 'Modal ikut harga pemasok utama.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      'Strata',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    _angkaField(_pengurang, 'Pengurang', min: 100, max: 120),
                    const SizedBox(height: 6),
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _angkaField(_min[i], 'Min ${i + 1}', min: 80, max: 100),
                            _angkaField(
                              _harga[i],
                              'Jual ${i + 1}',
                              bacaSaja: true,
                              min: 100,
                              max: 140,
                            ),
                            _labaDiKanan(_harga[i]),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _proses ? null : _simpanMaster,
                        child: Text(_proses ? 'Menyimpan…' : 'Simpan barang'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: _lebarIsi(_stok.text, 'Stok master', min: 80, max: 140),
                      child: TextField(
                        controller: _stok,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [_qty],
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(fontSize: 14),
                        decoration: _isi('Stok master'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.awal == null
                            ? 'Bukan sisa packing. Sisa gudang tampil setelah SKU tersimpan.'
                            : 'Sisa buku gudang (packing): ${Uang.qty(widget.awal!.sisaGudang)}',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: _proses ? null : _simpanStok,
                        child: const Text('Simpan stok'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

