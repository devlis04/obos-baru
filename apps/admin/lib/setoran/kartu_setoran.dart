import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../pesan.dart';
import '../uang.dart';
import 'cek_rinci_setoran.dart';
import 'daftar_rinci_dialog.dart';
import 'dialog_kasbon.dart';
import 'dialog_tunai_admin.dart';
import 'kasbon_cek_setoran.dart';
import 'mutasi_repo.dart';
import 'tunai_admin_setoran.dart';
import 'setoran_repo.dart';

const lebarKartuSetoran = 960.0;
const lebarKananMin = 280.0;
const _lebarRute = 108.0;
const _lebarNilai = 248.0;
const _lebarLabel = 118.0;
const _tinggiBarisNilai = 26.0;
const _tinggiJudul = 32.0;
const _padAtas = 4.0;
const _padBawah = 8.0;
const _teksIsi = 14.0;
const _garisKolom = Color(0xFF8FB4D9);

double tinggiKartuSetoran(int nBaris, double tinggiBaris) =>
    _padAtas + _tinggiJudul + nBaris * tinggiBaris + _padBawah;

/// Chip yang nyala di kartu Jumlah tidak ada yang oranye (hijau / biru).
bool chipJumlahTanpaOranye(RingkasSetoran data) {
  final rute = data.rute;
  bool semua({
    required bool Function(BarisSetoranRute r) nyala,
    required bool Function(BarisSetoranRute r) hijau,
  }) {
    for (final r in rute) {
      if (!nyala(r)) continue;
      if (!hijau(r)) return false;
    }
    return true;
  }

  bool rinci(String jenis, int Function(BarisSetoranRute r) nilai) {
    return semua(
      nyala: (r) => nilai(r) > 0,
      hijau: (r) => CekRinciSetoran.instance.hijau(
        tanggal: data.tanggal,
        jenis: jenis,
        rute: r.rute,
      ),
    );
  }

  return rinci('kiriman', (r) => r.kiriman) &&
      rinci('batal', (r) => r.batal) &&
      rinci('pending', (r) => r.pending) &&
      rinci('retur', (r) => r.retur) &&
      semua(
        nyala: (r) => r.transfer > 0,
        hijau: (r) {
          final n = MutasiSetoran.instance.nilai(rute: r.rute);
          return n > 0 && n == r.transfer;
        },
      ) &&
      semua(
        nyala: (r) => r.tunai > 0,
        hijau: (r) {
          final n = TunaiAdminSetoran.instance.nilai(
            tanggal: data.tanggal,
            rute: r.rute,
          );
          return n > 0 && n == r.tunai;
        },
      ) &&
      semua(
        nyala: (r) => r.kasbon > 0,
        hijau: (r) => KasbonCekSetoran.instance.hijau(
          tanggal: data.tanggal,
          rute: r.rute,
          semua: data.rute,
        ),
      );
}

class KartuSetoran extends StatelessWidget {
  const KartuSetoran({
    super.key,
    required this.data,
    required this.sibuk,
    required this.tinggiBaris,
    this.totalSaja = false,
  });

  final RingkasSetoran data;
  final bool sibuk;
  final double tinggiBaris;
  final bool totalSaja;

  List<BarisSetoranRute> get _baris =>
      totalSaja ? [data.total] : data.rute;

