import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dialog_gulir_isi.dart';
import '../jaringan.dart';
import '../pesan.dart';
import '../uang.dart';
import 'cek_rinci_setoran.dart';
import 'setoran_repo.dart';

double _rasioNilai(int omset, int modal) {
  if (omset <= 0 || modal <= 0) return 0;
  return (omset - modal) / modal * 100;
}

String _rasioTeks(int omset, int modal) =>
    '${_rasioNilai(omset, modal).toStringAsFixed(2)}%';

bool _cocokAngka(String f, int n) {
  final digit = f.replaceAll(RegExp(r'[^0-9]'), '');
  if (digit.isNotEmpty && n.toString().contains(digit)) return true;
  return Uang.angka(n).toLowerCase().contains(f) ||
      Uang.qty(n).toLowerCase().contains(f);
}

Widget _bidangCari({
  required TextEditingController controller,
  required VoidCallback onUbah,
  required String hint,
  double lebar = 320,
}) {
  return SizedBox(
    width: lebar,
    child: TextField(
      controller: controller,
      onChanged: (_) => onUbah(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 32,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  controller.clear();
                  onUbah();
                },
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
    ),
  );
}

String judulJenisSetoran(String jenis) {
  switch (jenis) {
    case 'kiriman':
      return 'Kiriman';
    case 'batal':
      return 'Batal';
    case 'pending':
      return 'Pending';
    case 'actual':
      return 'Actual';
    case 'retur':
      return 'Retur';
    default:
      return jenis;
  }
}

Future<void> bukaRinciSetoran({
  required BuildContext context,
  required String jenis,
  String? rute,
  int? idBuku,
}) async {
  final repo = SetoranRepo(Supabase.instance.client);
  RinciSetoran data;
  try {
    data = await repo.rinci(jenis: jenis, rute: rute, idBuku: idBuku);
  } catch (e) {
    if (!context.mounted) return;
    tampilPesan(
      context,
      Jaringan.mati(e)
          ? 'Tidak ada internet. Rincian belum bisa dibuka.'
          : 'Rincian belum bisa dibaca.',
    );
    return;
  }
  if (!context.mounted) return;
  if (data.toko.isEmpty) {
    tampilPesan(context, 'Tidak ada ${judulJenisSetoran(jenis).toLowerCase()}.');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => data.jenis == 'retur'
        ? DialogReturToko(data: data)
        : DialogKirimanToko(data: data),
  );
}

String _lingkupRute(RinciSetoran data) {
  final jenis = judulJenisSetoran(data.jenis);
  final rute = data.rute;
  if (rute == null || rute.isEmpty) return '$jenis Â· semua rute';
  return '$jenis Â· $rute';
}

class DialogKirimanToko extends StatefulWidget {
  const DialogKirimanToko({super.key, required this.data});

  final RinciSetoran data;

  @override
  State<DialogKirimanToko> createState() => _DialogKirimanTokoState();
}

