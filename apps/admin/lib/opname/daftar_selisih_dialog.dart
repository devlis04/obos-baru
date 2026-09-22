import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'opname_repo.dart';

Future<void> bukaDaftarSelisih({
  required BuildContext context,
  required RingkasOpname data,
  required Future<void> Function() onMuat,
}) async {
  final id = data.idSetoranBuku;
  if (id == null) return;
  final repo = OpnameRepo(Supabase.instance.client);
  List<BarisSelisihOpname> baris;
  List<UserKasbon> users;
  try {
    baris = await repo.selisih(id);
    users = await repo.usersKasbon();
  } catch (e) {
    if (!context.mounted) return;
    tampilPesan(
      context,
      Jaringan.mati(e)
          ? 'Tidak ada internet. Daftar selisih belum bisa dibuka.'
          : 'Daftar selisih belum bisa dibaca.',
    );
    return;
  }
  if (!context.mounted) return;
  if (baris.isEmpty) {
    tampilPesan(
      context,
      data.skuFisik == 0
          ? 'Belum ada stok fisik dari gudang.'
          : 'Tidak ada selisih stok.',
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => DaftarSelisihDialog(
      idBuku: id,
      ditutup: data.ditutup,
      awal: baris,
      users: users,
      onMuat: onMuat,
    ),
  );
}

class DaftarSelisihDialog extends StatefulWidget {
  const DaftarSelisihDialog({
    super.key,
    required this.idBuku,
    required this.ditutup,
    required this.awal,
    required this.users,
    required this.onMuat,
  });

  final int idBuku;
  final bool ditutup;
  final List<BarisSelisihOpname> awal;
  final List<UserKasbon> users;
  final Future<void> Function() onMuat;

  @override
  State<DaftarSelisihDialog> createState() => _DaftarSelisihDialogState();
}

class _DaftarSelisihDialogState extends State<DaftarSelisihDialog> {
  final _repo = OpnameRepo(Supabase.instance.client);
  late List<BarisSelisihOpname> _baris = widget.awal;
  final Map<String, String> _pilih = {};
  String? _prosesSku;
  String? _pesan;

  @override
  void initState() {
    super.initState();
    for (final r in _baris) {
      if (r.kasbonEmail.isNotEmpty) _pilih[r.idBarang] = r.kasbonEmail;
    }
  }

  Future<void> _konfirmasiFisik() async {
    if (widget.ditutup || _prosesSku != null) return;
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Konfirmasi stok fisik?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: IsiDialog(
          child: const Text(
            'Stok master SKU yang sudah dihitung fisik akan mengikuti fisik gudang. Buku tidak ditutup.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, konfirmasi'),
          ),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    setState(() => _prosesSku = '_fisik');
    try {
      await _repo.konfirmasi(widget.idBuku);
      if (!mounted) return;
      setState(() => _prosesSku = null);
      await widget.onMuat();
      if (!mounted) return;
      tampilPesan(context, 'Stok master sudah mengikuti fisik gudang.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _prosesSku = null);
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Konfirmasi belum tersimpan.'
            : (e is PostgrestException && e.message.trim().isNotEmpty
                ? e.message.trim()
                : 'Konfirmasi stok belum tersimpan.'),
      );
    }
  }

  Future<void> _putusan(BarisSelisihOpname r, String jenis) async {
    if (widget.ditutup || _prosesSku != null) return;
    final email = _pilih[r.idBarang];
    if (jenis == 'kasbon' && widget.users.isEmpty) {
      setState(() => _pesan = 'Tidak ada karyawan di daftar kasbon.');
      return;
    }
    if (jenis == 'kasbon' && (email == null || email.isEmpty)) {
      setState(
        () => _pesan = 'Pilih karyawan untuk kasbon, baru tekan Kasbon.',
      );
      return;
    }
    setState(() {
      _prosesSku = r.idBarang;
      _pesan = null;
    });
    try {
      final hasil = await _repo.putusan(
        idBuku: widget.idBuku,
        idBarang: r.idBarang,
        jenis: jenis,
        email: jenis == 'kasbon' ? email : null,
      );
      final baru = await _repo.selisih(widget.idBuku);
      if (!mounted) return;
      final cek = baru.where((b) => b.idBarang == r.idBarang).toList();
      final dariRpc = (hasil['putusan']?.toString() ?? '') == jenis;
      final dariDb = cek.isNotEmpty && cek.first.putusan == jenis;
      final nilai = int.tryParse('${hasil['nilai']}') ??
          (cek.isNotEmpty ? cek.first.nilaiPutusan : 0);
      setState(() {
        _baris = baru;
        _prosesSku = null;
        _pesan = dariDb || dariRpc
            ? (jenis == 'kasbon'
                ? 'Kasbon ${hasil['kasbon_nama'] ?? cek.firstOrNull?.kasbonNama ?? ''} ${Uang.rp(nilai)} tersimpan.'
                : 'Selisih masuk potong margin.')
            : 'Putusan belum tertulis di buku. Jalankan SQL 090, lalu ulangi.';
      });
      await widget.onMuat();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _prosesSku = null;
        _pesan = Jaringan.mati(e)
            ? 'Tidak ada internet. Putusan belum tersimpan.'
            : (e is PostgrestException && e.message.trim().isNotEmpty
                ? e.message.trim()
                : 'Putusan belum tersimpan.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Selisih opname (${_baris.length})',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pesan != null) ...[
              Text(
                _pesan!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
            ],
            DaftarGulirDialog(
              faktor: 0.5,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                primary: false,
                itemCount: _baris.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _kartuBaris(_baris[i]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _prosesSku != null ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        if (!widget.ditutup)
          FilledButton(
            onPressed: _prosesSku != null ? null : _konfirmasiFisik,
            child: const Text('Konfirmasi stok fisik'),
          ),
      ],
    );
  }

  Widget _kartuBaris(BarisSelisihOpname r) {
    final kurang = r.selisih < 0;
    final sibuk = _prosesSku == r.idBarang;
    final emailPilih = _pilih[r.idBarang];
    const tombol = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(0, 32)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.nama,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Hitung ${Uang.qty(r.stokHitung)}  ·  '
                'Fisik ${Uang.qty(r.stokFisik)}  ·  '
                'Selisih ${Uang.qty(r.selisih)}',
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
              Text(
                Uang.rp(r.nilaiSelisih.abs()),
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
              if (r.dicekOleh.isNotEmpty)
                Text(
                  'Dicek ${r.dicekOleh}',
                  style: const TextStyle(fontSize: 12, color: Tema.redup),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _tokoPacked(r),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _statusTeks(r, kurang),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: kurang
                      ? Colors.orange.shade800
                      : const Color(0xFF2E7D32),
                ),
              ),
              if (kurang && !widget.ditutup) ...[
                const SizedBox(height: 6),
                if (widget.users.isEmpty)
                  const Text(
                    'Tidak ada karyawan untuk kasbon.',
                    style: TextStyle(fontSize: 12, color: Colors.black),
                  )
                else
                  DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    hint: const Text('Karyawan kasbon'),
                    value: widget.users.any((u) => u.email == emailPilih)
                        ? emailPilih
                        : null,
                    items: [
                      for (final u in widget.users)
                        DropdownMenuItem(
                          value: u.email,
                          child: Text(
                            '${u.nama} (${u.peran})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: sibuk
                        ? null
                        : (v) => setState(() {
                              if (v == null) {
                                _pilih.remove(r.idBarang);
                              } else {
                                _pilih[r.idBarang] = v;
                              }
                            }),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    FilledButton(
                      style: tombol,
                      onPressed: sibuk ? null : () => _putusan(r, 'kasbon'),
                      child: Text(sibuk ? '…' : 'Kasbon'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      style: tombol,
                      onPressed: sibuk ? null : () => _putusan(r, 'beban'),
                      child: const Text('Potong margin'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tokoPacked(BarisSelisihOpname r) {
    if (r.tokoPacked.isEmpty) {
      return const Text(
        'Belum ada packing',
        style: TextStyle(
          fontSize: 14,
          color: Tema.redup,
        ),
      );
    }
    final n = r.tokoPacked.length;
    final qty = r.tokoPacked.fold<num>(0, (a, t) => a + t.qty);
    return Align(
      alignment: Alignment.centerLeft,
      child: MenuAnchor(
        builder: (context, controller, _) {
          return OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
            ),
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$n toko · ${Uang.qty(qty)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black,
                  ),
                ),
                Icon(
                  controller.isOpen
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: Colors.black,
                ),
              ],
            ),
          );
        },
        menuChildren: [
          for (final t in r.tokoPacked)
            MenuItemButton(
              onPressed: () {},
              child: SizedBox(
                width: 280,
                child: Text(
                  '${t.nama}  ·  ${Uang.qty(t.qty)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusTeks(BarisSelisihOpname r, bool kurang) {
    if (!kurang) return 'Tambah margin ${Uang.rp(r.nilaiSelisih.abs())}';
    if (r.putusan == 'kasbon') {
      return 'Kasbon ${r.kasbonNama} · ${Uang.rp(r.nilaiPutusan)}';
    }
    if (r.putusan == 'beban') {
      return 'Potong margin ${Uang.rp(r.nilaiPutusan)}';
    }
    return 'Belum diputuskan';
  }
}
