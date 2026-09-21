import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../absensi/absensi_repo.dart';
import '../jaringan.dart';
import '../umpan.dart';

class PengirimDrawer extends StatelessWidget {
  const PengirimDrawer({
    super.key,
    required this.nama,
    required this.rutePengirim,
    required this.ruteSales,
    required this.teksTanggal,
    required this.sedangMuat,
    required this.sudahMasuk,
    required this.onPilihTanggal,
    required this.onScanAbsensi,
  });

  final String nama;
  final String rutePengirim;
  final List<String> ruteSales;
  final String teksTanggal;
  final bool sedangMuat;
  final bool sudahMasuk;
  final VoidCallback onPilihTanggal;
  final VoidCallback onScanAbsensi;

  String get _teksRute {
    if (rutePengirim.isNotEmpty) return rutePengirim;
    if (ruteSales.isEmpty) return 'Memuat rute...';
    return ruteSales.join(' · ');
  }

  Future<void> _keluar(BuildContext context) async {
    Navigator.pop(context);
    try {
      await AbsensiRepo(Supabase.instance.client).status();
    } catch (e) {
      if (!context.mounted) return;
      if (Jaringan.mati(e)) {
        umpan(
          context,
          'Tidak ada internet. Sambungkan internet, lalu tekan Keluar lagi.',
        );
        return;
      }
    }
    if (!context.mounted) return;
    context.read<AuthBloc>().add(MintaKeluar());
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ColoredBox(
            color: Tema.biru,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Row(
                  children: [
                    Image(
                      image: AssetImage('assets/icon/app_icon_white.png'),
                      height: 56,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Obos Powered By Alhan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rute: $_teksRute',
                  style: const TextStyle(fontSize: 14, color: Tema.redup),
                ),
                if (rutePengirim.isNotEmpty && ruteSales.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Rute sales: ${ruteSales.join(' · ')}',
                    style: const TextStyle(fontSize: 13, color: Tema.redup),
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: Tema.sudut,
                  onTap: sedangMuat
                      ? null
                      : () {
                          Navigator.pop(context);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onPilihTanggal();
                          });
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          color: sedangMuat ? Colors.grey : Tema.biru,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih tanggal buku',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: sedangMuat ? Colors.grey : Colors.black,
                                ),
                              ),
                              Text(
                                teksTanggal,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Tema.redup,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: Icon(
              sudahMasuk
                  ? Icons.logout_outlined
                  : Icons.qr_code_scanner_outlined,
              color: sudahMasuk ? const Color(0xFF2E7D32) : Colors.orange.shade800,
            ),
            title: Text(sudahMasuk ? 'Scan pulang' : 'Scan masuk'),
            subtitle: Text(
              sudahMasuk ? 'Sudah absen masuk' : 'Belum absen masuk',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: sudahMasuk
                    ? const Color(0xFF2E7D32)
                    : Colors.orange.shade800,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              onScanAbsensi();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_outlined, color: Tema.biru),
            title: const Text(
              'Keluar aplikasi',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => _keluar(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
