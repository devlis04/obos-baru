import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

class GudangDrawer extends StatelessWidget {
  const GudangDrawer({
    super.key,
    required this.nama,
    required this.peran,
    required this.sudahMasuk,
    required this.onScanAbsensi,
    required this.onPilihTanggal,
    required this.onStokOpname,
  });

  final String nama;
  final String peran;
  final bool sudahMasuk;
  final VoidCallback onScanAbsensi;
  final VoidCallback onPilihTanggal;
  final VoidCallback onStokOpname;

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                  peran == 'admin' ? 'Peran: Admin' : 'Peran: Gudang',
                  style: const TextStyle(fontSize: 14, color: Tema.redup),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined, color: Tema.biru),
            title: const Text('Pilih tanggal buku'),
            onTap: () {
              Navigator.pop(context);
              onPilihTanggal();
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined, color: Tema.biru),
            title: const Text('Stok opname'),
            subtitle: const Text('Isi jumlah fisik barang'),
            onTap: () {
              Navigator.pop(context);
              onStokOpname();
            },
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
            onTap: () {
              Navigator.pop(context);
              context.read<AuthBloc>().add(MintaKeluar());
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
