import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';

import 'pelanggan.dart';
import 'pelanggan_bloc.dart';
import 'pelanggan_event.dart';
import 'pelanggan_state.dart';

class KunjunganSesi {
  static const _hariKunci = 'kunjungan_hari';

  static final ValueNotifier<
          ({Pelanggan toko, bool bypass, bool selesaiMinggu})?>
      kunci = ValueNotifier(null);

  static void kunciToko(
    Pelanggan toko, {
    required bool bypass,
    bool selesaiMinggu = false,
  }) {
    kunci.value = (
      toko: toko,
      bypass: bypass,
      selesaiMinggu: selesaiMinggu,
    );
  }

  static void bukaDaftar() {
    kunci.value = null;
  }

  static Future<String> hariDaftar(BuildContext context) async {
    final dariState = context.read<PelangganBloc>().state.hariDaftar?.trim();
    if (dariState != null && dariState.isNotEmpty) return dariState;
    return (await SesiHp.hariTerakhir())?.trim() ?? '';
  }

  static Future<String?> hariTersimpan() async {
    final hari = (await PrefsHp.getString(_hariKunci))?.trim();
    if (hari != null && hari.isNotEmpty) return hari;
    return (await SesiHp.hariTerakhir())?.trim();
  }

  static Future<void> simpanHari(String hari) async {
    final nama = hari.trim();
    if (nama.isEmpty) {
      await PrefsHp.hapus(_hariKunci);
      return;
    }
    await PrefsHp.setString(_hariKunci, nama);
    await SesiHp.setHari(nama);
  }

  static Future<void> setSesi({
    required Pelanggan toko,
    required bool bypass,
    bool selesaiMinggu = false,
    required String hari,
  }) async {
    await SesiHp.setKunjungan(
      id: toko.id,
      bypass: bypass,
      selesaiMinggu: selesaiMinggu,
    );
    await simpanHari(hari);
    kunciToko(toko, bypass: bypass, selesaiMinggu: selesaiMinggu);
  }

  static Future<void> keluarKeDaftar(BuildContext context) async {
    final hari = await hariTersimpan();
    await SesiHp.hapusKunjungan();
    await PrefsHp.hapus(_hariKunci);
    if (hari != null && hari.isNotEmpty) {
      await SesiHp.setHari(hari);
      if (context.mounted) {
        final bloc = context.read<PelangganBloc>();
        final selesai = bloc.stream.firstWhere((s) {
          if (s is PelangganMemuat) return false;
          return s.hariDaftar == hari;
        });
        bloc.add(MuatHari(hari, paksa: true));
        await selesai;
      }
    }
    bukaDaftar();
  }
}
