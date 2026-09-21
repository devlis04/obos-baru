import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../absensi/absensi_repo.dart';
import '../absensi/scan_absensi_layar.dart';
import '../buka_maps.dart';
import '../jaringan.dart';
import '../lantai.dart';
import '../toko/kunjungan_sesi.dart';
import '../toko/outlet_toko_layar.dart';
import '../toko/scan_toko_layar.dart';
import '../toko/toko_layar.dart';
import '../toko/toko_repo.dart';
import '../uang.dart';
import '../umpan.dart';
import 'kartu_toko.dart';
import 'pengirim_drawer.dart';
import 'peta_toko_layar.dart';
import 'setoran_sheet.dart';

class BerandaPengirimLayar extends StatefulWidget {
  const BerandaPengirimLayar({
    super.key,
    required this.nama,
    required this.rute,
    this.info,
  });

  final String nama;
  final String rute;
  final String? info;

  @override
  State<BerandaPengirimLayar> createState() => _BerandaPengirimLayarState();
}

class _BerandaPengirimLayarState extends State<BerandaPengirimLayar> {
  final _absensi = AbsensiRepo(Supabase.instance.client);
  final _repo = TokoRepo(Supabase.instance.client);
  final _cariCtrl = TextEditingController();
  StatusAbsensi _status = StatusAbsensi.kosong;
  bool _muat = true;
  bool _keluarOutlet = false;
  List<KartuToko> _toko = [];
  List<String> _ruteSales = const [];
  String _rutePengirim = '';
  String _filterKartu = 'semua';
  DateTime? _pilihTanggalBuku;
  late DateTime _tanggal;
  bool _hidup = true;

