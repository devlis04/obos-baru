import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pesan.dart';
import '../rumus_sederhana.dart';
import '../uang.dart';
import 'masukan_csv.dart';
import 'masukan_repo.dart';

const _lebarQty = 52.0;
const _lebarHarga = 100.0;
const _lebarTotal = 112.0;
const _lebarHapus = 48.0;
const _celahAngka = 8.0;
const _gayaJudul = TextStyle(
  fontWeight: FontWeight.w700,
  fontSize: 13,
  color: Colors.black,
);
const _gayaIsi = TextStyle(
  fontSize: 14,
  color: Colors.black,
);
const _gayaJumlah = TextStyle(fontWeight: FontWeight.bold);

Future<void> bukaMasukan({
  required BuildContext context,
  required Future<void> Function() onMuat,
  int? idSupplier,
  bool baru = false,
}) async {
  final repo = MasukanRepo(Supabase.instance.client);
  List<Supplier> daftar;
  try {
    daftar = await repo.supplier();
  } catch (e) {
    if (!context.mounted) return;
    tampilPesan(
      context,
      Jaringan.mati(e)
          ? 'Tidak ada internet. Barang masuk belum bisa dibuka.'
          : 'Daftar supplier belum bisa dibaca.',
    );
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => MasukanDialog(
      awalSupplier: daftar,
      onMuat: onMuat,
      idSupplier: idSupplier,
      baru: baru,
    ),
  );
}

class MasukanDialog extends StatefulWidget {
  const MasukanDialog({
    super.key,
    required this.awalSupplier,
    required this.onMuat,
    this.idSupplier,
    this.baru = false,
  });

  final List<Supplier> awalSupplier;
  final Future<void> Function() onMuat;
  final int? idSupplier;
  final bool baru;

  @override
  State<MasukanDialog> createState() => _MasukanDialogState();
}

class _MasukanDialogState extends State<MasukanDialog> {
  final _repo = MasukanRepo(Supabase.instance.client);
  late List<Supplier> _supplier = widget.awalSupplier;
  int? _idSupplier;
  final List<_Draft> _draft = [];
  final Set<String> _skuAwal = {};
  final _ongkir = TextEditingController();
  final _namaSupplier = TextEditingController();
  final _qty = TextEditingController();
  final _harga = TextEditingController();
  final _namaBaru = TextEditingController();
  final _satuan = TextEditingController();
  final _rincian = TextEditingController();
  final _kategori = TextEditingController();
  CariBarang? _pilihCari;
  TextEditingController? _cariAuto;
  int _kunciCari = 0;
  int? _editDraftI;
  bool _skuBaru = false;
  bool _supplierBaru = false;
  bool _muat = false;
  bool _proses = false;

