import 'dart:async';

import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_drawer.dart';
import '../jaringan.dart';
import '../masukan/kartu_masukan.dart';
import '../masukan/masukan_repo.dart';
import '../opname/kartu_opname.dart';
import '../opname/opname_repo.dart';
import '../pesan.dart';
import '../masukan/masukan_csv.dart';
import '../setoran/absensi_repo.dart';
import '../setoran/cek_rinci_setoran.dart';
import '../setoran/kartu_absensi.dart';
import '../setoran/kartu_mutasi.dart';
import '../setoran/kartu_setoran.dart';
import '../setoran/kasbon_cek_setoran.dart';
import '../setoran/mutasi_csv.dart';
import '../setoran/mutasi_repo.dart';
import '../setoran/setoran_repo.dart';
import '../setoran/tunai_admin_setoran.dart';
import '../uang.dart';

class BerandaAdminLayar extends StatefulWidget {
  const BerandaAdminLayar({
    super.key,
    required this.nama,
    this.info,
  });

  final String nama;
  final String? info;

  @override
  State<BerandaAdminLayar> createState() => _BerandaAdminLayarState();
}

class _BerandaAdminLayarState extends State<BerandaAdminLayar>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  late final OpnameRepo _repo = OpnameRepo(_sb);
  late final MasukanRepo _masukanRepo = MasukanRepo(_sb);
  late final SetoranRepo _setoranRepo = SetoranRepo(_sb);
  late final MutasiRepo _mutasiRepo = MutasiRepo(_sb);
  late final AbsensiRepo _absensiRepo = AbsensiRepo(_sb);
  RealtimeChannel? _saluran;
  Timer? _tundaSegar;
  Timer? _jagaKartu;
  RingkasOpname _data = RingkasOpname.kosong;
  RingkasMasuk _masuk = RingkasMasuk.kosong;
  RingkasSetoran _setoran = RingkasSetoran.kosong;
  SiklusBuku _siklus = SiklusBuku.kosong;
  List<OrangAbsensi> _pengirim = const [];
  List<OrangAbsensi> _gudang = const [];
  int? _idBukuLihat;
  bool _muat = true;
  bool _proses = false;
  bool _sedangMuat = false;
  bool _muatUlang = false;
  bool _halamanAktif = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final info = widget.info;
    if (info != null && info.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tampilPesan(context, info);
      });
    }
    _dengarOpname();
    _jagaKartu = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_halamanAktif) return;
      unawaited(_muatData(diam: true));
    });
    unawaited(_muatData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tundaSegar?.cancel();
    _jagaKartu?.cancel();
    final saluran = _saluran;
    if (saluran != null) {
      unawaited(_sb.removeChannel(saluran));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _halamanAktif = state == AppLifecycleState.resumed;
    if (_halamanAktif) unawaited(_muatData(diam: true));
  }

  void _dengarOpname() {
    final token = _sb.auth.currentSession?.accessToken;
    if (token != null) _sb.realtime.setAuth(token);
    _saluran = _sb
        .channel('admin-opname-kartu')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stok_opname',
          callback: (_) => _jadwalSegar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'setoran_buku',
          callback: (_) => _jadwalSegar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'setoran_pengirim',
          callback: (_) => _jadwalSegar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'retur_toko',
          callback: (_) => _jadwalSegar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transaksi',
          callback: (_) => _jadwalSegar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mutasi_bank',
          callback: (_) => _jadwalSegar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'absensi',
          callback: (_) => _jadwalSegar(),
        )
        .subscribe();
  }

  void _jadwalSegar() {
    _tundaSegar?.cancel();
    _tundaSegar = Timer(const Duration(milliseconds: 400), () {
      unawaited(_muatData(diam: true));
    });
  }

  Future<void> _muatData({bool diam = false}) async {
    if (_sedangMuat) {
      _muatUlang = true;
      return;
    }
    _sedangMuat = true;
    if (!diam && mounted) setState(() => _muat = true);
    try {
      final data = await _repo.ringkas(idBuku: _idBukuLihat);
      RingkasMasuk masuk = _masuk;
      RingkasSetoran setoran = _setoran;
      var siklus = _siklus;
      var pengirim = _pengirim;
      var gudang = _gudang;
      try {
        masuk = await _masukanRepo.ringkas(idBuku: _idBukuLihat);
      } catch (e) {
        if (!diam && mounted) {
          tampilPesan(
            context,
            Jaringan.mati(e)
                ? 'Tidak ada internet. Kartu barang masuk belum bisa dimuat.'
                : _pesanGagal(e, 'Kartu barang masuk belum bisa dibaca.'),
          );
        }
      }
      try {
        setoran = await _setoranRepo.ringkas(idBuku: _idBukuLihat);
        CekRinciSetoran.instance.gabungJson(setoran.cek);
        TunaiAdminSetoran.instance.gabungJson(setoran.tunaiAdmin);
        KasbonCekSetoran.instance.gabungJson(setoran.kasbon);
        try {
          siklus = await _setoranRepo.siklus();
        } catch (_) {
          if (!diam) siklus = SiklusBuku.kosong;
        }
      } catch (e) {
        if (!diam && mounted) {
          tampilPesan(
            context,
            Jaringan.mati(e)
                ? 'Tidak ada internet. Kartu setoran belum bisa dimuat.'
                : _pesanGagal(e, 'Kartu setoran belum bisa dibaca.'),
          );
        }
      }
      try {
        MutasiSetoran.instance.pasang(
          await _mutasiRepo.lihat(idBuku: _idBukuLihat),
        );
      } catch (e) {
        if (!diam) MutasiSetoran.instance.pasang(const []);
        if (!diam && mounted) {
          tampilPesan(
            context,
            Jaringan.mati(e)
                ? 'Tidak ada internet. Kartu mutasi belum bisa dimuat.'
                : _pesanGagal(e, 'Kartu mutasi belum bisa dibaca.'),
          );
        }
      }
      try {
        final absen = await _absensiRepo.lihat(idBuku: _idBukuLihat);
        pengirim = absen.pengirim;
        gudang = absen.gudang;
      } catch (e) {
        if (!diam) {
          pengirim = const [];
          gudang = const [];
        }
        if (!diam && mounted) {
          tampilPesan(
            context,
            Jaringan.mati(e)
                ? 'Tidak ada internet. Kartu absensi belum bisa dimuat.'
                : _pesanGagal(e, 'Kartu absensi belum bisa dibaca.'),
          );
        }
      }
      if (!mounted) return;
      final berubah = data != _data ||
          masuk != _masuk ||
          setoran != _setoran ||
          siklus.pesan != _siklus.pesan ||
          !_samaOrang(pengirim, _pengirim) ||
          !_samaOrang(gudang, _gudang) ||
          _muat;
      if (berubah) {
        setState(() {
          _data = data;
          _masuk = masuk;
          _setoran = setoran;
          _siklus = siklus;
          _pengirim = pengirim;
          _gudang = gudang;
          _muat = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (diam) {
        if (_muat) setState(() => _muat = false);
        return;
      }
      setState(() {
        _data = RingkasOpname.kosong;
        _muat = false;
      });
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Kartu opname belum bisa dimuat.'
            : _pesanGagal(e, 'Kartu opname belum bisa dibaca.'),
      );
    } finally {
      _sedangMuat = false;
      if (_muatUlang && mounted) {
        _muatUlang = false;
        unawaited(_muatData(diam: true));
      }
    }
  }

  bool _samaOrang(List<OrangAbsensi> a, List<OrangAbsensi> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _pesanGagal(Object e, String cadangan) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message.trim();
    }
    return cadangan;
  }

  Future<void> _konfirmasi() async {
    final id = _data.idSetoranBuku;
    if (id == null || _proses) return;
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Konfirmasi stok fisik?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: IsiDialog(
          child: const Text(
            'Stok master SKU yang sudah dihitung fisik akan mengikuti fisik gudang. Buku tidak ditutup.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, konfirmasi'),
          ),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    setState(() => _proses = true);
    try {
      await _repo.konfirmasi(id);
      if (!mounted) return;
      tampilPesan(context, 'Stok master sudah mengikuti fisik gudang.');
      await _muatData();
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Konfirmasi belum tersimpan.'
            : _pesanGagal(e, 'Konfirmasi stok belum tersimpan.'),
      );
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  Future<void> _tutupBuku() async {
    if (_proses || !_bisaTutup) return;
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Tutup buku setoran?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: IsiDialog(
          child: const Text(
            'Buku ditutup. Fisik terisi memakai fisik; yang belum memakai sisa hitung.\n'
            'Selisih kurang kasbon atau potong margin; lebih masuk tambahan margin.\n'
            'Scan dan packing berikutnya masuk buku baru.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, tutup buku'),
          ),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    setState(() => _proses = true);
    try {
      await _repo.tutupBuku();
      if (!mounted) return;
      tampilPesan(context, 'Buku setoran ditutup.');
      await _muatData();
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Buku belum ditutup.'
            : _pesanGagal(e, 'Buku belum ditutup.'),
      );
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  DateTime _hari(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _hariSama(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pilihBuku() async {
    List<BukuSetoranPilih> daftar;
    try {
      daftar = await _setoranRepo.daftarBuku();
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Daftar buku belum bisa dibuka.'
            : _pesanGagal(e, 'Daftar buku belum bisa dibaca.'),
      );
      return;
    }
    if (!mounted) return;
    if (daftar.isEmpty) {
      tampilPesan(context, 'Belum ada buku setoran.');
      return;
    }
    final tanggalAda = {
      for (final b in daftar) _hari(b.tanggal),
    };
    final awal = tanggalAda.reduce((a, b) => a.isBefore(b) ? a : b);
    final akhir = tanggalAda.reduce((a, b) => a.isAfter(b) ? a : b);
    final sekarang = _setoran.tanggal ?? DateTime.now();
    var initial = _hari(sekarang);
    if (!tanggalAda.any((t) => _hariSama(t, initial))) {
      initial = akhir;
    }
    final pilih = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: awal,
      lastDate: akhir,
      helpText: 'Pilih tanggal buku',
      selectableDayPredicate: (d) =>
          tanggalAda.any((t) => _hariSama(t, d)),
    );
    if (pilih == null || !mounted) return;
    final kandidat = [
      for (final b in daftar)
        if (_hariSama(b.tanggal, pilih)) b,
    ];
    if (kandidat.isEmpty) {
      tampilPesan(context, 'Tidak ada buku di tanggal itu.');
      return;
    }
    kandidat.sort((a, b) => b.id.compareTo(a.id));
    setState(() => _idBukuLihat = kandidat.first.id);
    await _muatData();
  }

  Future<void> _simpanKartu() async {
    final id = _setoran.idSetoranBuku;
    if (id == null || _proses) return;
    setState(() => _proses = true);
    try {
      await _setoranRepo.simpanKartu(
        idBuku: id,
        cek: CekRinciSetoran.instance.keJson(),
        tunai: TunaiAdminSetoran.instance.keJson(),
        kasbon: KasbonCekSetoran.instance.keJson(),
      );
      if (!mounted) return;
      tampilPesan(context, 'Kartu setoran disimpan.');
      await _muatData(diam: true);
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Kartu belum tersimpan.'
            : _pesanGagal(e, 'Kartu belum tersimpan.'),
      );
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  bool get _opnameSesuai =>
      _data.adaBuku && _data.skuFisik > 0 && _data.skuMinusBelum == 0;

  bool get _bisaTutup =>
      _setoran.adaBuku &&
      !_setoran.ditutup &&
      !_data.ditutup &&
      !_muat &&
      !_proses &&
      _setoran.total.cek == 0 &&
      chipJumlahTanpaOranye(_setoran) &&
      _opnameSesuai &&
      !_absensiMasihOranye;

  bool get _absensiMasihOranye =>
      _pengirim.any((o) => o.oranye) || _gudang.any((o) => o.oranye);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        CekRinciSetoran.instance,
        TunaiAdminSetoran.instance,
        KasbonCekSetoran.instance,
        MutasiSetoran.instance,
      ]),
      builder: (context, _) {
        final bisaTutup = _bisaTutup;
        final tgl = _setoran.tanggal ?? _data.tanggal;
        return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              tooltip: 'Buku lama',
              onPressed: _muat || _proses ? null : _pilihBuku,
              icon: const Icon(Icons.calendar_month_outlined),
            ),
            Flexible(
              child: Text(
                tgl == null
                    ? (_setoran.adaBuku || _data.adaBuku
                        ? 'Setoran'
                        : 'Setoran · belum ada buku')
                    : Uang.setoranJudul(tgl),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: FilledButton(
              onPressed: _muat || _proses || !_setoran.adaBuku
                  ? null
                  : _simpanKartu,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Simpan'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: OutlinedButton(
              onPressed: bisaTutup ? _tutupBuku : null,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Tutup buku'),
            ),
          ),
          IconButton(
            tooltip: 'Unduh',
            onPressed: () => tampilPesan(context, 'Belum tersedia.'),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Segarkan',
            onPressed: _muat || _proses ? null : () => _muatData(),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: const AdminDrawer(halaman: HalamanAdmin.setoran),
      body: LayoutBuilder(
        builder: (context, layar) {
          const padAtas = 6.0;
          const padBawah = 6.0;
          const celah = 6.0;
          const tinggiAbsen = 40.0;
          const tinggiBanner = 40.0;
          final adaBanner = _siklus.pesan.isNotEmpty;
          final adaProgress = _muat || _proses;
          final tinggiKartuArea = (layar.maxHeight -
                  padAtas -
                  padBawah -
                  tinggiAbsen -
                  celah -
                  (adaBanner ? tinggiBanner : 0) -
                  (adaProgress ? 4.0 : 0))
              .clamp(240.0, 4000.0);
          const cadangan = 2 * (4 + 8 + 32);
          var tinggiBaris =
              ((tinggiKartuArea - celah - cadangan) / 5).floorToDouble();
          if (tinggiBaris > 200) tinggiBaris = 200;
          if (tinggiBaris < 72) tinggiBaris = 72;
          final nRute = _setoran.rute.isEmpty ? 4 : _setoran.rute.length;
          final tinggiRute = tinggiKartuSetoran(nRute, tinggiBaris);
          final tinggiJumlah = tinggiKartuSetoran(1, tinggiBaris);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (adaProgress) const LinearProgressIndicator(),
              if (adaBanner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, padAtas, 16, 0),
                  child: _bannerSiklus(),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _muatData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      adaBanner ? 0 : padAtas,
                      16,
                      celah,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _barisKiriKanan(
                          lebar: layar.maxWidth - 32,
                          kiri: KartuSetoran(
                            data: _setoran,
                            sibuk: _muat || _proses,
                            tinggiBaris: tinggiBaris,
                          ),
                          kanan: _kananAtas(tinggiRute),
                          tinggiKanan: tinggiRute,
                        ),
                        const SizedBox(height: celah),
                        _barisKiriKanan(
                          lebar: layar.maxWidth - 32,
                          kiri: KartuSetoran(
                            data: _setoran,
                            sibuk: _muat || _proses,
                            tinggiBaris: tinggiBaris,
                            totalSaja: true,
                          ),
                          kanan: _opname(),
                          tinggiKanan: tinggiJumlah,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, padBawah),
                child: SizedBox(
                  height: tinggiAbsen,
                  child: KartuAbsensi(
                    pengirim: _pengirim,
                    gudang: _gudang,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
      },
    );
  }

  Widget _bannerSiklus() {
    final siap = _siklus.siapTutup;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: siap ? const Color(0xFFC8E6C9) : Tema.kuning,
        borderRadius: Tema.sudut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            _siklus.pesan,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _barisKiriKanan({
    required double lebar,
    required Widget kiri,
    required Widget kanan,
    required double tinggiKanan,
  }) {
    const gap = 12.0;
    final butuh = lebarKartuSetoran + gap + lebarKananMin;
    final lebarKanan =
        lebar >= butuh ? lebar - lebarKartuSetoran - gap : lebarKananMin;
    final baris = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: lebarKartuSetoran, child: kiri),
        const SizedBox(width: gap),
        SizedBox(
          width: lebarKanan,
          height: tinggiKanan,
          child: kanan,
        ),
      ],
    );
    if (lebar >= butuh) return baris;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: baris,
    );
  }

  Widget _kananAtas(double tinggiKolom) {
    const celah = 6.0;
    const minMutasi = 80.0;
    var hMasuk = KartuMasukan.tinggiUntuk(_masuk.supplier.length);
    final maks = (tinggiKolom - celah - minMutasi).clamp(72.0, tinggiKolom);
    if (hMasuk > maks) hMasuk = maks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: KartuMutasi(
            sibuk: _muat || _proses,
            ditutup: _setoran.ditutup,
            judulHari: Uang.setoranJudul(_setoran.tanggal),
            onUnggah: _unggahMutasi,
            onHapus: _hapusMutasi,
          ),
        ),
        const SizedBox(height: celah),
        SizedBox(
          height: hMasuk,
          width: double.infinity,
          child: KartuMasukan(
            data: _masuk,
            sibuk: _muat || _proses,
            ditutup: _setoran.ditutup,
            onMuat: _muatData,
          ),
        ),
      ],
    );
  }

  String? _isoTanggal(DateTime? d) {
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _unggahMutasi() async {
    if (_proses) return;
    final teks = await pilihBerkasCsv();
    if (teks == null || !mounted) return;
    final hasil = MutasiCsv.parse(teks);
    if (hasil.error != null) {
      tampilPesan(context, hasil.error!);
      return;
    }
    final iso = _isoTanggal(_setoran.tanggal);
    setState(() => _proses = true);
    try {
      final n = await _mutasiRepo.unggah(
        namaBerkas: 'mutasi.csv',
        baris: [
          for (final b in hasil.baris)
            {
              ...b.toRpc(),
              'rute_pengirim': MutasiCsv.ruteDariBerita(b.berita, iso) ?? '',
            },
        ],
      );
      MutasiSetoran.instance.pasang(await _mutasiRepo.lihat(idBuku: _idBukuLihat));
      if (!mounted) return;
      tampilPesan(
        context,
        n <= 0 ? 'Tidak ada baris mutasi yang tersimpan.' : '$n baris mutasi diunggah.',
      );
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Mutasi belum tersimpan.'
            : _pesanGagal(e, 'Mutasi belum tersimpan.'),
      );
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  Future<void> _hapusMutasi() async {
    if (_proses) return;
    setState(() => _proses = true);
    try {
      await _mutasiRepo.hapus();
      MutasiSetoran.instance.pasang(const []);
      if (!mounted) return;
      tampilPesan(context, 'Mutasi buku ini dihapus.');
    } catch (e) {
      if (!mounted) return;
      tampilPesan(
        context,
        Jaringan.mati(e)
            ? 'Tidak ada internet. Mutasi belum dihapus.'
            : _pesanGagal(e, 'Mutasi belum dihapus.'),
      );
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  Widget _opname() {
    return SizedBox.expand(
      child: KartuOpname(
        data: _data,
        sibuk: _muat || _proses,
        onMuat: _muatData,
        onKonfirmasi: _konfirmasi,
      ),
    );
  }
}
