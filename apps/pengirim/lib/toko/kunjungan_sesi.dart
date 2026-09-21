import 'package:flutter/foundation.dart';
import 'package:obos_core/obos_core.dart';

import '../beranda/kartu_toko.dart';
import '../uang.dart';

class KunjunganSesi {
  static final ValueNotifier<
      ({KartuToko toko, DateTime tanggal, bool lihatSaja})?>
      kunci = ValueNotifier(null);

  static void kunciToko(
    KartuToko toko,
    DateTime tanggal, {
    bool lihatSaja = false,
  }) {
    kunci.value = (toko: toko, tanggal: tanggal, lihatSaja: lihatSaja);
  }

  static void bukaDaftar() {
    kunci.value = null;
  }

  static Future<void> setSesi({
    required KartuToko toko,
    required DateTime tanggal,
    bool lihatSaja = false,
  }) async {
    await SesiHp.setKunjungan(
      id: toko.idPelanggan,
      bypass: false,
      selesaiMinggu: lihatSaja,
    );
    await SesiHp.setHari(Uang.isoHari(tanggal));
    kunciToko(toko, tanggal, lihatSaja: lihatSaja);
  }

  static Future<void> keluarKeDaftar() async {
    await SesiHp.hapusKunjungan();
    bukaDaftar();
  }
}
