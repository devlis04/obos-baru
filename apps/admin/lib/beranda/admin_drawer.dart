import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

enum HalamanAdmin { dashboard, setoran, barang, pelanggan }

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key, required this.halaman});

  final HalamanAdmin halaman;

  void _tutup(BuildContext context) {
    Navigator.pop(context);
  }

  void _keDashboard(BuildContext context) {
    final nav = Navigator.of(context);
    _tutup(context);
    if (halaman == HalamanAdmin.dashboard) return;
    nav.pushNamedAndRemoveUntil('/dashboard', (r) => false);
  }

  void _keSetoran(BuildContext context) {
    final nav = Navigator.of(context);
    _tutup(context);
    if (halaman == HalamanAdmin.setoran) return;
    nav.pushNamedAndRemoveUntil('/', (r) => false);
  }

  void _keBarang(BuildContext context) {
    final nav = Navigator.of(context);
    _tutup(context);
    if (halaman == HalamanAdmin.barang) return;
    nav.pushNamedAndRemoveUntil('/barang', (r) => false);
  }

  void _kePelanggan(BuildContext context) {
    final nav = Navigator.of(context);
    _tutup(context);
    if (halaman == HalamanAdmin.pelanggan) return;
    nav.pushNamedAndRemoveUntil('/pelanggan', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final nama = auth is AuthMasuk ? auth.nama : '';

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
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Peran: Admin',
                  style: TextStyle(fontSize: 14, color: Tema.redup),
                ),
              ],
            ),
          ),
          ListTile(
            selected: halaman == HalamanAdmin.dashboard,
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Dashboard'),
            onTap: () => _keDashboard(context),
          ),
          ListTile(
            selected: halaman == HalamanAdmin.setoran,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Setoran'),
            onTap: () => _keSetoran(context),
          ),
          ListTile(
            selected: halaman == HalamanAdmin.barang,
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Barang'),
            onTap: () => _keBarang(context),
          ),
          ListTile(
            selected: halaman == HalamanAdmin.pelanggan,
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Pelanggan'),
            onTap: () => _kePelanggan(context),
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_outlined, color: Tema.biru),
            title: const Text(
              'Keluar',
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
