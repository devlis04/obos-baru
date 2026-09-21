import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_auth/obos_auth.dart';
import 'package:obos_core/obos_core.dart';

import '../dashboard/dashboard_layar.dart';
import 'pelanggan_bloc.dart';
import 'pelanggan_event.dart';

class TokoDrawer extends StatelessWidget {
  const TokoDrawer({
    super.key,
    required this.nama,
    required this.rute,
    required this.hariAktif,
    required this.daftarHari,
    required this.sedangUnduh,
  });

  final String nama;
  final String rute;
  final String hariAktif;
  final List<String> daftarHari;
  final bool sedangUnduh;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
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
                  'Rute: ${rute.isEmpty ? '—' : rute}',
                  style: const TextStyle(fontSize: 14, color: Tema.redup),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Pilih Hari Kunjungan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Tema.redup,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: Tema.sudut,
                    border: Border.all(color: Tema.biru),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: daftarHari.contains(hariAktif)
                          ? hariAktif
                          : daftarHari.first,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      iconEnabledColor: Tema.biru,
                      style: const TextStyle(
                        color: Tema.biru,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      icon: const Icon(
                        Icons.arrow_drop_down_circle_outlined,
                        color: Tema.biru,
                      ),
                      items: daftarHari
                          .map(
                            (hari) => DropdownMenuItem(
                              value: hari,
                              child: Text(
                                hari,
                                style: const TextStyle(
                                  color: Tema.biru,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (baru) {
                        if (baru == null || baru == hariAktif || sedangUnduh) {
                          return;
                        }
                        Navigator.pop(context);
                        context.read<PelangganBloc>().add(MuatHari(baru));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined, color: Tema.biru),
            title: const Text('Ringkasan penjualan'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DashboardLayar(rute: rute),
                ),
              );
            },
          ),
          const Spacer(),
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
