import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaringan.dart';
import 'pelanggan.dart';
import 'pelanggan_cache.dart';
import 'pelanggan_event.dart';
import 'pelanggan_repo.dart';
import 'pelanggan_state.dart';

class PelangganBloc extends Bloc<PelangganEvent, PelangganState> {
  PelangganBloc({required this.rute}) : super(PelangganAwal()) {
    on<MuatHari>(_onMuat);
    on<GeserUrutan>(_onGeser);
    on<TambahPelanggan>(_onTambah);
    on<CatatKunjungan>(_onCatat);
    on<_KirimUrutan>(_onKirim);
  }

  final String rute;
  final _repo = PelangganRepo(Supabase.instance.client);
  Timer? _timerUrutan;
  String? _pendingHari;
  List<String>? _pendingId;

  Future<void> _onMuat(MuatHari event, Emitter<PelangganState> emit) async {
    if (rute.trim().isEmpty) {
      emit(PelangganGagal('Rute pengguna belum diatur oleh admin.', event.hari));
      return;
    }

    await _flushUrutan();
    await _kirimTokoTmp();

    final cache = await PelangganCache.semua();
    final lokal = PelangganCache.saring(cache, event.hari, rute);
    if (!event.paksa && lokal.isNotEmpty) {
      emit(
        PelangganSiap(
          hari: event.hari,
          rute: rute,
          daftar: lokal,
          dariCache: true,
        ),
      );
    } else {
      emit(PelangganMemuat(event.hari));
    }

    if (_pendingHari == event.hari) {
      emit(PelangganSiap(hari: event.hari, rute: rute, daftar: lokal));
      return;
    }

    try {
      await _repo.unduhRute(
        rute,
        batas: event.paksa || lokal.isEmpty ? Jaringan.lambat : Jaringan.cepat,
      );
      final cacheBaru = await PelangganCache.semua();
      final hariIni = PelangganCache.saring(cacheBaru, event.hari, rute);
      emit(PelangganSiap(hari: event.hari, rute: rute, daftar: hariIni));
    } catch (_) {
      if (lokal.isNotEmpty) {
        emit(
          PelangganSiap(
            hari: event.hari,
            rute: rute,
            daftar: lokal,
            dariCache: true,
          ),
        );
      } else if (cache.isEmpty) {
        emit(PelangganKosongNet(event.hari, rute));
      } else {
        emit(
          PelangganGagal(
            'Tidak bisa mengunduh toko. Periksa internet, lalu tarik ulang.',
            event.hari,
          ),
        );
      }
    }
  }

  Future<void> _onGeser(GeserUrutan event, Emitter<PelangganState> emit) async {
    if (state is! PelangganSiap) return;
    final s = state as PelangganSiap;
    final baru = event.baru;
    if (event.lama < 0 ||
        event.lama >= s.daftar.length ||
        baru < 0 ||
        baru >= s.daftar.length ||
        event.lama == baru) {
      return;
    }

    final list = [...s.daftar];
    final item = list.removeAt(event.lama);
    list.insert(baru, item);
    final terurut = [
      for (var i = 0; i < list.length; i++) list[i].salin(urutan: i + 1),
    ];
    await PelangganCache.timpaHari(
      hari: s.hari,
      rute: s.rute,
      daftar: terurut,
    );
    emit(PelangganSiap(hari: s.hari, rute: s.rute, daftar: terurut));

    _pendingHari = s.hari;
    _pendingId = terurut.map((t) => t.id).toList();
    _timerUrutan?.cancel();
    _timerUrutan = Timer(const Duration(milliseconds: 500), () {
      add(_KirimUrutan());
    });
  }

