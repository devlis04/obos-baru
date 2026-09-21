import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';

import '../buka_maps.dart';
import '../pesan.dart';
import 'pelanggan.dart';
import 'kunjungan_sesi.dart';
import 'pelanggan_bloc.dart';
import 'scan_layar.dart';

class TokoKartu extends StatelessWidget {
  const TokoKartu({super.key, required this.item, this.urutanGeser});

  final Pelanggan item;
  final int? urutanGeser;

  Future<void> _peta(BuildContext context) {
    return bukaMapsToko(
      context: context,
      nama: item.nama,
      latitude: item.latitude,
      longitude: item.longitude,
    );
  }

  Future<void> _buka(BuildContext context) async {
    if (item.id.startsWith('TMP')) {
      tampilPesan(
        context,
        'Toko baru belum punya kode cloud. Sambungkan internet, unduh rute, lalu scan lagi.',
      );
      return;
    }
    if (item.selesaiMingguIni) {
      await KunjunganSesi.setSesi(
        toko: item,
        bypass: false,
        selesaiMinggu: true,
        hari: await KunjunganSesi.hariDaftar(context),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: context.read<PelangganBloc>(),
          child: ScanLayar(toko: item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = item.selesaiMingguIni
        ? 'Sudah dikunjungi minggu ini'
        : 'Belum dikunjungi minggu ini';

    final kartu = Card(
      child: ListTile(
        onTap: () => _buka(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          item.nama,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Tema.teksKartu,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Kode: ${item.id}',
              style: const TextStyle(fontSize: 13, color: Tema.teksKartu),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                color: item.selesaiMingguIni ? Tema.seed : Tema.redup,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.location_on_outlined,
                color: Tema.seed,
                size: 26,
              ),
              tooltip: 'Buka Maps',
              onPressed: () => _peta(context),
            ),
            IconButton(
              icon: Icon(
                item.selesaiMingguIni
                    ? Icons.storefront_outlined
                    : Icons.qr_code_scanner_outlined,
                color: Tema.seed,
                size: 26,
              ),
              tooltip: item.selesaiMingguIni
                  ? 'Buka toko'
                  : 'Scan masuk toko',
              onPressed: () => _buka(context),
            ),
          ],
        ),
      ),
    );

    final i = urutanGeser;
    if (i == null) return kartu;
    return ReorderableDelayedDragStartListener(index: i, child: kartu);
  }
}