  @override
  Widget build(BuildContext context) {
    final n = totalSaja ? 1 : (_baris.isEmpty ? 1 : _baris.length);
    return SizedBox(
      height: tinggiKartuSetoran(n, tinggiBaris),
      width: lebarKartuSetoran,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, _padAtas, 8, _padBawah),
          child: !data.adaBuku && !totalSaja
              ? const Center(
                  child: Text(
                    'Scan masuk gudang membuka buku.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : ListenableBuilder(
                  listenable: Listenable.merge([
                    CekRinciSetoran.instance,
                    TunaiAdminSetoran.instance,
                    KasbonCekSetoran.instance,
                    MutasiSetoran.instance,
                  ]),
                  builder: (context, _) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: _tinggiJudul,
                    dataRowMinHeight: tinggiBaris,
                    dataRowMaxHeight: tinggiBaris,
                    dividerThickness: 0,
                    columnSpacing: 16,
                    horizontalMargin: 10,
                    border: const TableBorder(
                      verticalInside: BorderSide(color: _garisKolom, width: 1),
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: _teksIsi,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    columns: [
                      _judul(_lebarRute, 'Rute'),
                      _judul(_lebarNilai, 'Nota'),
                      _judul(_lebarNilai, 'Setor'),
                      _judul(_lebarNilai, 'Hitung'),
                    ],
                    rows: [
                      for (final b in _baris) _barisRute(context, b),
                    ],
                  ),
                ),
                ),
        ),
      ),
    );
  }

  DataColumn _judul(double lebar, String teks) {
    return DataColumn(
      headingRowAlignment: MainAxisAlignment.center,
      label: SizedBox(
        width: lebar,
        child: Text(teks, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _kotak(
    double lebar,
    Widget child, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return SizedBox(
      width: lebar,
      child: OverflowBox(
        alignment: alignment,
        maxWidth: lebar,
        maxHeight: double.infinity,
        child: child,
      ),
    );
  }

  bool _hijauSemuaRute({
    required bool Function(BarisSetoranRute r) nyala,
    required bool Function(BarisSetoranRute r) hijau,
  }) {
    var ada = false;
    for (final r in data.rute) {
      if (!nyala(r)) continue;
      ada = true;
      if (!hijau(r)) return false;
    }
    return ada;
  }

  bool _hijauRinciJumlah(String jenis) {
    return _hijauSemuaRute(
      nyala: (r) {
        switch (jenis) {
          case 'kiriman':
            return r.kiriman > 0;
          case 'batal':
            return r.batal > 0;
          case 'pending':
            return r.pending > 0;
          case 'retur':
            return r.retur > 0;
          default:
            return false;
        }
      },
      hijau: (r) => CekRinciSetoran.instance.hijau(
        tanggal: data.tanggal,
        jenis: jenis,
        rute: r.rute,
      ),
    );
  }

  DataRow _barisRute(BuildContext context, BarisSetoranRute b) {
    final jumlah = b.rute == 'Jumlah';
    final ruteTap = jumlah ? null : b.rute;
    final ruteSemua = [for (final r in data.rute) r.rute];
    final tunaiAdmin = TunaiAdminSetoran.instance.nilai(
      tanggal: data.tanggal,
      rute: b.rute,
      semuaRute: ruteSemua,
    );
    final hijauTunaiAdmin = jumlah
        ? _hijauSemuaRute(
            nyala: (r) => r.tunai > 0,
            hijau: (r) {
              final n = TunaiAdminSetoran.instance.nilai(
                tanggal: data.tanggal,
                rute: r.rute,
              );
              return n > 0 && n == r.tunai;
            },
          )
        : tunaiAdmin > 0 && tunaiAdmin == b.tunai;
    final hijauKasbon = KasbonCekSetoran.instance.hijau(
      tanggal: data.tanggal,
      rute: b.rute,
      semua: data.rute,
    );
    final mutasi = MutasiSetoran.instance.nilai(
      rute: b.rute,
      semuaRute: ruteSemua,
    );
    final hijauMutasi = jumlah
        ? _hijauSemuaRute(
            nyala: (r) => r.transfer > 0,
            hijau: (r) {
              final n = MutasiSetoran.instance.nilai(rute: r.rute);
              return n > 0 && n == r.transfer;
            },
          )
        : mutasi > 0 && mutasi == b.transfer;
    return DataRow(
      cells: [
        DataCell(
          _kotak(_lebarRute, _selRute(b), alignment: Alignment.center),
        ),
        DataCell(
          _kotak(
            _lebarNilai,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _nilai(
                  context,
                  label: 'Kiriman',
                  n: b.kiriman,
                  jenis: 'kiriman',
                  rute: ruteTap,
                  chip: true,
                  hijauChip: jumlah && _hijauRinciJumlah('kiriman'),
                ),
                _nilai(
                  context,
                  label: 'Batal',
                  n: b.batal,
                  jenis: 'batal',
                  rute: ruteTap,
                  chip: true,
                  hijauChip: jumlah && _hijauRinciJumlah('batal'),
                ),
                _nilai(
                  context,
                  label: 'Pending',
                  n: b.pending,
                  jenis: 'pending',
                  rute: ruteTap,
                  chip: true,
                  hijauChip: jumlah && _hijauRinciJumlah('pending'),
                ),
                _nilai(
                  context,
                  label: 'Actual',
                  n: b.actual,
                  jenis: 'actual',
                  rute: ruteTap,
                  chip: true,
                ),
              ],
            ),
          ),
        ),
        DataCell(
          _kotak(
            _lebarNilai,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _nilai(context, label: 'Transfer', n: b.transfer),
                _nilai(
                  context,
                  label: 'Mutasi',
                  n: mutasi,
                  chip: true,
                  chipDari: b.transfer,
                  hijauChip: hijauMutasi,
                ),
                _nilai(context, label: 'Tunai', n: b.tunai),
                _nilai(
                  context,
                  label: 'Tunai admin',
                  n: tunaiAdmin,
                  chip: true,
                  chipDari: b.tunai,
                  hijauChip: hijauTunaiAdmin,
                  ketuk: sibuk
                      ? null
                      : () => bukaDialogTunaiAdmin(
                            context: context,
                            tanggal: data.tanggal,
                            rute: b.rute,
                            tunaiPengirim: b.tunai,
                            semuaRute: ruteSemua,
                          ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          _kotak(
            _lebarNilai,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _nilai(context, label: 'BOP', n: b.bop),
                _nilai(
                  context,
                  label: 'Kasbon',
                  n: b.kasbon,
                  chip: true,
                  chipDari: b.kasbon,
                  hijauChip: hijauKasbon,
                  ketuk: sibuk
                      ? null
                      : () => bukaDialogKasbon(
                            context: context,
                            tanggal: data.tanggal,
                            rute: b.rute,
                            semuaRute: data.rute,
                          ),
                ),
                _nilai(
                  context,
                  label: 'Retur',
                  n: b.retur,
                  jenis: 'retur',
                  rute: ruteTap,
                  chip: true,
                  hijauChip: jumlah && _hijauRinciJumlah('retur'),
                ),
                _nilai(context, label: 'Cek', n: b.cek),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _selRute(BarisSetoranRute b) {
    final jumlah = b.rute == 'Jumlah';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          b.rute,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: jumlah ? Colors.black : Tema.seed,
            decoration: jumlah ? TextDecoration.none : TextDecoration.underline,
            fontWeight: FontWeight.bold,
            fontSize: _teksIsi,
            height: 1.15,
          ),
        ),
        if (!jumlah && !b.sudahSetor)
          Text(
            'Belum setor',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.15,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (b.wajibKunci > 0)
          Text(
            b.wajibKunci == 1
                ? 'Masih 1 nota dikirim'
                : 'Masih ${b.wajibKunci} nota dikirim',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 10,
              height: 1.15,
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _nilai(
    BuildContext context, {
    required String label,
    required int n,
    String? jenis,
    String? rute,
    bool dummy = false,
    bool chip = false,
    int? chipDari,
    bool hijauChip = false,
    VoidCallback? ketuk,
  }) {
    final nilaiChip = chipDari ?? n;
    final pakaiChip = chip && nilaiChip > 0;
    final jenisCek = jenis != null &&
        const {'kiriman', 'batal', 'pending', 'retur'}.contains(jenis);
    final chipHijau = hijauChip ||
        (pakaiChip &&
            jenisCek &&
            rute != null &&
            CekRinciSetoran.instance.hijau(
              tanggal: data.tanggal,
              jenis: jenis,
              rute: rute,
            ));
    final chipBiru = pakaiChip && jenis == 'actual';
    final bisaRinci = !sibuk && n != 0 && jenis != null;
    final bisaDummy = !sibuk && dummy && nilaiChip > 0;
    final aksi = ketuk ??
        (bisaRinci
            ? () => bukaRinciSetoran(
                  context: context,
                  jenis: jenis,
                  rute: rute,
                  idBuku: data.idSetoranBuku,
                )
            : (bisaDummy
                ? () => tampilPesan(context, 'Belum tersedia.')
                : null));
    final labelTeks = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        height: 1.15,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
    );
    final Widget labelKiri;
    if (pakaiChip) {
      labelKiri = _chip(
        label,
        onTap: aksi,
        hijau: chipHijau,
        biru: chipBiru,
        panah: aksi != null,
      );
    } else {
      labelKiri = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: aksi,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: labelTeks,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: _tinggiBarisNilai,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: _lebarLabel, child: labelKiri),
          const SizedBox(width: 8),
          Expanded(child: _uang(n)),
        ],
      ),
    );
  }

  Widget _chip(
    String label, {
    VoidCallback? onTap,
    bool hijau = false,
    bool biru = false,
    bool panah = true,
  }) {
    final warna = biru
        ? Colors.blue.shade800
        : hijau
            ? Colors.green.shade800
            : Colors.orange.shade800;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: _tinggiBarisNilai,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: warna, width: 1.2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: warna,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    height: 1.15,
                  ),
                ),
              ),
              if (panah) Icon(Icons.chevron_right, size: 14, color: warna),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uang(int n) {
    const gaya = TextStyle(
      fontSize: _teksIsi,
      height: 1.15,
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );
    return Row(
      children: [
        const SizedBox(width: 22, child: Text('Rp', style: gaya)),
        Expanded(
          child: Text(
            Uang.angka(n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: gaya,
          ),
        ),
      ],
    );
  }
}
