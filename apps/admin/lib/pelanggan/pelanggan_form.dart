import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pesan.dart';
import 'pelanggan.dart';
import 'pelanggan_repo.dart';

class PelangganPanel extends StatefulWidget {
  const PelangganPanel({
    super.key,
    required this.awal,
    required this.onTersimpan,
  });

  final Pelanggan awal;
  final ValueChanged<Pelanggan> onTersimpan;

  @override
  State<PelangganPanel> createState() => _PelangganPanelState();
}

class _PelangganPanelState extends State<PelangganPanel> {
  final _repo = PelangganRepo(Supabase.instance.client);
  late final TextEditingController _id;
  late final TextEditingController _nama;
  late final TextEditingController _urutan;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late bool _aktif;
  String _rute = '';
  String _visit = '';
  bool _proses = false;
  List<({String rute, String nama})> _sales = [];

  static const _pad = EdgeInsets.symmetric(horizontal: 10, vertical: 8);

  @override
  void initState() {
    super.initState();
    _id = TextEditingController();
    _nama = TextEditingController();
    _urutan = TextEditingController();
    _lat = TextEditingController();
    _lng = TextEditingController();
    _isiDari(widget.awal);
    unawaited(_muatRute());
  }

  @override
  void didUpdateWidget(PelangganPanel old) {
    super.didUpdateWidget(old);
    if (old.awal.id != widget.awal.id) {
      _isiDari(widget.awal);
    }
  }

  void _isiDari(Pelanggan a) {
    _id.text = a.id;
    _nama.text = a.nama;
    _urutan.text = a.urutan == 0 ? '' : '${a.urutan}';
    _lat.text = a.latitude == null ? '' : '${a.latitude}';
    _lng.text = a.longitude == null ? '' : '${a.longitude}';
    _aktif = a.aktif;
    _rute = a.rute.trim();
    _visit = a.visit.trim();
  }

  @override
  void dispose() {
    _id.dispose();
    _nama.dispose();
    _urutan.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _muatRute() async {
    try {
      final list = await _repo.ruteSales();
      if (!mounted) return;
      setState(() => _sales = list);
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Daftar rute salesman belum bisa dimuat.'
            : pesanGagal(e, 'Daftar rute salesman belum bisa dimuat.'),
      );
    }
  }

  double? _desimal(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _simpan() async {
    if (_proses) return;
    final nama = _nama.text.trim();
    if (nama.isEmpty) {
      tampilPesan(context, 'Nama pelanggan wajib diisi.');
      return;
    }
    setState(() => _proses = true);
    try {
      final simpan = Pelanggan(
        id: _id.text.trim(),
        nama: nama,
        rute: _rute,
        visit: _visit,
        urutan: int.tryParse(_urutan.text.trim()) ?? 0,
        latitude: _desimal(_lat.text),
        longitude: _desimal(_lng.text),
        aktif: _aktif,
      );
      final hasil = await _repo.simpan(simpan);
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(context, 'Pelanggan disimpan.');
      widget.onTersimpan(hasil);
    } catch (e) {
      if (!mounted) return;
      setState(() => _proses = false);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Pelanggan belum tersimpan.'
            : pesanGagal(e, 'Pelanggan belum tersimpan.'),
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
    TextCapitalization cap = TextCapitalization.none,
  }) {
    return SizedBox(
      width: _lebarIsi(c.text, label, min: min, max: max),
      child: TextField(
        controller: c,
        enabled: enabled,
        textCapitalization: cap,
        textInputAction: TextInputAction.next,
        style: const TextStyle(fontSize: 14),
        decoration: _isi(label),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visitIsi = {
      '',
      ...Pelanggan.hariVisit,
      if (_visit.isNotEmpty) _visit,
    }.toList();
    final ruteIsi = [
      '',
      ...{for (final s in _sales) s.rute, if (_rute.isNotEmpty) _rute},
    ];
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
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubah pelanggan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Tema.biru,
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
                        _fieldTeks(_id, 'Id', min: 100, max: 160, enabled: false),
                        _fieldTeks(
                          _nama,
                          'Nama toko',
                          min: 180,
                          max: 320,
                          cap: TextCapitalization.characters,
                        ),
                        SizedBox(
                          width: _lebarIsi(_rute, 'Rute sales', min: 140, max: 220),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('rute-$_rute-${_sales.length}'),
                            initialValue: ruteIsi.contains(_rute) ? _rute : '',
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 14, color: Colors.black),
                            decoration: _isi('Rute sales'),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('(kosong)'),
                              ),
                              for (final s in _sales)
                                DropdownMenuItem(
                                  value: s.rute,
                                  child: Text(
                                    s.nama.isEmpty ? s.rute : '${s.rute} · ${s.nama}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (_rute.isNotEmpty &&
                                  !_sales.any((s) => s.rute == _rute))
                                DropdownMenuItem(
                                  value: _rute,
                                  child: Text(_rute),
                                ),
                            ],
                            onChanged: (v) => setState(() => _rute = v ?? ''),
                          ),
                        ),
                        SizedBox(
                          width: _lebarIsi(_visit, 'Hari visit', min: 120, max: 160),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('visit-$_visit'),
                            initialValue: visitIsi.contains(_visit) ? _visit : '',
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 14, color: Colors.black),
                            decoration: _isi('Hari visit'),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('(kosong)'),
                              ),
                              for (final h in Pelanggan.hariVisit)
                                DropdownMenuItem(value: h, child: Text(h)),
                              if (_visit.isNotEmpty &&
                                  !Pelanggan.hariVisit.contains(_visit))
                                DropdownMenuItem(
                                  value: _visit,
                                  child: Text(_visit),
                                ),
                            ],
                            onChanged: (v) => setState(() => _visit = v ?? ''),
                          ),
                        ),
                        SizedBox(
                          width: _lebarIsi(_urutan.text, 'Urutan', min: 80, max: 110),
                          child: TextField(
                            controller: _urutan,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(fontSize: 14),
                            decoration: _isi('Urutan'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        _fieldTeks(_lat, 'Latitude', min: 110, max: 160),
                        _fieldTeks(_lng, 'Longitude', min: 110, max: 160),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Aktif di lapangan',
                        style: TextStyle(fontSize: 14),
                      ),
                      value: _aktif,
                      onChanged: (v) => setState(() => _aktif = v),
                    ),
                    Text(
                      'Toko baru dari aplikasi salesman (GPS). Di sini hanya ubah data.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _proses ? null : _simpan,
                      child: Text(_proses ? 'Menyimpan…' : 'Simpan pelanggan'),
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
