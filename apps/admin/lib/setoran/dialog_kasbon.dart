import 'package:flutter/material.dart';

import '../dialog_gulir_isi.dart';
import '../uang.dart';
import 'kasbon_cek_setoran.dart';
import 'setoran_repo.dart';

Future<void> bukaDialogKasbon({
  required BuildContext context,
  required DateTime? tanggal,
  required String rute,
  required List<BarisSetoranRute> semuaRute,
  int? idBuku,
  bool lihatSaja = false,
}) async {
  final daftar = rute == 'Jumlah'
      ? semuaRute
      : semuaRute.where((b) => b.rute == rute).toList();
  if (daftar.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DialogKasbon(
      tanggal: tanggal,
      judul: rute == 'Jumlah' ? 'Kasbon semua rute' : 'Kasbon $rute',
      daftar: daftar,
      semuaRute: rute == 'Jumlah',
      idBuku: idBuku,
      lihatSaja: lihatSaja,
    ),
  );
}

class _DialogKasbon extends StatefulWidget {
  const _DialogKasbon({
    required this.tanggal,
    required this.judul,
    required this.daftar,
    required this.semuaRute,
    this.idBuku,
    this.lihatSaja = false,
  });

  final DateTime? tanggal;
  final String judul;
  final List<BarisSetoranRute> daftar;
  final bool semuaRute;
  final int? idBuku;
  final bool lihatSaja;

  @override
  State<_DialogKasbon> createState() => _DialogKasbonState();
}

class _DialogKasbonState extends State<_DialogKasbon> {
  static const _gayaTebal = TextStyle(fontWeight: FontWeight.bold);
  static const _garis = Color(0xFF8FB4D9);
  final _gulir = ScrollController();

  @override
  void dispose() {
    _gulir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KasbonCekSetoran.instance,
      builder: (context, _) {
        final cek = KasbonCekSetoran.instance;
        final orang = [
          for (final b in widget.daftar)
            for (final o in b.orangKasbon) (rute: b.rute, o: o),
        ];
        final jumKlaim = orang.fold<int>(0, (n, x) => n + x.o.klaim);
        final cekKolom = !widget.semuaRute;
        final w = <double>[
          if (cekKolom) 36,
          220,
          88,
        ];
        final judulKolom = <String>[
          if (cekKolom) '',
          'Orang',
          'Klaim',
        ];

        Widget sel(
          String teks, {
          required int i,
          bool angka = false,
          bool tebal = false,
          Widget? anak,
        }) {
          return SizedBox(
            width: w[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: anak ??
                  Align(
                    alignment: angka
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Text(
                      teks,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: angka ? TextAlign.right : TextAlign.left,
                      style: tebal ? _gayaTebal : null,
                    ),
                  ),
            ),
          );
        }

        Widget baris(List<Widget> isi, {bool jumlah = false}) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: jumlah ? Colors.grey.shade50 : null,
              border:
                  const Border(bottom: BorderSide(color: _garis, width: 0.5)),
            ),
            child: SizedBox(height: 40, child: Row(children: isi)),
          );
        }

        final iNama = cekKolom ? 1 : 0;
        final iKlaim = cekKolom ? 2 : 1;

        return DialogGulirIsi(
          lebar: w.fold<double>(0, (a, b) => a + b),
          controller: _gulir,
          itemCount: orang.length,
          judul: Text(
            widget.judul,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
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
                    SizedBox(
                      width: w[i],
                      height: 36,
                      child: Align(
                        alignment: i == iKlaim
                            ? Alignment.centerRight
                            : Alignment.center,
                        child: Text(
                          judulKolom[i],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
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
              if (cekKolom) sel('', i: 0),
              sel('Jumlah (${orang.length})', i: iNama, tebal: true),
              sel(
                Uang.angka(jumKlaim),
                i: iKlaim,
                angka: true,
                tebal: true,
              ),
            ],
          ),
          itemBuilder: (context, i) {
            final x = orang[i];
            return baris([
              if (cekKolom)
                sel(
                  '',
                  i: 0,
                  anak: Checkbox(
                    value: cek.centang(
                      tanggal: widget.tanggal,
                      rute: x.rute,
                      peran: x.o.peran,
                      idBuku: widget.idBuku,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: widget.lihatSaja
                        ? null
                        : (v) => cek.setCentang(
                              tanggal: widget.tanggal,
                              rute: x.rute,
                              peran: x.o.peran,
                              nilai: v ?? false,
                              idBuku: widget.idBuku,
                            ),
                  ),
                ),
              sel(
                widget.semuaRute ? '${x.rute} · ${x.o.label}' : x.o.label,
                i: iNama,
              ),
              sel(Uang.angka(x.o.klaim), i: iKlaim, angka: true),
            ]);
          },
        );
      },
    );
  }
}
