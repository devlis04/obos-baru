import 'dart:async';

import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../beranda/admin_drawer.dart';
import '../jaringan.dart';
import '../pesan.dart';
import 'pelanggan.dart';
import 'pelanggan_csv_dialog.dart';
import 'pelanggan_form.dart';
import 'pelanggan_repo.dart';

class PelangganLayar extends StatefulWidget {
  const PelangganLayar({super.key});

  @override
  State<PelangganLayar> createState() => _PelangganLayarState();
}

class _PelangganLayarState extends State<PelangganLayar> {
  final _repo = PelangganRepo(Supabase.instance.client);
  final _cari = TextEditingController();
  Timer? _tunda;
  List<Pelanggan> _daftar = [];
  bool _muat = true;
  Pelanggan? _pilih;

  @override
  void initState() {
    super.initState();
    _muatCari();
  }

  @override
  void dispose() {
    _tunda?.cancel();
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muatCari({String? tetapId}) async {
    setState(() => _muat = true);
    try {
      final list = await _repo.katalog(_cari.text);
      if (!mounted) return;
      Pelanggan? pilih = _pilih;
      final id = tetapId ?? _pilih?.id;
      if (id != null) {
        final ketemu = list.where((p) => p.id == id);
        pilih = ketemu.isEmpty ? _pilih : ketemu.first;
      }
      setState(() {
        _daftar = list;
        _pilih = pilih;
        _muat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _daftar = [];
        _muat = false;
      });
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Daftar pelanggan belum bisa dimuat.'
            : pesanGagal(e, 'Daftar pelanggan belum bisa dimuat.'),
      );
    }
  }

  void _ketik(String _) {
    _tunda?.cancel();
    _tunda = Timer(const Duration(milliseconds: 350), _muatCari);
  }

  Future<void> _setelahSimpan(Pelanggan p) async {
    setState(() => _pilih = p);
    await _muatCari(tetapId: p.id);
  }

  @override
  Widget build(BuildContext context) {
    final tampilForm = _pilih != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Pelanggan')),
      drawer: const AdminDrawer(halaman: HalamanAdmin.pelanggan),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cari,
                          onChanged: _ketik,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Cari nama, id, rute, hari',
                            prefixIcon: Icon(Icons.search, size: 20),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Tema.biru,
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(56, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => PelangganCsvDialog.buka(
                          context: context,
                          repo: _repo,
                          onSelesai: _muatCari,
                        ),
                        child: const Text('CSV'),
                      ),
                    ],
                  ),
                ),
                if (_muat) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _daftar.isEmpty && !_muat
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 8, 0),
                          child: Text('Tidak ada pelanggan.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 4, 12),
                          itemCount: _daftar.length,
                          itemBuilder: (context, i) {
                            final p = _daftar[i];
                            final pilih = _pilih?.id == p.id;
                            return Card(
                              color: pilih ? const Color(0xFFD6E8F7) : null,
                              margin: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                              child: InkWell(
                                onTap: () => setState(() => _pilih = p),
                                borderRadius: Tema.sudut,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.nama,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: p.aktif
                                              ? Colors.black
                                              : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          p.id,
                                          if (p.rute.isNotEmpty) p.rute,
                                          if (p.visit.isNotEmpty) p.visit,
                                          if (!p.aktif) 'Nonaktif',
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: tampilForm
                ? PelangganPanel(
                    key: ValueKey(_pilih!.id),
                    awal: _pilih!,
                    onTersimpan: _setelahSimpan,
                  )
                : const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 12, 12),
                      child: Text(
                        'Pilih pelanggan di kiri. Toko baru dari aplikasi salesman.',
                        style: TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                    ),
                  ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}
