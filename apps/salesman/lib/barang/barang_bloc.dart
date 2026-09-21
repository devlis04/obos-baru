import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import '../transaksi/transaksi_repo.dart';
import 'barang_cache.dart';
import 'barang_event.dart';
import 'barang_repo.dart';
import 'barang_state.dart';
import 'pesan_katalog.dart';

class BarangBloc extends Bloc<BarangEvent, BarangState> {
  BarangBloc() : super(BarangAwal()) {
    on<MuatBarang>(_onMuat);
    on<TandaiPesan>(_onTandai);
    on<TandaiSemuaPesan>(_onTandaiSemua);
  }

  final _repo = BarangRepo(Supabase.instance.client);
  final _nota = TransaksiRepo(Supabase.instance.client);

  Future<void> _onMuat(MuatBarang event, Emitter<BarangState> emit) async {
    await _nota.kirimTertunda();
    final lokal = await BarangCache.semua();
    final notices = await PesanKatalogStore.semua();
    if (!event.paksa && lokal.isNotEmpty) {
      emit(BarangSiap(lokal, dariCache: true, notices: notices));
    } else if (lokal.isEmpty) {
      emit(BarangMemuat());
    }

    try {
      final cloud = await _repo.unduh(
        batas: event.paksa || lokal.isEmpty ? Jaringan.lambat : Jaringan.cepat,
      );
      final ubah = KatalogBerubah.bandingkan(lokal: lokal, server: cloud);
      await PesanKatalogStore.simpanDari(ubah);
      emit(BarangSiap(cloud, notices: await PesanKatalogStore.semua()));
    } catch (_) {
      if (lokal.isNotEmpty) {
        emit(
          BarangSiap(
            lokal,
            dariCache: true,
            notices: await PesanKatalogStore.semua(),
          ),
        );
      } else {
        emit(BarangKosongNet());
      }
    }
  }

  Future<void> _onTandai(TandaiPesan event, Emitter<BarangState> emit) async {
    await PesanKatalogStore.tandaiDibaca(event.id);
    await _kirimNotice(emit);
  }

  Future<void> _onTandaiSemua(
    TandaiSemuaPesan event,
    Emitter<BarangState> emit,
  ) async {
    await PesanKatalogStore.tandaiSemua();
    await _kirimNotice(emit);
  }

  Future<void> _kirimNotice(Emitter<BarangState> emit) async {
    final current = state;
    if (current is! BarangSiap) return;
    emit(
      BarangSiap(
        current.daftar,
        dariCache: current.dariCache,
        notices: await PesanKatalogStore.semua(),
      ),
    );
  }
}