  @override
  void initState() {
    super.initState();
    if (widget.baru) return;
    final pilih = widget.idSupplier;
    if (pilih != null && _supplier.any((s) => s.id == pilih)) {
      _idSupplier = pilih;
    }
    if (_idSupplier != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_muatSupplier());
      });
    }
  }

  @override
  void dispose() {
    _ongkir.dispose();
    _namaSupplier.dispose();
    _qty.dispose();
    _harga.dispose();
    _namaBaru.dispose();
    _satuan.dispose();
    _rincian.dispose();
    _kategori.dispose();
    super.dispose();
  }

  String _gagal(Object e, String cadangan) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message.trim();
    }
    return cadangan;
  }

  Future<void> _muatSupplier() async {
    if (widget.baru) return;
    final id = _idSupplier;
    if (id == null) return;
    setState(() => _muat = true);
    try {
      final baris = await _repo.lihat(id);
      final ongkir = await _repo.ongkirSupplier(id);
      if (!mounted) return;
      setState(() {
        _draft
          ..clear()
          ..addAll(
            baris.map(
              (r) => _Draft.katalog(
                idBarang: r.idBarang,
                nama: r.nama,
                qty: r.qty,
                hargaBeli: r.hargaBeli,
              ),
            ),
          );
        _skuAwal
          ..clear()
          ..addAll(baris.map((r) => r.idBarang));
        _ongkir.text = ongkir > 0 ? '$ongkir' : '';
        _editDraftI = null;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _muat = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Daftar masuk belum bisa dibaca.'
            : _gagal(e, 'Daftar masuk belum bisa dibaca.'),
      );
    }
  }

  void _tambahDraft() {
    final baris = _barisDariForm(wajib: true);
    if (baris == null) return;
    setState(() {
      final i = _editDraftI;
      if (i != null && i >= 0 && i < _draft.length) {
        _draft[i] = baris;
      } else {
        _draft.add(baris);
      }
      _editDraftI = null;
      _bersihFormSku();
    });
  }

  void _bersihFormSku() {
    _namaBaru.clear();
    _satuan.clear();
    _rincian.clear();
    _kategori.clear();
    _qty.clear();
    _harga.clear();
    _pilihCari = null;
    _cariAuto?.clear();
    _kunciCari++;
  }

  void _isiDraft(int i) {
    if (i < 0 || i >= _draft.length) return;
    final d = _draft[i];
    setState(() {
      _editDraftI = i;
      _skuBaru = d.baru;
      _namaBaru.text = d.baru ? d.nama : '';
      _satuan.text = d.satuan;
      _rincian.text = d.rincian;
      _kategori.text = d.kategori;
      _qty.text = teksQty(d.qty);
      _harga.text = d.hargaBeli.round().toString();
      if (d.baru || d.idBarang == null) {
        _pilihCari = null;
        _cariAuto?.clear();
        _kunciCari++;
      } else {
        _pilihCari = CariBarang(
          idBarang: d.idBarang!,
          nama: d.nama,
          hargaBeli: d.hargaBeli.round(),
        );
        _kunciCari++;
      }
    });
    if (!d.baru && d.idBarang != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _cariAuto?.text = d.nama;
      });
    }
  }

  bool get _formSkuAdaIsi {
    return _qty.text.trim().isNotEmpty ||
        _harga.text.trim().isNotEmpty ||
        _namaBaru.text.trim().isNotEmpty ||
        _satuan.text.trim().isNotEmpty ||
        _rincian.text.trim().isNotEmpty ||
        _kategori.text.trim().isNotEmpty ||
        _pilihCari != null;
  }

  _Draft? _barisDariForm({required bool wajib}) {
    if (!wajib && !_formSkuAdaIsi) return null;
    final qty = nilaiDariRumus(_qty.text);
    final harga = nilaiDariRumus(_harga.text);
    if (qty == null || qty <= 0 || harga == null || harga <= 0) {
      tampilPesan(context, 'Qty dan harga beli wajib lebih dari nol.');
      return null;
    }
    if (_skuBaru) {
      if (_namaBaru.text.trim().isEmpty || _satuan.text.trim().isEmpty) {
        tampilPesan(context, 'SKU baru wajib nama dan satuan.');
        return null;
      }
      return _Draft.baru(
        nama: _namaBaru.text.trim(),
        satuan: _satuan.text.trim(),
        rincian: _rincian.text.trim(),
        kategori: _kategori.text.trim(),
        qty: qty,
        hargaBeli: harga,
      );
    }
    final pilih = _pilihCari;
    if (pilih == null) {
      tampilPesan(context, 'Cari dan pilih SKU katalog dulu.');
      return null;
    }
    return _Draft.katalog(
      idBarang: pilih.idBarang,
      nama: pilih.nama,
      qty: qty,
      hargaBeli: harga,
    );
  }

  Future<void> _simpan() async {
    var id = _idSupplier;
    final namaBaru = _namaSupplier.text.trim();
    final extra = _barisDariForm(wajib: false);
    if (_formSkuAdaIsi && extra == null) return;
    if (_draft.isEmpty) {
      tampilPesan(context, 'Tambah SKU ke daftar dulu.');
      return;
    }
    final kirim = [..._draft];
    if (extra != null) {
      final i = _editDraftI;
      if (i != null && i >= 0 && i < kirim.length) {
        kirim[i] = extra;
      } else {
        kirim.add(extra);
      }
    }
    final ongkir = nilaiDariRumus(_ongkir.text);
    if (_ongkir.text.trim().isNotEmpty && (ongkir == null || ongkir < 0)) {
      tampilPesan(context, 'Ongkir tidak valid.');
      return;
    }
    if (_supplierBaru) {
      if (namaBaru.isEmpty) {
        tampilPesan(context, 'Nama supplier baru wajib.');
        return;
      }
    } else if (id == null) {
      tampilPesan(context, 'Pilih supplier.');
      return;
    }
    setState(() => _proses = true);
    try {
      if (_supplierBaru) {
        id = await _repo.tambahSupplier(namaBaru);
        final daftar = await _repo.supplier();
        if (!mounted) return;
        _namaSupplier.clear();
        _supplier = daftar;
        _idSupplier = id;
      }
      if (widget.baru) {
        await _repo.simpan(
          idSupplier: id!,
          baris: kirim.map((d) => d.keMap()).toList(),
          ongkir: ongkir?.round(),
        );
      } else {
        await _tulisChip(id: id!, kirim: kirim, ongkir: ongkir?.round());
      }
      if (!mounted) return;
      _editDraftI = null;
      _bersihFormSku();
      if (widget.baru) {
        _draft.clear();
        _ongkir.clear();
        _idSupplier = null;
        _supplierBaru = false;
        _namaSupplier.clear();
        _skuAwal.clear();
      }
      setState(() => _proses = false);
      if (!widget.baru) await _muatSupplier();
      await widget.onMuat();
      if (!mounted) return;
      tampilPesan(context, 'Barang masuk tersimpan.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Barang masuk belum tersimpan.'
            : _gagal(e, 'Barang masuk belum tersimpan.'),
      );
    }
  }

  Future<void> _tulisChip({
    required int id,
    required List<_Draft> kirim,
    int? ongkir,
  }) async {
    final sekarang = <String>{};
    final tambahan = <_Draft>[];
    for (final d in kirim) {
      final kode = d.idBarang;
      if (d.baru || kode == null || !_skuAwal.contains(kode)) {
        tambahan.add(d);
        continue;
      }
      sekarang.add(kode);
      await _repo.ubah(
        idSupplier: id,
        idBarang: kode,
        qty: d.qty,
        hargaBeli: d.hargaBeli,
      );
    }
    for (final kode in _skuAwal) {
      if (!sekarang.contains(kode)) {
        await _repo.hapus(idSupplier: id, idBarang: kode);
      }
    }
    await _repo.simpan(
      idSupplier: id,
      baris: tambahan.map((d) => d.keMap()).toList(),
      ongkir: ongkir,
    );
  }

  Widget _tombolPlus() {
    return IconButton(
      tooltip: 'Tambah ke daftar',
      splashRadius: 20,
      enableFeedback: false,
      onPressed: _proses ? null : _tambahDraft,
      icon: const Icon(Icons.add_circle_outline),
    );
  }

  String _namaBerkasCsv() {
    var n = '';
    if (_supplierBaru) {
      n = _namaSupplier.text.trim();
    } else {
      for (final s in _supplier) {
        if (s.id == _idSupplier) {
          n = s.nama;
          break;
        }
      }
    }
    final aman = n
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return aman.isEmpty ? 'barang-masuk.csv' : 'barang-masuk-$aman.csv';
  }

  Future<void> _unduhCsv() async {
    if (_proses) return;
    setState(() => _proses = true);
    try {
      final kat = await _repo.katalogCsv();
      if (!mounted) return;
      final qtyIsi = <String, num>{};
      for (final d in _draft) {
        final kode = d.idBarang;
        if (kode != null && kode.isNotEmpty) qtyIsi[kode.toLowerCase()] = d.qty;
      }
      final baris = <BarisCsvMasuk>[];
      for (final k in kat) {
        final pecah = pecahNamaBarang(k.namaBarang);
        baris.add(
          BarisCsvMasuk(
            idBarang: k.idBarang,
            nama: pecah.nama,
            satuan: pecah.satuan,
            rincian: pecah.rincian,
            kategori: k.kategori,
            hargaBeli: k.hargaBeli,
            qty: qtyIsi[k.idBarang.toLowerCase()],
          ),
        );
      }
      unduhBerkasCsv(_namaBerkasCsv(), csvDariBaris(baris));
      setState(() => _proses = false);
      tampilPesan(
        context,
        kat.isEmpty
            ? 'Templat CSV diunduh.'
            : 'CSV ${kat.length} SKU katalog diunduh. Isi kolom qty.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. CSV belum bisa diunduh.'
            : 'Katalog CSV belum bisa dibaca.',
      );
    }
  }

  Future<void> _unggahCsv() async {
    if (_proses) return;
    final teks = await pilihBerkasCsv();
    if (!mounted || teks == null) return;
    List<BarisCsvMasuk> csv;
    try {
      csv = barisDariCsv(teks);
    } on FormatException catch (e) {
      tampilPesan(
        context,
        e.message.trim().isEmpty ? 'CSV tidak bisa dibaca.' : e.message,
      );
      return;
    } catch (_) {
      tampilPesan(context, 'CSV tidak bisa dibaca.');
      return;
    }
    if (csv.isEmpty) {
      tampilPesan(context, 'Isi kolom qty di CSV dulu.');
      return;
    }
    setState(() => _proses = true);
    try {
      final kat = await _repo.katalogCsv();
      if (!mounted) return;
      final peta = {
        for (final k in kat) k.idBarang.toLowerCase(): k,
      };
      final hasil = <_Draft>[];
      final lewat = <String>[];
      for (final b in csv) {
        final kode = b.idBarang?.trim() ?? '';
        if (kode.isEmpty || b.qty == null || b.qty! <= 0) continue;
        final k = peta[kode.toLowerCase()];
        if (k == null) {
          lewat.add(kode);
          continue;
        }
        hasil.add(
          _Draft.katalog(
            idBarang: k.idBarang,
            nama: k.namaBarang,
            qty: b.qty!,
            hargaBeli: k.hargaBeli,
          ),
        );
      }
      setState(() {
        _proses = false;
        if (hasil.isNotEmpty) {
          _draft
            ..clear()
            ..addAll(hasil);
          _editDraftI = null;
          _bersihFormSku();
        }
      });
      if (hasil.isEmpty) {
        tampilPesan(context, 'Tidak ada id barang di CSV yang ada di katalog.');
      } else if (lewat.isNotEmpty) {
        tampilPesan(
          context,
          '${hasil.length} SKU dari CSV. Dilewati: ${lewat.join(', ')}.',
        );
      } else {
        tampilPesan(context, '${hasil.length} SKU dari CSV.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. CSV belum bisa dicek ke katalog.'
            : 'CSV belum bisa dicek ke katalog.',
      );
    }
  }

  InputDecoration _dekor(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Barang masuk',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              if (_muat || _proses) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'Supplier baru',
                  style: _gayaJudul,
                ),
                value: _supplierBaru,
                onChanged: _proses
                    ? null
                    : (v) => setState(() {
                          _supplierBaru = v;
                          if (v) {
                            _idSupplier = null;
                            _draft.clear();
                            _skuAwal.clear();
                          } else {
                            _namaSupplier.clear();
                          }
                        }),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: !_supplierBaru
                        ? DropdownButtonFormField<int>(
                            key: ValueKey(_idSupplier),
                            initialValue: _idSupplier,
                            isDense: true,
                            decoration: _dekor('Supplier'),
                            items: _supplier
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(s.nama),
                                  ),
                                )
                                .toList(),
                            onChanged: _proses
                                ? null
                                : (v) {
                                    setState(() {
                                      _idSupplier = v;
                                      _draft.clear();
                                      _skuAwal.clear();
                                    });
                                    if (!widget.baru) {
                                      unawaited(_muatSupplier());
                                    }
                                  },
                          )
                        : TextField(
                            controller: _namaSupplier,
                            decoration: _dekor('Nama supplier'),
                            textCapitalization: TextCapitalization.words,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ongkir,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: _dekor('Ongkir (Rp)'),
                    ),
                  ),
                ],
              ),
              if (_draft.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Belum disimpan',
                  style: _gayaJudul,
                ),
                const SizedBox(height: 8),
                DaftarGulirDialog(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      overscroll: false,
                      scrollbars: true,
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _draft.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        return _BarisDraft(
                          draft: _draft[i],
                          aktif: _editDraftI == i,
                          onTap: _proses ? null : () => _isiDraft(i),
                          onHapus: _proses
                              ? null
                              : () => setState(() {
                                    if (_editDraftI == i) {
                                      _editDraftI = null;
                                      _bersihFormSku();
                                    } else if (_editDraftI != null &&
                                        _editDraftI! > i) {
                                      _editDraftI = _editDraftI! - 1;
                                    }
                                    _draft.removeAt(i);
                                  }),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Jumlah',
                        style: _gayaJumlah,
                      ),
                    ),
                    const SizedBox(width: _lebarQty),
                    const SizedBox(width: _celahAngka),
                    SizedBox(
                      width: _lebarHarga,
                      child: Text(
                        '${_draft.length} SKU',
                        textAlign: TextAlign.right,
                        style: _gayaJumlah,
                      ),
                    ),
                    const SizedBox(width: _celahAngka),
                    SizedBox(
                      width: _lebarTotal,
                      child: Text(
                        Uang.rp(
                          _draft.fold<int>(0, (a, d) => a + d.jumlah),
                        ),
                        textAlign: TextAlign.right,
                        style: _gayaJumlah,
                      ),
                    ),
                    const SizedBox(width: _lebarHapus),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'SKU baru',
                  style: _gayaJudul,
                ),
                value: _skuBaru,
                onChanged: _proses
                    ? null
                    : (v) => setState(() {
                          _skuBaru = v;
                          _pilihCari = null;
                          _cariAuto?.clear();
                          _kunciCari++;
                          if (v) {
                            _qty.clear();
                            _harga.clear();
                          }
                        }),
              ),
              if (!_skuBaru)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 9,
                      child: Autocomplete<CariBarang>(
                        key: ValueKey(_kunciCari),
                        displayStringForOption: (o) => o.nama,
                        optionsBuilder: (teks) async {
                          final q = teks.text.trim();
                          if (q.isEmpty) {
                            return const Iterable<CariBarang>.empty();
                          }
                          try {
                            return await _repo.cari(q);
                          } catch (_) {
                            return const Iterable<CariBarang>.empty();
                          }
                        },
                        onSelected: (v) {
                          setState(() => _pilihCari = v);
                          if (v.hargaBeli > 0 && _harga.text.trim().isEmpty) {
                            _harga.text = '${v.hargaBeli}';
                          }
                        },
                        fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                          _cariAuto = ctrl;
                          return TextField(
                            controller: ctrl,
                            focusNode: focus,
                            decoration: _dekor(
                              _pilihCari == null
                                  ? 'Cari SKU'
                                  : _pilihCari!.nama,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _qty,
                        inputFormatters: const [FormatRumusQty()],
                        decoration: _dekor('Qty'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _harga,
                        inputFormatters: const [FormatRumusQty()],
                        decoration: _dekor('Harga beli'),
                      ),
                    ),
                    _tombolPlus(),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _namaBaru,
                        decoration: _dekor('Nama'),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _satuan,
                        decoration: _dekor('Satuan'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _rincian,
                        decoration: _dekor('Rincian'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _kategori,
                        decoration: _dekor('Kategori'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _qty,
                        inputFormatters: const [FormatRumusQty()],
                        decoration: _dekor('Qty'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _harga,
                        inputFormatters: const [FormatRumusQty()],
                        decoration: _dekor('Harga beli'),
                      ),
                    ),
                    _tombolPlus(),
                  ],
                ),
              ],
            ],
          ),
        ),
      actions: [
        TextButton(
          onPressed: _proses ? null : _unduhCsv,
          child: const Text('Unduh CSV'),
        ),
        TextButton(
          onPressed: _proses ? null : _unggahCsv,
          child: const Text('Unggah CSV'),
        ),
        TextButton(
          onPressed: _proses ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        FilledButton(
          onPressed: _proses ? null : _simpan,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _Draft {
  const _Draft({
    required this.baru,
    this.idBarang,
    required this.nama,
    this.satuan = '',
    this.rincian = '',
    this.kategori = '',
    required this.qty,
    required this.hargaBeli,
  });

  factory _Draft.katalog({
    required String idBarang,
    required String nama,
    required num qty,
    required num hargaBeli,
  }) {
    return _Draft(
      baru: false,
      idBarang: idBarang,
      nama: nama,
      qty: qty,
      hargaBeli: hargaBeli,
    );
  }

  factory _Draft.baru({
    required String nama,
    required String satuan,
    required String rincian,
    required String kategori,
    required num qty,
    required num hargaBeli,
  }) {
    return _Draft(
      baru: true,
      nama: nama,
      satuan: satuan,
      rincian: rincian,
      kategori: kategori,
      qty: qty,
      hargaBeli: hargaBeli,
    );
  }

  final bool baru;
  final String? idBarang;
  final String nama;
  final String satuan;
  final String rincian;
  final String kategori;
  final num qty;
  final num hargaBeli;

  int get jumlah => (qty * hargaBeli).round();

  String get namaTampil {
    if (baru) {
      final r = rincian.isEmpty ? '' : '/$rincian';
      return '$nama /$satuan$r';
    }
    return nama;
  }

  Map<String, dynamic> keMap() {
    return {
      'baru': baru,
      if (idBarang != null) 'id_barang': idBarang,
      'nama': nama,
      'satuan': satuan,
      'rincian': rincian,
      'kategori': kategori,
      'qty': qty.toString(),
      'harga_beli': hargaBeli.toString(),
    };
  }
}

class _BarisDraft extends StatelessWidget {
  const _BarisDraft({
    required this.draft,
    required this.aktif,
    this.onTap,
    this.onHapus,
  });

  final _Draft draft;
  final bool aktif;
  final VoidCallback? onTap;
  final VoidCallback? onHapus;

  @override
  Widget build(BuildContext context) {
    const gaya = _gayaIsi;
    final isi = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              draft.namaTampil,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: gaya,
            ),
          ),
          const SizedBox(width: _celahAngka),
          SizedBox(
            width: _lebarQty,
            child: Text(
              teksQty(draft.qty),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: gaya,
            ),
          ),
          const SizedBox(width: _celahAngka),
          SizedBox(
            width: _lebarHarga,
            child: Text(
              Uang.rp(draft.hargaBeli.round()),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: gaya,
            ),
          ),
          const SizedBox(width: _celahAngka),
          SizedBox(
            width: _lebarTotal,
            child: Text(
              Uang.rp(draft.jumlah),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: gaya,
            ),
          ),
          SizedBox(
            width: _lebarHapus,
            child: GestureDetector(
              onTap: onHapus,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                height: 32,
                child: Icon(Icons.close, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: aktif
          ? ColoredBox(color: const Color(0x0F1B75CB), child: isi)
          : isi,
    );
  }
}