  String get _judul {
    if (_hidup) return 'Pengiriman hari ini';
    return 'Pengiriman ${Uang.tanggal(_tanggal)}';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _tanggal = DateTime(now.year, now.month, now.day);
    _rutePengirim = widget.rute;
    final info = widget.info;
    if (info != null && info.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        umpan(context, info);
      });
    }
    _muatData();
    KunjunganSesi.kunci.addListener(_saatKunciBerubah);
  }

  @override
  void dispose() {
    KunjunganSesi.kunci.removeListener(_saatKunciBerubah);
    _cariCtrl.dispose();
    super.dispose();
  }

  void _saatKunciBerubah() {
    if (!mounted) return;
    if (KunjunganSesi.kunci.value != null) {
      _keluarOutlet = true;
      return;
    }
    if (!_keluarOutlet) return;
    _keluarOutlet = false;
    _muatData();
  }

  Color _warnaStatus(String label) {
    switch (label) {
      case 'Terkirim':
      case 'Sedang dikirim':
        return Colors.green;
      case 'Batal':
        return Colors.red;
      default:
        return Colors.amber.shade800;
    }
  }

  bool _cocokFilter(KartuToko toko, [String? kunci]) {
    switch (kunci ?? _filterKartu) {
      case 'dikirim':
        return toko.labelStatus == 'Sedang dikirim';
      case 'terkirim':
        return toko.labelStatus == 'Terkirim';
      case 'pending':
        return toko.adaPending;
      case 'batal':
        return toko.omsetBatal > 0 || toko.labelStatus == 'Batal';
      default:
        return true;
    }
  }

  bool _cocokCari(KartuToko toko) {
    final q = _cariCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return toko.nama.toLowerCase().contains(q) ||
        toko.idPelanggan.toLowerCase().contains(q) ||
        toko.ruteSales.toLowerCase().contains(q);
  }

  List<KartuToko> get _tokoTampil =>
      _toko.where(_cocokFilter).where(_cocokCari).toList(growable: false);

  int _jumlahFilter(String kunci) => kunci == 'semua'
      ? _toko.length
      : _toko.where((t) => _cocokFilter(t, kunci)).length;

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 14)),
      helpText: 'Pilih tanggal buku',
      cancelText: 'Batal',
      confirmText: 'Tampilkan',
    );
    if (picked == null) return;
    final hari = DateTime(picked.year, picked.month, picked.day);
    setState(() => _pilihTanggalBuku = hari);
    await _muatData();
  }

  Future<void> _muatData({bool diam = false}) async {
    if (!diam) setState(() => _muat = true);
    try {
      final status = await _absensi.status();
      final buku = await _repo.bukuHari(_pilihTanggalBuku);
      final tgl = buku?.tanggal ??
          _pilihTanggalBuku ??
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          );
      final list = buku == null ? <KartuToko>[] : await _repo.kartu(tgl);
      List<String> sales = const [];
      try {
        sales = await _repo.ruteSales();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _status = status;
        _tanggal = tgl;
        _hidup = buku?.hidup ?? false;
        _toko = list;
        _ruteSales = sales;
        _rutePengirim = widget.rute.isNotEmpty ? widget.rute : _rutePengirim;
        _muat = false;
      });
      await _pulihkanKunci();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _toko = [];
        _muat = false;
      });
      umpan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Sambungkan internet, lalu coba lagi.'
            : pesanGagal(e, 'Daftar toko belum bisa dimuat.'),
      );
    }
  }

  Future<void> _pulihkanKunci() async {
    if (KunjunganSesi.kunci.value != null) return;
    final aktif = await SesiHp.kunjunganAktif();
    if (aktif == null || !mounted) return;
    KartuToko? toko;
    for (final t in _toko) {
      if (t.idPelanggan == aktif.id) {
        toko = t;
        break;
      }
    }
    if (toko == null) return;
    if (toko.scanKeluar) {
      KunjunganSesi.kunciToko(toko, _tanggal);
      return;
    }
    if (!_hidup && (aktif.selesaiMinggu || toko.sudahDikunjungi)) {
      KunjunganSesi.kunciToko(toko, _tanggal, lihatSaja: true);
      return;
    }
    if (_hidup && toko.sudahDikunjungi) {
      KunjunganSesi.kunciToko(toko, _tanggal);
      return;
    }
    await KunjunganSesi.keluarKeDaftar();
  }

  Future<void> _bukaScanAbsensi() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanAbsensiLayar(keluar: _status.masuk),
      ),
    );
    if (!mounted) return;
    if (ok == true || ok == null) await _muatData(diam: true);
  }

  Future<void> _bukaMaps(KartuToko toko) {
    return bukaMapsToko(
      context: context,
      nama: toko.nama,
      latitude: toko.latitude,
      longitude: toko.longitude,
    );
  }

  Future<void> _bukaToko(KartuToko toko) async {
    if (toko.scanKeluar && _hidup) {
      await KunjunganSesi.setSesi(toko: toko, tanggal: _tanggal);
      return;
    }
    if (!_hidup) {
      await KunjunganSesi.setSesi(
        toko: toko,
        tanggal: _tanggal,
        lihatSaja: true,
      );
      return;
    }
    if (toko.sudahDikunjungi) {
      await KunjunganSesi.setSesi(toko: toko, tanggal: _tanggal);
      return;
    }
    await Navigator.of(context).push(
      ruteHalaman(TokoLayar(toko: toko, tanggal: _tanggal)),
    );
    if (mounted) await _muatData(diam: true);
  }

  Future<void> _bukaScan(KartuToko toko) async {
    if (!_hidup || toko.sudahDikunjungi) {
      await _bukaToko(toko);
      return;
    }
    if (!await pastikanBolehKerja(context)) return;
    if (!mounted) return;
    final checkIn = !toko.scanKeluar;
    final ok = await Navigator.of(context).push<bool>(
      ruteHalaman(ScanTokoLayar(toko: toko, keluar: toko.scanKeluar)),
    );
    if (ok != true || !mounted) return;
    await _muatData(diam: true);
    if (!mounted || !checkIn) return;
    final baru = _toko.where((t) => t.idPelanggan == toko.idPelanggan);
    await KunjunganSesi.setSesi(
      toko: baru.isNotEmpty ? baru.first : toko,
      tanggal: _tanggal,
    );
  }

  Widget _chipStatus(bool masuk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: masuk ? const Color(0xFF2E7D32) : Tema.kuning,
        borderRadius: Tema.sudut,
      ),
      child: Text(
        masuk ? 'SUDAH ABSEN' : 'BELUM ABSEN',
        style: TextStyle(
          color: masuk ? Colors.white : Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _chipTeks(String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: Tema.sudut,
        border: Border.all(color: warna, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: warna,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _tombolKartu({
    required String tooltip,
    required IconData ikon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(ikon, color: Tema.seed, size: 22),
    );
  }

  Widget _nominal(KartuToko toko) {
    const gaya = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Tema.seed,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Order : ${Uang.rp(toko.omsetOrder)}', style: gaya),
        const SizedBox(height: 2),
        Text('Kiriman : ${Uang.rp(toko.omsetPacked)}', style: gaya),
        const SizedBox(height: 2),
        Text('Actual : ${Uang.rp(toko.omsetActual)}', style: gaya),
      ],
    );
  }

  Widget _statusKunjungan(KartuToko toko) {
    final sudah = toko.waktuKeluar != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        sudah ? 'Sudah dikunjungi' : 'Belum dikunjungi',
        style: TextStyle(
          color: sudah ? Tema.seed : Tema.redup,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _bilahFilter() {
    const opsi = <(String, String)>[
      ('semua', 'Semua'),
      ('dikirim', 'Sedang dikirim'),
      ('terkirim', 'Terkirim'),
      ('pending', 'Pending'),
      ('batal', 'Batal'),
    ];
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          children: [
            for (final o in opsi)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chipFilter(o.$1, o.$2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipFilter(String kunci, String label) {
    final pilih = _filterKartu == kunci;
    final warna = switch (kunci) {
      'pending' => Colors.orange.shade800,
      'batal' => Colors.red,
      'semua' => Tema.seed,
      _ => Colors.green,
    };
    final n = _jumlahFilter(kunci);
    return Material(
      color: pilih ? warna.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: Tema.sudut,
      child: InkWell(
        onTap: () => setState(() => _filterKartu = kunci),
        borderRadius: Tema.sudut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: Tema.sudut,
            border: Border.all(color: warna, width: 1.2),
          ),
          child: Text(
            '$label ($n)',
            style: TextStyle(
              color: warna,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  void _bukaPeta() {
    Navigator.of(context).push(
      ruteHalaman(
        PetaTokoLayar(judul: _judul, toko: _tokoTampil),
      ),
    );
  }

  Future<void> _tampilkanRingkasanHari() async {
    final ringkas = await _repo.ringkasHari(_tanggal, kartu: _toko);
    var sudahSetor = false;
    try {
      sudahSetor = (await _repo.setoranLihat()).sudahAda;
    } catch (_) {}
    if (!mounted) return;
    await tampilkanSheetSetoran(
      context: context,
      tanggal: _tanggal,
      ringkas: ringkas,
      rutePengirim: _rutePengirim,
      belumKunci: _toko.fold(0, (n, t) => n + t.wajibKunci),
      sudahSetor: sudahSetor,
      bolehSetor: _hidup,
    );
  }

  Widget _bilahCari() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cariCtrl,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Cari nama, kode, atau rute...',
                  prefixIcon: const Icon(Icons.search_outlined, size: 22),
                  suffixIcon: _cariCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus',
                          icon: const Icon(Icons.clear_outlined, size: 20),
                          onPressed: () {
                            _cariCtrl.clear();
                            setState(() {});
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Peta toko',
              onPressed: _muat ? null : _bukaPeta,
              icon: const Icon(Icons.map_outlined),
            ),
            IconButton(
              tooltip: 'Ringkasan pengiriman',
              onPressed: _muat ? null : _tampilkanRingkasanHari,
              icon: const Icon(Icons.summarize_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kartuToko(KartuToko toko) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _bukaToko(toko),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toko.nama.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      toko.idPelanggan.isEmpty
                          ? 'Kode: -'
                          : 'Kode: ${toko.idPelanggan}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (toko.ruteSales.isNotEmpty)
                      Text(
                        'Rute: ${toko.ruteSales}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 6),
                    _chipTeks('${toko.jumlahNota} nota', Tema.seed),
                    _statusKunjungan(toko),
                    if (!_hidup || (!toko.adaDikirim && !toko.adaPending))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Hanya lihat',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tombolKartu(
                      tooltip: 'Buka Maps',
                      ikon: Icons.location_on_outlined,
                      onPressed: () => _bukaMaps(toko),
                    ),
                    _tombolKartu(
                      tooltip: !_hidup || toko.sudahDikunjungi
                          ? 'Buka toko'
                          : toko.scanKeluar
                              ? 'Scan keluar toko'
                              : 'Scan masuk toko',
                      ikon: !_hidup || toko.sudahDikunjungi
                          ? Icons.storefront_outlined
                          : Icons.qr_code_scanner_outlined,
                      onPressed: () => !_hidup || toko.sudahDikunjungi
                          ? _bukaToko(toko)
                          : _bukaScan(toko),
                    ),
                  ],
                ),
                _chipTeks(toko.labelStatus, _warnaStatus(toko.labelStatus)),
                if (toko.adaPending) ...[
                  const SizedBox(height: 6),
                  _chipTeks('Pending', Colors.orange.shade800),
                ],
                if (toko.omsetBatal > 0) ...[
                  const SizedBox(height: 6),
                  _chipTeks('Batal ${Uang.rp(toko.omsetBatal)}', Colors.red),
                ],
                if (toko.omsetRetur > 0) ...[
                  const SizedBox(height: 6),
                  _chipTeks('Retur ${Uang.rp(toko.omsetRetur)}', Colors.red),
                ],
                const SizedBox(height: 6),
                _nominal(toko),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KunjunganSesi.kunci,
      builder: (context, _) {
        final kunci = KunjunganSesi.kunci.value;
        if (kunci != null) {
          return OutletTokoLayar(
            key: ValueKey(
              '${kunci.toko.idPelanggan}-${kunci.lihatSaja}',
            ),
            toko: kunci.toko,
            tanggal: kunci.tanggal,
            lihatSaja: kunci.lihatSaja,
          );
        }
        return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu_outlined),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: Text(_judul),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _chipStatus(_status.masuk)),
            ),
          ],
        ),
        drawer: PengirimDrawer(
          nama: widget.nama,
          rutePengirim: _rutePengirim,
          ruteSales: _ruteSales,
          teksTanggal: _hidup
              ? 'Buku berjalan · ${Uang.tanggal(_tanggal)}'
              : Uang.tanggal(_tanggal),
          sedangMuat: _muat,
          sudahMasuk: _status.masuk,
          onPilihTanggal: _pilihTanggal,
          onScanAbsensi: _bukaScanAbsensi,
        ),
        body: _muat
            ? const Center(child: CircularProgressIndicator())
            : _toko.isEmpty
                ? RefreshIndicator(
                    onRefresh: () => _muatData(diam: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Belum ada pengiriman di tanggal ini.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _bilahFilter(),
                      _bilahCari(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () => _muatData(diam: true),
                          child: _tokoTampil.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 120),
                                    Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'Tidak ada kartu untuk filter atau pencarian ini.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                                  itemCount: _tokoTampil.length,
                                  itemBuilder: (context, i) =>
                                      _kartuToko(_tokoTampil[i]),
                                ),
                        ),
                      ),
                    ],
                  ),
      ),
        );
      },
    );
  }
}
