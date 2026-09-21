import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jaga_antrian.dart';
import '../pelanggan/dialog_tambah_pelanggan.dart';
import '../pesan.dart';
import '../pelanggan/kunjungan_sesi.dart';
import '../pelanggan/pelanggan.dart';
import '../pelanggan/pelanggan_bloc.dart';
import '../pelanggan/pelanggan_cache.dart';
import '../pelanggan/pelanggan_event.dart';
import '../pelanggan/pelanggan_state.dart';
import '../pelanggan/peta_hari_layar.dart';
import '../pelanggan/toko_drawer.dart';
import '../pelanggan/toko_kartu.dart';
import '../pelanggan/toko_layar.dart';
import '../transaksi/transaksi_repo.dart';

class CangkangLayar extends StatefulWidget {
  const CangkangLayar({
    super.key,
    required this.nama,
    required this.rute,
    this.info,
  });

  final String nama;
  final String rute;
  final String? info;

  static bool _sesiSudah = false;

  @override
  State<CangkangLayar> createState() => _CangkangLayarState();
}

class _CangkangLayarState extends State<CangkangLayar> {
  static const _hari = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  String _hariPilih = 'Senin';
  bool _tungguSesi = true;
  String? _idTunggu;
  bool _bypassKunci = false;
  bool _selesaiMingguKunci = false;
  final _jagaAntrian = JagaAntrian();

  String _hariIni() {
    final w = DateTime.now().weekday;
    return (w >= 1 && w <= 7) ? _hari[w - 1] : 'Senin';
  }

