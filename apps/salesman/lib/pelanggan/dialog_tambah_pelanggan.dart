import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:obos_core/isi_dialog.dart';

import '../buka_maps.dart';
import '../pesan.dart';
import 'pelanggan_bloc.dart';
import 'pelanggan_event.dart';

class DialogTambahPelanggan extends StatefulWidget {
  const DialogTambahPelanggan({
    super.key,
    required this.hari,
    required this.rute,
  });

  final String hari;
  final String rute;

  static Future<void> tampil(
    BuildContext context, {
    required String hari,
    required String rute,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<PelangganBloc>(),
        child: DialogTambahPelanggan(hari: hari, rute: rute),
      ),
    );
  }

  @override
  State<DialogTambahPelanggan> createState() => _DialogTambahPelangganState();
}

class _DialogTambahPelangganState extends State<DialogTambahPelanggan> {
  final _nama = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _mengunci = true;
  bool _menyimpan = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _kunciLokasi();
  }

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  Future<void> _kunciLokasi() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'gps_mati';
      }
      var izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }
      if (izin == LocationPermission.denied ||
          izin == LocationPermission.deniedForever) {
        throw 'izin_lokasi';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (pos.isMocked) throw 'lokasi_palsu';

      if (!mounted) return;
      await bukaMapsToko(
        context: context,
        nama: 'Lokasi Toko Baru',
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _mengunci = false;
      });
    } catch (e) {
      if (!mounted) return;
      _tutupPesan(_pesanGagalLokasi(e));
    }
  }

  String _pesanGagalLokasi(Object error) {
    final teks = error.toString();
    if (teks.contains('gps_mati')) {
      return 'GPS HP belum aktif. Nyalakan GPS, lalu tambah toko lagi.';
    }
    if (teks.contains('izin_lokasi')) {
      return 'Izin lokasi belum diberikan. Izinkan lokasi, lalu tambah toko lagi.';
    }
    if (teks.contains('lokasi_palsu')) {
      return 'Lokasi HP terdeteksi tidak wajar. Matikan aplikasi lokasi palsu, lalu tambah toko lagi.';
    }
    return 'Lokasi toko belum bisa dikunci. Nyalakan GPS, izinkan lokasi, lalu coba lagi.';
  }

  void _tutupPesan(String msg) {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) Navigator.pop(context);
    tampilPesan(context, msg);
  }

  Future<void> _simpan() async {
    if (_menyimpan) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    setState(() => _menyimpan = true);
    final done = Completer<bool>();
    if (!mounted) return;
    context.read<PelangganBloc>().add(
      TambahPelanggan(
        nama: _nama.text.trim().toUpperCase(),
        hari: widget.hari,
        latitude: lat,
        longitude: lng,
        selesai: done,
      ),
    );
    final ok = await done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => false,
    );
    if (!mounted) return;
    if (ok) {
      _tutupPesan('Toko baru sudah disimpan.');
      return;
    }
    setState(() => _menyimpan = false);
    tampilPesan(
      context,
      'Toko baru belum tersimpan. Periksa internet, pastikan sesi masih aktif, lalu coba lagi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mengunci) {
      return const AlertDialog(
        content: IsiDialog(
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text('Mengunci koordinat GPS dan membuka peta...'),
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text(
        'Tambah toko baru',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: IsiDialog(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Koordinat GPS berhasil dikunci. Masukkan nama toko di bawah ini.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nama,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nama toko',
                  hintText: 'MISAL: TOKO SEMBAKO JAYA',
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Nama toko tidak boleh kosong'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _menyimpan ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _menyimpan ? null : _simpan,
          child: _menyimpan
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan toko'),
        ),
      ],
    );
  }
}