class _DialogKirimanTokoState extends State<DialogKirimanToko> {
  static const _garis = Color(0xFF8FB4D9);
  final _cari = TextEditingController();
  var _sortKolom = 0;
  var _sortNaik = true;
  final _centang = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.data.jenis == 'batal' ||
        widget.data.jenis == 'pending' ||
        widget.data.jenis == 'actual') {
      return;
    }
    _centang.addAll(
      CekRinciSetoran.instance.centang(
        tanggal: widget.data.tanggal,
        jenis: widget.data.jenis,
        rute: widget.data.rute,
      ),
    );
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  void _catatTutup() {
    if (widget.data.jenis == 'actual') return;
    if (widget.data.jenis == 'batal' || widget.data.jenis == 'pending') {
      CekRinciSetoran.instance.simpanTutup(
        tanggal: widget.data.tanggal,
        jenis: widget.data.jenis,
        rute: widget.data.rute,
        toko: widget.data.toko,
        centang: CekRinciSetoran.instance.centang(
          tanggal: widget.data.tanggal,
          jenis: widget.data.jenis,
          rute: widget.data.rute,
        ),
        wajib: widget.data.jenis == 'batal'
            ? CekRinciSetoran.kunciSemuaBarang(widget.data.toko)
            : CekRinciSetoran.kunciSemuaNota(widget.data.toko),
      );
      return;
    }
    CekRinciSetoran.instance.simpanTutup(
      tanggal: widget.data.tanggal,
      jenis: widget.data.jenis,
      rute: widget.data.rute,
      toko: widget.data.toko,
      centang: _centang,
    );
  }

  bool get _centangToko =>
      widget.data.jenis != 'batal' &&
      widget.data.jenis != 'pending' &&
      widget.data.jenis != 'actual';

  String get _judul {
    final jenis = judulJenisSetoran(widget.data.jenis);
    final rute = widget.data.rute;
    if (rute == null || rute.isEmpty) return jenis;
    return '$jenis $rute';
  }

  bool _cocok(TokoSetoranRinci b) {
    final f = _cari.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    final digit = f.replaceAll(RegExp(r'[^0-9]'), '');
    bool angka(int n) {
      if (digit.isNotEmpty && n.toString().contains(digit)) return true;
      return Uang.angka(n).toLowerCase().contains(f);
    }

    return b.nama.toLowerCase().contains(f) ||
        b.idPelanggan.toLowerCase().contains(f) ||
        b.rutePengirim.toLowerCase().contains(f) ||
        b.status.toLowerCase().contains(f) ||
        angka(b.nota) ||
        angka(b.sku.length) ||
        angka(b.packed) ||
        angka(b.batal) ||
        angka(b.pending) ||
        angka(b.actual);
  }

  int _banding(TokoSetoranRinci a, TokoSetoranRinci b) {
    final r = switch (_sortKolom) {
      0 => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
      1 => a.rutePengirim.toLowerCase().compareTo(b.rutePengirim.toLowerCase()),
      2 => a.nota.compareTo(b.nota),
      3 => a.sku.length.compareTo(b.sku.length),
      4 => a.packed.compareTo(b.packed),
      5 => a.batal.compareTo(b.batal),
      6 => a.pending.compareTo(b.pending),
      7 => a.actual.compareTo(b.actual),
      _ => a.status.toLowerCase().compareTo(b.status.toLowerCase()),
    };
    return _sortNaik ? r : -r;
  }

  @override
  Widget build(BuildContext context) {
    final tampil = widget.data.toko.where(_cocok).toList()..sort(_banding);

    final jumNota = tampil.fold<int>(0, (a, b) => a + b.nota);
    final jumSku = tampil.fold<int>(0, (a, b) => a + b.sku.length);
    final jumPacked = tampil.fold<int>(0, (a, b) => a + b.packed);
    final jumBatal = tampil.fold<int>(0, (a, b) => a + b.batal);
    final jumPending = tampil.fold<int>(0, (a, b) => a + b.pending);
    final jumActual = tampil.fold<int>(0, (a, b) => a + b.actual);

    const gayaJumlah = TextStyle(fontWeight: FontWeight.bold);

    DataCell uang(int n, {bool tebal = false}) => DataCell(
          Text(
            Uang.angka(n),
            textAlign: TextAlign.right,
            style: tebal ? gayaJumlah : null,
          ),
        );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _catatTutup();
      },
      child: AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              _judul,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 460,
            child: TextField(
              controller: _cari,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cari toko, rute, status, atau angka',
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 32,
                ),
                suffixIcon: _cari.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _cari.clear();
                          setState(() {});
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        width: 980,
        child: DaftarGulirDialog(
              faktor: 0.62,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  border: const TableBorder(
                    verticalInside: BorderSide(color: _garis, width: 1),
                  ),
                  columnSpacing: 12,
                  horizontalMargin: 8,
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 40,
                  columns: [
                    _kolom('Toko', 0, lebar: _centangToko ? 188 : 160),
                    _kolom('Rute', 1, lebar: 88),
                    _kolom('Nota', 2, angka: true, lebar: 64),
                    _kolom('SKU', 3, angka: true, lebar: 64),
                    _kolom('Kiriman', 4, angka: true),
                    _kolom('Batal', 5, angka: true),
                    _kolom('Pending', 6, angka: true),
                    _kolom('Actual', 7, angka: true),
                    _kolom('Status', 8, lebar: 80),
                  ],
                  rows: [
                    for (final b in tampil)
                      DataRow(
                        cells: [
                          DataCell(_namaToko(context, b)),
                          DataCell(Text(b.rutePengirim)),
                          uang(b.nota),
                          uang(b.sku.length),
                          uang(b.packed),
                          uang(b.batal),
                          uang(b.pending),
                          uang(b.actual),
                          DataCell(Text(b.status)),
                        ],
                      ),
                    DataRow(
                      cells: [
                        DataCell(
                          Text(
                            'Jumlah (${tampil.length})',
                            style: gayaJumlah,
                          ),
                        ),
                        const DataCell(Text('')),
                        uang(jumNota, tebal: true),
                        uang(jumSku, tebal: true),
                        uang(jumPacked, tebal: true),
                        uang(jumBatal, tebal: true),
                        uang(jumPending, tebal: true),
                        uang(jumActual, tebal: true),
                        const DataCell(Text('')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
    );
  }

  Widget _namaToko(BuildContext context, TokoSetoranRinci b) {
    final nama = Tooltip(
      message: 'Rincian nota',
      child: InkWell(
        onTap: b.notaList.isEmpty && b.sku.isEmpty
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (ctx) => DialogNotaToko(
                    jenis: widget.data.jenis,
                    toko: b,
                    tanggal: widget.data.tanggal,
                    ruteCek: widget.data.rute,
                    wajibBarang: widget.data.jenis == 'batal'
                        ? CekRinciSetoran.kunciSemuaBarang(widget.data.toko)
                        : const {},
                    wajibNota: widget.data.jenis == 'pending'
                        ? CekRinciSetoran.kunciSemuaNota(widget.data.toko)
                        : const {},
                  ),
                ),
        child: Text(
          b.nama,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Tema.seed,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (!_centangToko) return nama;
    return Row(
      children: [
        Checkbox(
          value: _centang.contains(CekRinciSetoran.kunciToko(b)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            setState(() {
              final id = CekRinciSetoran.kunciToko(b);
              if (v == true) {
                _centang.add(id);
              } else {
                _centang.remove(id);
              }
            });
          },
        ),
        Expanded(child: nama),
      ],
    );
  }

  DataColumn _kolom(
    String judul,
    int indeks, {
    bool angka = false,
    double lebar = 92,
  }) {
    final aktif = _sortKolom == indeks;
    return DataColumn(
      headingRowAlignment: MainAxisAlignment.center,
      numeric: angka,
      label: InkWell(
        onTap: () {
          setState(() {
            if (_sortKolom == indeks) {
              _sortNaik = !_sortNaik;
            } else {
              _sortKolom = indeks;
              _sortNaik = true;
            }
          });
        },
        child: SizedBox(
          width: lebar,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  judul,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: aktif ? Tema.seed : Colors.black,
                  ),
                ),
              ),
              if (aktif)
                Icon(
                  _sortNaik ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                  color: Tema.seed,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DialogReturToko extends StatefulWidget {
  const DialogReturToko({super.key, required this.data});

  final RinciSetoran data;

  @override
  State<DialogReturToko> createState() => _DialogReturTokoState();
}

class _DialogReturTokoState extends State<DialogReturToko> {
  static const _garis = Color(0xFF8FB4D9);

  void _catatTutup() {
    CekRinciSetoran.instance.simpanTutup(
      tanggal: widget.data.tanggal,
      jenis: 'retur',
      rute: widget.data.rute,
      toko: widget.data.toko,
      centang: CekRinciSetoran.instance.centang(
        tanggal: widget.data.tanggal,
        jenis: 'retur',
        rute: widget.data.rute,
      ),
      wajib: CekRinciSetoran.kunciSemuaBarang(widget.data.toko),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gayaJumlah = TextStyle(fontWeight: FontWeight.bold);
    DataCell uang(int n, {bool tebal = false}) => DataCell(
          Text(
            Uang.angka(n),
            textAlign: TextAlign.right,
            style: tebal ? gayaJumlah : null,
          ),
        );
    DataColumn judul(String t, {bool angka = false}) => DataColumn(
          headingRowAlignment: MainAxisAlignment.center,
          numeric: angka,
          label: Text(
            t,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        );

    final tampil = [...widget.data.toko]..sort(
        (a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
      );
    final jumSku = tampil.fold<int>(0, (a, b) => a + b.sku.length);
    final jumRetur = tampil.fold<int>(0, (a, b) => a + b.retur);
    final rute = widget.data.rute;
    final judulTeks =
        (rute == null || rute.isEmpty) ? 'Retur' : 'Retur $rute';

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _catatTutup();
      },
      child: AlertDialog(
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 640),
      title: Text(
        judulTeks,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        child: DaftarGulirDialog(
          faktor: 0.55,
          child: IntrinsicWidth(
            child: DataTable(
              border: const TableBorder(
                verticalInside: BorderSide(color: _garis, width: 1),
              ),
              columnSpacing: 16,
              horizontalMargin: 8,
              headingRowHeight: 36,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              columns: [
                judul('Toko'),
                judul('Rute'),
                judul('SKU', angka: true),
                judul('Retur', angka: true),
              ],
              rows: [
                for (final b in tampil)
                  DataRow(
                    cells: [
                      DataCell(
                        Tooltip(
                          message: 'Rincian barang',
                          child: InkWell(
                            onTap: b.sku.isEmpty
                                ? null
                                : () => showDialog<void>(
                                      context: context,
                                      builder: (ctx) => RinciSkuDialog(
                                        jenis: 'retur',
                                        toko: b,
                                        nota: b.notaList.isEmpty
                                            ? null
                                            : b.notaList.first,
                                        tanggal: widget.data.tanggal,
                                        ruteCek: widget.data.rute,
                                        wajibBarang:
                                            CekRinciSetoran.kunciSemuaBarang(
                                          widget.data.toko,
                                        ),
                                      ),
                                    ),
                            child: Text(
                              b.nama,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Tema.seed,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(b.rutePengirim)),
                      uang(b.sku.length),
                      uang(b.retur),
                    ],
                  ),
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        'Jumlah (${tampil.length})',
                        style: gayaJumlah,
                      ),
                    ),
                    const DataCell(Text('')),
                    uang(jumSku, tebal: true),
                    uang(jumRetur, tebal: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
    );
  }
}

class DialogNotaToko extends StatefulWidget {
  const DialogNotaToko({
    super.key,
    required this.jenis,
    required this.toko,
    this.tanggal,
    this.ruteCek,
    this.wajibBarang = const {},
    this.wajibNota = const {},
  });

  final String jenis;
  final TokoSetoranRinci toko;
  final DateTime? tanggal;
  final String? ruteCek;
  final Set<String> wajibBarang;
  final Set<String> wajibNota;

  @override
  State<DialogNotaToko> createState() => _DialogNotaTokoState();
}

class _DialogNotaTokoState extends State<DialogNotaToko> {
  static const _garis = Color(0xFF8FB4D9);
  final _centang = <String>{};
  final _gulir = ScrollController();
  final _cari = TextEditingController();
  var _sortKolom = 0;
  var _sortNaik = true;

  bool get _cekNota => widget.jenis == 'pending';

  @override
  void dispose() {
    _cari.dispose();
    _gulir.dispose();
    super.dispose();
  }

  bool _cocok(NotaSetoranRinci n) {
    final f = _cari.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    if (n.id.toLowerCase().contains(f) ||
        n.rute.toLowerCase().contains(f) ||
        n.status.toLowerCase().contains(f)) {
      return true;
    }
    for (final s in n.sku) {
      if (s.nama.toLowerCase().contains(f) ||
          s.idBarang.toLowerCase().contains(f)) {
        return true;
      }
    }
    return _cocokAngka(f, n.sku.length) ||
        _cocokAngka(f, n.nilaiOrder) ||
        _cocokAngka(f, n.packed) ||
        _cocokAngka(f, n.batal) ||
        _cocokAngka(f, n.pending) ||
        _cocokAngka(f, n.actual) ||
        _cocokAngka(f, n.retur) ||
        _rasioTeks(n.nilaiOrder, n.modalOrder).toLowerCase().contains(f) ||
        _rasioTeks(n.packed, n.modalPacked).toLowerCase().contains(f) ||
        _rasioTeks(n.pending, n.modalPending).toLowerCase().contains(f) ||
        _rasioTeks(n.actual, n.modalActual).toLowerCase().contains(f);
  }

  int _banding(NotaSetoranRinci a, NotaSetoranRinci b, bool pakaiRetur) {
    int rasio(int oa, int ma, int ob, int mb) =>
        _rasioNilai(oa, ma).compareTo(_rasioNilai(ob, mb));
    final r = switch (_sortKolom) {
      0 => a.id.toLowerCase().compareTo(b.id.toLowerCase()),
      1 => a.sku.length.compareTo(b.sku.length),
      2 => a.nilaiOrder.compareTo(b.nilaiOrder),
      3 => rasio(a.nilaiOrder, a.modalOrder, b.nilaiOrder, b.modalOrder),
      4 => a.packed.compareTo(b.packed),
      5 => rasio(a.packed, a.modalPacked, b.packed, b.modalPacked),
      6 => a.batal.compareTo(b.batal),
      7 => a.pending.compareTo(b.pending),
      8 => rasio(a.pending, a.modalPending, b.pending, b.modalPending),
      9 => a.actual.compareTo(b.actual),
      10 => rasio(a.actual, a.modalActual, b.actual, b.modalActual),
      11 => pakaiRetur
          ? a.retur.compareTo(b.retur)
          : a.status.toLowerCase().compareTo(b.status.toLowerCase()),
      _ => a.status.toLowerCase().compareTo(b.status.toLowerCase()),
    };
    return _sortNaik ? r : -r;
  }

  void _urut(int i) {
    setState(() {
      if (_sortKolom == i) {
        _sortNaik = !_sortNaik;
      } else {
        _sortKolom = i;
        _sortNaik = i == 0;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (!_cekNota) return;
    final sudah = CekRinciSetoran.instance.centang(
      tanggal: widget.tanggal,
      jenis: widget.jenis,
      rute: widget.ruteCek,
    );
    for (final n in widget.toko.notaList) {
      final id = CekRinciSetoran.kunciNota(widget.toko, n);
      if (sudah.contains(id)) _centang.add(id);
    }
  }

  void _catatTutup() {
    if (!_cekNota) return;
    CekRinciSetoran.instance.gabungBarang(
      tanggal: widget.tanggal,
      jenis: widget.jenis,
      rute: widget.ruteCek,
      kunciNota: {
        for (final n in widget.toko.notaList)
          CekRinciSetoran.kunciNota(widget.toko, n),
      },
      centangNota: _centang,
      wajib: widget.wajibNota,
    );
  }

  @override
  Widget build(BuildContext context) {
    const gayaJumlah = TextStyle(fontWeight: FontWeight.bold);
    final pakaiRetur = widget.jenis == 'retur';
    final tampil = widget.toko.notaList.where(_cocok).toList()
      ..sort((a, b) => _banding(a, b, pakaiRetur));
    final jumSku = tampil.fold<int>(0, (a, n) => a + n.sku.length);
    final jumOrder = tampil.fold<int>(0, (a, n) => a + n.nilaiOrder);
    final jumModalOrder = tampil.fold<int>(0, (a, n) => a + n.modalOrder);
    final jumPacked = tampil.fold<int>(0, (a, n) => a + n.packed);
    final jumModalPacked = tampil.fold<int>(0, (a, n) => a + n.modalPacked);
    final jumBatal = tampil.fold<int>(0, (a, n) => a + n.batal);
    final jumPending = tampil.fold<int>(0, (a, n) => a + n.pending);
    final jumModalPending = tampil.fold<int>(0, (a, n) => a + n.modalPending);
    final jumActual = tampil.fold<int>(0, (a, n) => a + n.actual);
    final jumModalActual = tampil.fold<int>(0, (a, n) => a + n.modalActual);
    final jumRetur = tampil.fold<int>(0, (a, n) => a + n.retur);
    final rute = widget.toko.rutePengirim.trim();
    final judulTeks = rute.isEmpty
        ? 'Nota ${widget.toko.nama}'
        : 'Nota ${widget.toko.nama} $rute';
    final iStatus = pakaiRetur ? 12 : 11;
    final lebar = pakaiRetur
        ? const [
            176.0,
            44.0,
            84.0,
            48.0,
            84.0,
            48.0,
            72.0,
            84.0,
            48.0,
            84.0,
            48.0,
            76.0,
            72.0,
          ]
        : const [
            188.0,
            44.0,
            88.0,
            48.0,
            88.0,
            48.0,
            72.0,
            88.0,
            48.0,
            88.0,
            52.0,
            80.0,
          ];
    final judulKolom = pakaiRetur
        ? const [
            'Nota',
            'SKU',
            'Order',
            '%',
            'Kiriman',
            '%',
            'Batal',
            'Pending',
            '%',
            'Actual',
            '%',
            'Retur',
            'Status',
          ]
        : const [
            'Nota',
            'SKU',
            'Order',
            '%',
            'Kiriman',
            '%',
            'Batal',
            'Pending',
            '%',
            'Actual',
            '%',
            'Status',
          ];

    Widget sel(
      String teks, {
      required int i,
      bool angkaKolom = false,
      bool tengah = false,
      bool tebal = false,
      Widget? anak,
    }) {
      return SizedBox(
        width: lebar[i],
        child: Padding(
          padding: EdgeInsets.only(
            left: i == 0 ? 0 : 6,
            right: i == lebar.length - 1 ? 0 : 4,
          ),
          child: anak ??
              Align(
                alignment: tengah
                    ? Alignment.center
                    : angkaKolom
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                child: Text(
                  teks,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: tengah
                      ? TextAlign.center
                      : angkaKolom
                          ? TextAlign.right
                          : TextAlign.left,
                  style: tebal ? gayaJumlah : null,
                ),
              ),
        ),
      );
    }

    Widget uang(int n, int i, {bool tebal = false}) =>
        sel(Uang.angka(n), i: i, angkaKolom: true, tebal: tebal);

    Widget baris(List<Widget> isi, {bool jumlah = false}) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: jumlah ? Colors.grey.shade50 : null,
          border: const Border(bottom: BorderSide(color: _garis, width: 0.5)),
        ),
        child: SizedBox(height: 40, child: Row(children: isi)),
      );
    }

    String rasio(int omset, int modal) => _rasioTeks(omset, modal);

    List<Widget> nilaiNota({
      required int sku,
      required int order,
      required int modalO,
      required int packed,
      required int modalK,
      required int batal,
      required int pending,
      required int modalP,
      required int actual,
      required int modalA,
      required int retur,
      bool tebal = false,
    }) {
      return [
        uang(sku, 1, tebal: tebal),
        uang(order, 2, tebal: tebal),
        sel(rasio(order, modalO), i: 3, angkaKolom: true, tebal: tebal),
        uang(packed, 4, tebal: tebal),
        sel(rasio(packed, modalK), i: 5, angkaKolom: true, tebal: tebal),
        uang(batal, 6, tebal: tebal),
        uang(pending, 7, tebal: tebal),
        sel(rasio(pending, modalP), i: 8, angkaKolom: true, tebal: tebal),
        uang(actual, 9, tebal: tebal),
        sel(rasio(actual, modalA), i: 10, angkaKolom: true, tebal: tebal),
        if (pakaiRetur) uang(retur, 11, tebal: tebal),
      ];
    }

    final dialog = DialogGulirIsi(
      lebar: lebar.fold<double>(0, (a, b) => a + b),
      controller: _gulir,
      itemCount: tampil.length,
      judul: Row(
        children: [
          Expanded(
            child: Text(
              judulTeks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          _bidangCari(
            controller: _cari,
            onUbah: () => setState(() {}),
            hint: 'Cari nota, status, SKU, atau angka',
          ),
        ],
      ),
      kepala: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _garis)),
        ),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              for (var i = 0; i < judulKolom.length; i++)
                InkWell(
                  onTap: () => _urut(i),
                  child: SizedBox(
                    width: lebar[i],
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? 0 : 6,
                        right: i == judulKolom.length - 1 ? 0 : 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              judulKolom[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (_sortKolom == i)
                            Icon(
                              _sortNaik
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      jumlah: baris(
        jumlah: true,
        [
          sel(
            'Jumlah (${tampil.length})',
            i: 0,
            tebal: true,
          ),
          ...nilaiNota(
            sku: jumSku,
            order: jumOrder,
            modalO: jumModalOrder,
            packed: jumPacked,
            modalK: jumModalPacked,
            batal: jumBatal,
            pending: jumPending,
            modalP: jumModalPending,
            actual: jumActual,
            modalA: jumModalActual,
            retur: jumRetur,
            tebal: true,
          ),
          sel('', i: iStatus),
        ],
      ),
      itemBuilder: (context, i) {
        final notaBaris = tampil[i];
        return baris([
          sel('', i: 0, anak: _namaNota(notaBaris)),
          ...nilaiNota(
            sku: notaBaris.sku.length,
            order: notaBaris.nilaiOrder,
            modalO: notaBaris.modalOrder,
            packed: notaBaris.packed,
            modalK: notaBaris.modalPacked,
            batal: notaBaris.batal,
            pending: notaBaris.pending,
            modalP: notaBaris.modalPending,
            actual: notaBaris.actual,
            modalA: notaBaris.modalActual,
            retur: notaBaris.retur,
          ),
          sel(notaBaris.status, i: iStatus, tengah: true),
        ]);
      },
    );
    if (!_cekNota) return dialog;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _catatTutup();
      },
      child: dialog,
    );
  }

  Widget _namaNota(NotaSetoranRinci n) {
    final nama = Tooltip(
      message: 'Rincian barang',
      child: InkWell(
        onTap: n.sku.isEmpty
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (ctx) => RinciSkuDialog(
                    jenis: widget.jenis,
                    toko: widget.toko,
                    nota: n,
                    tanggal: widget.tanggal,
                    ruteCek: widget.ruteCek,
                    wajibBarang: widget.wajibBarang,
                  ),
                ),
        child: Text(
          n.id,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Tema.seed,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (!_cekNota) return nama;
    final id = CekRinciSetoran.kunciNota(widget.toko, n);
    return Row(
      children: [
        Checkbox(
          value: _centang.contains(id),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _centang.add(id);
              } else {
                _centang.remove(id);
              }
            });
          },
        ),
        Expanded(child: nama),
      ],
    );
  }
}

class RinciTokoDialog extends StatelessWidget {
  const RinciTokoDialog({super.key, required this.data});

  final RinciSetoran data;

  @override
  Widget build(BuildContext context) {
    final nToko = data.toko.length;
    return AlertDialog(
      title: Text(
        _lingkupRute(data),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              [
                if (data.tanggal != null) Uang.tanggal(data.tanggal!),
                '$nToko toko',
                Uang.rp(data.total),
                'Tap toko untuk SKU',
              ].join(' Â· '),
              style: const TextStyle(
                color: Tema.redup,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DaftarGulirDialog(
              faktor: 0.5,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                primary: false,
                itemCount: data.toko.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _barisToko(context, data.toko[i]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  Widget _barisToko(BuildContext context, TokoSetoranRinci t) {
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (ctx) => RinciSkuDialog(
            jenis: data.jenis,
            toko: t,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.nama,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      t.idPelanggan,
                      if (t.rutePengirim.isNotEmpty) t.rutePengirim,
                      '${t.sku.length} SKU',
                    ].join(' Â· '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Tema.redup,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              Uang.rp(t.nilai),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Tema.seed,
                decoration: TextDecoration.underline,
                decorationColor: Tema.seed,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Tema.redup),
          ],
        ),
      ),
    );
  }
}

class RinciSkuDialog extends StatefulWidget {
  const RinciSkuDialog({
    super.key,
    required this.jenis,
    required this.toko,
    this.nota,
    this.tanggal,
    this.ruteCek,
    this.wajibBarang = const {},
  });

  final String jenis;
  final TokoSetoranRinci toko;
  final NotaSetoranRinci? nota;
  final DateTime? tanggal;
  final String? ruteCek;
  final Set<String> wajibBarang;

  @override
  State<RinciSkuDialog> createState() => _RinciSkuDialogState();
}

class _RinciSkuDialogState extends State<RinciSkuDialog> {
  static const _garis = Color(0xFF8FB4D9);
  final _centang = <String>{};
  final _gulir = ScrollController();
  final _cari = TextEditingController();
  var _sortKolom = 0;
  var _sortNaik = true;

  bool get _cekBarang =>
      (widget.jenis == 'batal' || widget.jenis == 'retur') &&
      widget.nota != null;

  @override
  void dispose() {
    _cari.dispose();
    _gulir.dispose();
    super.dispose();
  }

  bool _cocok(SkuSetoranRinci s) {
    final f = _cari.text.trim().toLowerCase();
    if (f.isEmpty) return true;
    if (s.nama.toLowerCase().contains(f) ||
        s.idBarang.toLowerCase().contains(f)) {
      return true;
    }
    return _cocokAngka(f, s.qtyOrder) ||
        _cocokAngka(f, s.nilaiOrder) ||
        _cocokAngka(f, s.qtyPacked) ||
        _cocokAngka(f, s.packed) ||
        _cocokAngka(f, s.qtyBatal) ||
        _cocokAngka(f, s.batal) ||
        _cocokAngka(f, s.qtyActual) ||
        _cocokAngka(f, s.actual) ||
        _cocokAngka(f, s.qtyRetur) ||
        _cocokAngka(f, s.nilaiRetur) ||
        _rasioTeks(s.nilaiOrder, s.modalOrder).toLowerCase().contains(f) ||
        _rasioTeks(s.packed, s.modalPacked).toLowerCase().contains(f) ||
        _rasioTeks(s.actual, s.modalActual).toLowerCase().contains(f);
  }

  int _banding(SkuSetoranRinci a, SkuSetoranRinci b, bool pakaiRetur) {
    int rasio(int oa, int ma, int ob, int mb) =>
        _rasioNilai(oa, ma).compareTo(_rasioNilai(ob, mb));
    if (pakaiRetur) {
      final r = switch (_sortKolom) {
        0 => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
        1 => a.qtyRetur.compareTo(b.qtyRetur),
        _ => a.nilaiRetur.compareTo(b.nilaiRetur),
      };
      return _sortNaik ? r : -r;
    }
    final r = switch (_sortKolom) {
      0 => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
      1 => a.qtyOrder.compareTo(b.qtyOrder),
      2 => a.nilaiOrder.compareTo(b.nilaiOrder),
      3 => rasio(a.nilaiOrder, a.modalOrder, b.nilaiOrder, b.modalOrder),
      4 => a.qtyPacked.compareTo(b.qtyPacked),
      5 => a.packed.compareTo(b.packed),
      6 => rasio(a.packed, a.modalPacked, b.packed, b.modalPacked),
      7 => a.qtyBatal.compareTo(b.qtyBatal),
      8 => a.batal.compareTo(b.batal),
      9 => a.qtyActual.compareTo(b.qtyActual),
      10 => a.actual.compareTo(b.actual),
      _ => rasio(a.actual, a.modalActual, b.actual, b.modalActual),
    };
    return _sortNaik ? r : -r;
  }

  void _urut(int i) {
    setState(() {
      if (_sortKolom == i) {
        _sortNaik = !_sortNaik;
      } else {
        _sortKolom = i;
        _sortNaik = i == 0;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (!_cekBarang) return;
    final nota = widget.nota!;
    final sudah = CekRinciSetoran.instance.centang(
      tanggal: widget.tanggal,
      jenis: widget.jenis,
      rute: widget.ruteCek,
    );
    for (final s in nota.sku) {
      final id = CekRinciSetoran.kunciBarang(widget.toko, nota, s);
      if (sudah.contains(id)) _centang.add(id);
    }
  }

  void _catatTutup() {
    if (!_cekBarang) return;
    final nota = widget.nota!;
    CekRinciSetoran.instance.gabungBarang(
      tanggal: widget.tanggal,
      jenis: widget.jenis,
      rute: widget.ruteCek,
      kunciNota: {
        for (final s in nota.sku)
          CekRinciSetoran.kunciBarang(widget.toko, nota, s),
      },
      centangNota: _centang,
      wajib: widget.wajibBarang,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nota != null) return _tabelNota(context, widget.nota!);
    return _daftarToko(context);
  }

  Widget _tabelNota(BuildContext context, NotaSetoranRinci nota) {
    const gayaJumlah = TextStyle(fontWeight: FontWeight.bold);
    final pakaiRetur = widget.jenis == 'retur';
    final sku = nota.sku.where(_cocok).toList()
      ..sort((a, b) => _banding(a, b, pakaiRetur));
    final jumQtyPacked = sku.fold<int>(0, (a, s) => a + s.qtyPacked);
    final jumPacked = sku.fold<int>(0, (a, s) => a + s.packed);
    final jumQtyOrder = sku.fold<int>(0, (a, s) => a + s.qtyOrder);
    final jumOrder = sku.fold<int>(0, (a, s) => a + s.nilaiOrder);
    final jumModalOrder = sku.fold<int>(0, (a, s) => a + s.modalOrder);
    final jumModalPacked = sku.fold<int>(0, (a, s) => a + s.modalPacked);
    final jumModalActual = sku.fold<int>(0, (a, s) => a + s.modalActual);
    final jumQtyBatal = sku.fold<int>(0, (a, s) => a + s.qtyBatal);
    final jumBatal = sku.fold<int>(0, (a, s) => a + s.batal);
    final jumQtyActual = sku.fold<int>(0, (a, s) => a + s.qtyActual);
    final jumActual = sku.fold<int>(0, (a, s) => a + s.actual);
    final jumQtyRetur = sku.fold<int>(0, (a, s) => a + s.qtyRetur);
    final jumRetur = sku.fold<int>(0, (a, s) => a + s.nilaiRetur);
    final rute = widget.toko.rutePengirim.trim();
    final judulTeks = [
      widget.toko.nama,
      if (rute.isNotEmpty) rute,
      nota.id,
    ].join(' ');
    final lebar = pakaiRetur
        ? const [280.0, 100.0, 100.0]
        : const [
            200.0,
            72.0,
            88.0,
            52.0,
            80.0,
            88.0,
            52.0,
            72.0,
            80.0,
            80.0,
            88.0,
            52.0,
          ];
    final judulKolom = pakaiRetur
        ? const ['Barang', 'qty(retur)', 'Retur']
        : const [
            'Barang',
            'qty(order)',
            'Order',
            '%',
            'qty(kiriman)',
            'Kiriman',
            '%',
            'qty(batal)',
            'Batal',
            'qty(actual)',
            'Actual',
            '%',
          ];

    Widget sel(
      String teks, {
      required int i,
      bool angka = false,
      bool tebal = false,
      Widget? anak,
    }) {
      return SizedBox(
        width: lebar[i],
        child: anak ??
            Text(
              teks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: angka ? TextAlign.right : TextAlign.left,
              style: tebal ? gayaJumlah : null,
            ),
      );
    }

    Widget angkaTeks(String teks, int i, {bool tebal = false}) =>
        sel(teks, i: i, angka: true, tebal: tebal);

    Widget baris(List<Widget> isi, {bool jumlah = false}) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: jumlah ? Colors.grey.shade50 : null,
          border: const Border(bottom: BorderSide(color: _garis, width: 0.5)),
        ),
        child: SizedBox(height: 40, child: Row(children: isi)),
      );
    }

    String rasio(int omset, int modal) => _rasioTeks(omset, modal);

    List<Widget> selNilai({
      required int qtyO,
      required int order,
      required int modalO,
      required int qtyK,
      required int kiriman,
      required int modalK,
      required int qtyB,
      required int batal,
      required int qtyA,
      required int actual,
      required int modalA,
      required int qtyR,
      required int retur,
      bool tebal = false,
    }) {
      if (pakaiRetur) {
        return [
          angkaTeks(Uang.qty(qtyR), 1, tebal: tebal),
          angkaTeks(Uang.angka(retur), 2, tebal: tebal),
        ];
      }
      return [
        angkaTeks(Uang.qty(qtyO), 1, tebal: tebal),
        angkaTeks(Uang.angka(order), 2, tebal: tebal),
        angkaTeks(rasio(order, modalO), 3, tebal: tebal),
        angkaTeks(Uang.qty(qtyK), 4, tebal: tebal),
        angkaTeks(Uang.angka(kiriman), 5, tebal: tebal),
        angkaTeks(rasio(kiriman, modalK), 6, tebal: tebal),
        angkaTeks(Uang.qty(qtyB), 7, tebal: tebal),
        angkaTeks(Uang.angka(batal), 8, tebal: tebal),
        angkaTeks(Uang.qty(qtyA), 9, tebal: tebal),
        angkaTeks(Uang.angka(actual), 10, tebal: tebal),
        angkaTeks(rasio(actual, modalA), 11, tebal: tebal),
      ];
    }

    final tabel = DialogGulirIsi(
      lebar: lebar.fold<double>(0, (a, b) => a + b),
      controller: _gulir,
      itemCount: sku.length,
      judul: Row(
        children: [
          Expanded(
            child: Text(
              judulTeks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          _bidangCari(
            controller: _cari,
            onUbah: () => setState(() {}),
            hint: 'Cari barang, SKU, atau angka',
          ),
        ],
      ),
      kepala: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _garis)),
        ),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              for (var i = 0; i < judulKolom.length; i++)
                InkWell(
                  onTap: () => _urut(i),
                  child: SizedBox(
                    width: lebar[i],
                    height: 36,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            judulKolom[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_sortKolom == i)
                          Icon(
                            _sortNaik
                                ? Icons.arrow_drop_up
                                : Icons.arrow_drop_down,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      jumlah: baris(
        jumlah: true,
        [
          sel('Jumlah (${sku.length})', i: 0, tebal: true),
          ...selNilai(
            qtyO: jumQtyOrder,
            order: jumOrder,
            modalO: jumModalOrder,
            qtyK: jumQtyPacked,
            kiriman: jumPacked,
            modalK: jumModalPacked,
            qtyB: jumQtyBatal,
            batal: jumBatal,
            qtyA: jumQtyActual,
            actual: jumActual,
            modalA: jumModalActual,
            qtyR: jumQtyRetur,
            retur: jumRetur,
            tebal: true,
          ),
        ],
      ),
      itemBuilder: (context, i) {
        final s = sku[i];
        return baris([
          sel('', i: 0, anak: _namaBarang(nota, s)),
          ...selNilai(
            qtyO: s.qtyOrder,
            order: s.nilaiOrder,
            modalO: s.modalOrder,
            qtyK: s.qtyPacked,
            kiriman: s.packed,
            modalK: s.modalPacked,
            qtyB: s.qtyBatal,
            batal: s.batal,
            qtyA: s.qtyActual,
            actual: s.actual,
            modalA: s.modalActual,
            qtyR: s.qtyRetur,
            retur: s.nilaiRetur,
          ),
        ]);
      },
    );
    if (!_cekBarang) return tabel;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _catatTutup();
      },
      child: tabel,
    );
  }

  Widget _namaBarang(NotaSetoranRinci nota, SkuSetoranRinci s) {
    final nama = Text(s.nama);
    if (!_cekBarang) return nama;
    final id = CekRinciSetoran.kunciBarang(widget.toko, nota, s);
    return Row(
      children: [
        Checkbox(
          value: _centang.contains(id),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _centang.add(id);
              } else {
                _centang.remove(id);
              }
            });
          },
        ),
        Expanded(child: nama),
      ],
    );
  }

  Widget _daftarToko(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${judulJenisSetoran(widget.jenis)} ${widget.toko.nama}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: IsiDialog(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              [
                widget.toko.idPelanggan,
                if (widget.toko.rutePengirim.isNotEmpty)
                  widget.toko.rutePengirim,
                '${widget.toko.sku.length} SKU',
                Uang.rp(widget.toko.nilai),
              ].join(' · '),
              style: const TextStyle(
                color: Tema.redup,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DaftarGulirDialog(
              faktor: 0.5,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                primary: false,
                itemCount: widget.toko.sku.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _barisSku(widget.toko.sku[i]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  Widget _barisSku(SkuSetoranRinci s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.nama,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.idBarang}  ·  ${Uang.qty(s.qty)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Tema.redup,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Uang.rp(s.nilai),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