  Future<void> _onTambah(
    TambahPelanggan event,
    Emitter<PelangganState> emit,
  ) async {
    var ok = false;
    try {
      await _flushUrutan();
      if (state is! PelangganSiap) return;
      final s = state as PelangganSiap;
      final nextUrutan = s.daftar.fold<int>(0, (m, t) {
            final u = t.urutan ?? 0;
            return u > m ? u : m;
          }) +
          1;

      final cloudId = await _repo.insertPelanggan(
        nama: event.nama,
        latitude: event.latitude,
        longitude: event.longitude,
        visit: event.hari,
        urutan: nextUrutan,
      );
      final id = cloudId ?? 'TMP${DateTime.now().microsecondsSinceEpoch}';
      final toko = Pelanggan(
        id: id,
        nama: event.nama,
        rute: rute,
        visit: event.hari,
        urutan: nextUrutan,
        latitude: event.latitude,
        longitude: event.longitude,
      );
      await PelangganCache.tambah(toko);
      ok = true;
      if (isClosed) return;
      if (state is PelangganSiap) {
        final now = state as PelangganSiap;
        if (now.hari == event.hari) {
          final cache = await PelangganCache.semua();
          emit(
            PelangganSiap(
              hari: now.hari,
              rute: now.rute,
              daftar: PelangganCache.saring(cache, now.hari, now.rute),
            ),
          );
        }
      }
    } catch (_) {
      if (state is PelangganSiap) {
        final s = state as PelangganSiap;
        emit(PelangganSiap(hari: s.hari, rute: s.rute, daftar: s.daftar));
      }
    } finally {
      if (!event.selesai.isCompleted) event.selesai.complete(ok);
    }
  }

  Future<void> _onCatat(
    CatatKunjungan event,
    Emitter<PelangganState> emit,
  ) async {
    try {
      final semua = await PelangganCache.semua();
      final daftar = [
        for (final t in semua)
          if (t.id == event.id)
            t.salin(
              waktuMasuk: event.waktuMasuk,
              waktuKeluar: event.waktuKeluar,
            )
          else
            t,
      ];
      await PelangganCache.simpan(daftar);
      if (state is! PelangganSiap) return;
      final s = state as PelangganSiap;
      emit(
        PelangganSiap(
          hari: s.hari,
          rute: s.rute,
          daftar: PelangganCache.saring(daftar, s.hari, s.rute),
        ),
      );
    } finally {
      if (!event.selesai.isCompleted) event.selesai.complete();
    }
  }

  Future<void> _onKirim(_KirimUrutan event, Emitter<PelangganState> emit) async {
    await _flushUrutan();
  }

  Future<void> _kirimTokoTmp() async {
    final semua = await PelangganCache.semua();
    for (final t in semua.where((x) => x.id.startsWith('TMP'))) {
      final cloudId = await _repo.insertPelanggan(
        nama: t.nama,
        latitude: t.latitude ?? 0,
        longitude: t.longitude ?? 0,
        visit: t.visit ?? '',
        urutan: t.urutan ?? 0,
      );
      if (cloudId == null) continue;
      await PelangganCache.gantiId(
        t.id,
        Pelanggan(
          id: cloudId,
          nama: t.nama,
          rute: t.rute,
          visit: t.visit,
          urutan: t.urutan,
          latitude: t.latitude,
          longitude: t.longitude,
        ),
      );
    }
  }

  Future<void> _flushUrutan() async {
    _timerUrutan?.cancel();
    final hari = _pendingHari;
    final id = _pendingId;
    if (hari == null || id == null || id.isEmpty) return;
    if (id.any((x) => x.startsWith('TMP'))) return;
    final ok = await _repo.kirimUrutan(visit: hari, id: id);
    if (ok) {
      _pendingHari = null;
      _pendingId = null;
    }
  }

  @override
  Future<void> close() {
    _timerUrutan?.cancel();
    final hari = _pendingHari;
    final id = _pendingId;
    _pendingHari = null;
    _pendingId = null;
    if (hari != null && id != null && id.isNotEmpty) {
      unawaited(_repo.kirimUrutan(visit: hari, id: id));
    }
    return super.close();
  }
}

class _KirimUrutan extends PelangganEvent {}