  @override
  void initState() {
    super.initState();
    final info = widget.info;
    if (info != null && info.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tampilPesan(context, info);
      });
    }
    _siapkanSesi();
    _jagaAntrian.mulai(
      kirim: () => TransaksiRepo(Supabase.instance.client).kirimTertunda(),
      setelah: (_, sisa) async {
        if (!mounted || sisa <= 0) return;
        tampilPesan(
          context,
          sisa == 1
              ? '1 nota belum terunggah. Akan dicoba lagi saat ada internet.'
              : '$sisa nota belum terunggah. Akan dicoba lagi saat ada internet.',
        );
      },
    );
  }

  @override
  void dispose() {
    _jagaAntrian.berhenti();
    super.dispose();
  }

  @override
  void didUpdateWidget(CangkangLayar old) {
    super.didUpdateWidget(old);
    final info = widget.info;
    if (info != null && info.isNotEmpty && info != old.info) {
      tampilPesan(context, info);
    }
  }

  Future<Pelanggan?> _cariToko(String id) async {
    final semua = await PelangganCache.semua();
    for (final t in semua) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _siapkanSesi() async {
    final aktif = await SesiHp.kunjunganAktif();
    if (!mounted) return;
    if (aktif != null) {
      final toko = await _cariToko(aktif.id);
      if (!mounted) return;
      if (toko != null) {
        KunjunganSesi.kunciToko(
          toko,
          bypass: aktif.bypass,
          selesaiMinggu: aktif.selesaiMinggu,
        );
      } else {
        _idTunggu = aktif.id;
        _bypassKunci = aktif.bypass;
        _selesaiMingguKunci = aktif.selesaiMinggu;
      }
    } else {
      KunjunganSesi.bukaDaftar();
    }
    _tungguSesi = false;
    setState(() {});
    await _siapkanHari(
      hariSesi: aktif == null ? null : await KunjunganSesi.hariTersimpan(),
      kunciAktif: aktif != null,
    );
  }

  Future<void> _selesaikanTunggu(PelangganSiap state) async {
    final id = _idTunggu;
    if (id == null || KunjunganSesi.kunci.value != null) return;
    final toko = await _cariToko(id);
    if (!mounted) return;
    if (toko != null) {
      _idTunggu = null;
      KunjunganSesi.kunciToko(
        toko,
        bypass: _bypassKunci,
        selesaiMinggu: _selesaiMingguKunci,
      );
      setState(() {});
      return;
    }
    if (state.dariCache) return;
    await SesiHp.hapusKunjungan();
    if (!mounted) return;
    setState(() => _idTunggu = null);
  }

  Future<void> _siapkanHari({String? hariSesi, bool kunciAktif = false}) async {
    final hariIni = _hariIni();
    final terakhir = await SesiHp.hariTerakhir();
    final kunciHari = hariSesi?.trim();
    if (kunciHari != null && kunciHari.isNotEmpty) {
      _hariPilih = kunciHari;
    } else if (kunciAktif) {
      _hariPilih = terakhir ?? hariIni;
    } else if (!CangkangLayar._sesiSudah) {
      _hariPilih = hariIni;
    } else {
      _hariPilih = terakhir ?? hariIni;
    }
    CangkangLayar._sesiSudah = true;
    await SesiHp.setHari(_hariPilih);
    if (!mounted) return;
    context.read<PelangganBloc>().add(MuatHari(_hariPilih));
    setState(() {});
  }

  String _hariDari(PelangganState state) {
    if (state is PelangganSiap) return state.hari;
    if (state is PelangganKosongNet) return state.hari;
    if (state is PelangganMemuat) return state.hari;
    if (state is PelangganGagal) return state.hari;
    return _hariPilih;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KunjunganSesi.kunci,
      builder: (context, _) {
        return BlocConsumer<PelangganBloc, PelangganState>(
          listener: (context, state) {
            if (state is PelangganSiap) {
              _hariPilih = state.hari;
              SesiHp.setHari(state.hari);
              _selesaikanTunggu(state);
            }
            if (state is PelangganKosongNet) {
              _hariPilih = state.hari;
              if (KunjunganSesi.kunci.value == null && _idTunggu == null) {
                tampilPesan(
                  context,
                  'Tidak ada internet. Sambungkan internet, lalu unduh rute hari ini.',
                );
              }
            }
          },
          builder: (context, state) {
            final kunci = KunjunganSesi.kunci.value;
            if (_tungguSesi || (_idTunggu != null && kunci == null)) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (kunci != null) {
              return TokoLayar(
                toko: kunci.toko,
                bypass: kunci.bypass,
                selesaiMinggu: kunci.selesaiMinggu,
              );
            }
            final hari = _hariDari(state);
            final unduh = state is PelangganMemuat;
            return Scaffold(
              appBar: AppBar(
                leading: Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu_outlined),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                title: Text(
                  hari,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                actionsPadding: const EdgeInsets.only(right: 12),
                actions: [
                  if (state is PelangganSiap)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Peta toko hari ini',
                          icon: const Icon(Icons.map_outlined, size: 26),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => PetaHariLayar(
                                  hari: state.hari,
                                  toko: List<Pelanggan>.from(state.daftar),
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Tambah toko',
                          icon: const Icon(
                            Icons.person_add_alt_1_outlined,
                            size: 26,
                          ),
                          onPressed: () => DialogTambahPelanggan.tampil(
                            context,
                            hari: state.hari,
                            rute: state.rute,
                          ),
                        ),
                      ],
                    ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: unduh
                      ? LinearProgressIndicator(
                          backgroundColor: Tema.seed.withAlpha(30),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Tema.seed,
                          ),
                        )
                      : const SizedBox(height: 4),
                ),
              ),
              drawer: TokoDrawer(
                nama: widget.nama,
                rute: widget.rute,
                hariAktif: hari,
                daftarHari: _hari,
                sedangUnduh: unduh,
              ),
              body: _isi(state),
            );
          },
        );
      },
    );
  }

  Widget _isi(PelangganState state) {
    if (state is PelangganMemuat) {
      return _tarik(
        state.hari,
        ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: 5,
          itemBuilder: (context, index) => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 48,
                child: ColoredBox(color: Color(0x11000000)),
              ),
            ),
          ),
        ),
      );
    }
    if (state is PelangganKosongNet) {
      return _kosongTarik(
        hari: state.hari,
        ikon: Icons.cloud_off_outlined,
        teks: 'Rute hari ini belum terunduh.',
      );
    }
    if (state is PelangganGagal) {
      return _kosongTarik(
        hari: state.hari,
        ikon: Icons.cloud_off_outlined,
        teks: state.pesan,
      );
    }
    if (state is PelangganSiap) {
      final items = state.daftar;
      if (items.isEmpty) {
        return _kosongTarik(
          hari: state.hari,
          ikon: Icons.storefront_outlined,
          teks: 'Tidak ada rute kunjungan untuk hari ini.',
        );
      }
      return _tarik(
        state.hari,
        ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 24, top: 8),
          buildDefaultDragHandles: false,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length,
          onReorderItem: (lama, baru) {
            context.read<PelangganBloc>().add(
              GeserUrutan(lama: lama, baru: baru),
            );
          },
          itemBuilder: (context, i) => TokoKartu(
            key: ValueKey(items[i].id),
            item: items[i],
            urutanGeser: i,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _unduhHari(String hari) async {
    context.read<PelangganBloc>().add(MuatHari(hari, paksa: true));
    await context.read<PelangganBloc>().stream.firstWhere(
      (s) => s is! PelangganMemuat,
    );
  }

  Widget _tarik(String hari, Widget child) {
    return RefreshIndicator(
      color: Tema.biru,
      onRefresh: () => _unduhHari(hari),
      child: child,
    );
  }

  Widget _kosongTarik({
    required String hari,
    required IconData ikon,
    required String teks,
  }) {
    return _tarik(
      hari,
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(ikon, size: 64, color: Tema.biru),
          const SizedBox(height: 16),
          Text(teks, textAlign: TextAlign.center, style: const TextStyle(color: Tema.redup)),
        ],
      ),
    );
  }
}
