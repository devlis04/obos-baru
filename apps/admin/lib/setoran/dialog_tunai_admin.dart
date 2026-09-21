import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import 'tunai_admin_setoran.dart';

Future<void> bukaDialogTunaiAdmin({
  required BuildContext context,
  required DateTime? tanggal,
  required String rute,
  required int tunaiPengirim,
  List<String> semuaRute = const [],
}) async {
  if (rute == 'Jumlah') {
    await _dialogJumlah(context, tanggal, semuaRute);
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DialogTunaiRute(
      tanggal: tanggal,
      rute: rute,
    ),
  );
}

class _DialogTunaiRute extends StatefulWidget {
  const _DialogTunaiRute({
    required this.tanggal,
    required this.rute,
  });

  final DateTime? tanggal;
  final String rute;

  @override
  State<_DialogTunaiRute> createState() => _DialogTunaiRuteState();
}

class _DialogTunaiRuteState extends State<_DialogTunaiRute> {
  late final List<TextEditingController> _pecahanCtrl;
  late final int _tunaiTersimpan;
  late final bool _pecahanKosong;

  @override
  void initState() {
    super.initState();
    final lama = TunaiAdminSetoran.instance.ambil(widget.tanggal, widget.rute);
    final qtyLama = lama.pecahanLengkap;
    _tunaiTersimpan = lama.tunai;
    _pecahanKosong = lama.tunai > 0 && qtyLama.every((n) => n == 0);
    _pecahanCtrl = List.generate(
      pecahanTunaiAdmin.length,
      (i) => TextEditingController(
        text: qtyLama[i] == 0 ? '' : Uang.angka(qtyLama[i]),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _pecahanCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  int get _total {
    var total = 0;
    for (var i = 0; i < pecahanTunaiAdmin.length; i++) {
      total += pecahanTunaiAdmin[i].nilai * Uang.angkaTeks(_pecahanCtrl[i].text);
    }
    return total;
  }

  void _pakai() {
    TunaiAdminSetoran.instance.simpan(
      tanggal: widget.tanggal,
      rute: widget.rute,
      tunai: _total,
      pecahan: [for (final c in _pecahanCtrl) Uang.angkaTeks(c.text)],
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _isiDialog(
      judul: 'Tunai ${widget.rute}',
      pecahanKosong: _pecahanKosong,
      tunaiTersimpan: _tunaiTersimpan,
      total: _total,
      anakPecahan: [
        for (var i = 0; i < pecahanTunaiAdmin.length; i++)
          _barisPecahan(
            qty: TextField(
              controller: _pecahanCtrl[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: _gaya,
              inputFormatters: const [UangFormatRibuan(kosong: '')],
              onChanged: (_) => setState(() {}),
              decoration: _dekorQty,
            ),
            jenis: pecahanTunaiAdmin[i].jenis,
            label: pecahanTunaiAdmin[i].label,
            hasil: pecahanTunaiAdmin[i].nilai *
                Uang.angkaTeks(_pecahanCtrl[i].text),
          ),
      ],
      aksi: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _pakai,
          child: const Text('Pakai'),
        ),
      ],
    );
  }
}

Future<void> _dialogJumlah(
  BuildContext context,
  DateTime? tanggal,
  List<String> semuaRute,
) async {
  final qty = TunaiAdminSetoran.instance.pecahanJumlah(tanggal, semuaRute);
  var total = 0;
  for (var i = 0; i < pecahanTunaiAdmin.length; i++) {
    total += pecahanTunaiAdmin[i].nilai * qty[i];
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return _isiDialog(
        judul: 'Tunai admin semua rute',
        pecahanKosong: false,
        tunaiTersimpan: 0,
        total: total,
        anakPecahan: [
          for (var i = 0; i < pecahanTunaiAdmin.length; i++)
            _barisPecahan(
              qty: Text(
                Uang.angka(qty[i]),
                textAlign: TextAlign.center,
                style: _gaya,
              ),
              jenis: pecahanTunaiAdmin[i].jenis,
              label: pecahanTunaiAdmin[i].label,
              hasil: pecahanTunaiAdmin[i].nilai * qty[i],
            ),
        ],
        extra: [
          const SizedBox(height: 8),
          for (final r in semuaRute)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 98,
                    child: _uangSel(
                      TunaiAdminSetoran.instance.ambil(tanggal, r).tunai,
                    ),
                  ),
                ],
              ),
            ),
        ],
        aksi: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      );
    },
  );
}

const _gaya = TextStyle(fontSize: 12, height: 1.2);

final _dekorQty = InputDecoration(
  isDense: true,
  hintText: '0',
  hintStyle: _gaya.copyWith(color: Colors.grey),
  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Tema.seed, width: 1),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Tema.seed, width: 1),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Tema.seed, width: 1),
  ),
);

Widget _isiDialog({
  required String judul,
  required List<TableRow> anakPecahan,
  required int total,
  required List<Widget> aksi,
  required bool pecahanKosong,
  required int tunaiTersimpan,
  List<Widget> extra = const [],
}) {
  return AlertDialog(
    title: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold)),
    titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    content: IsiDialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Table(
              columnWidths: const {
                0: FixedColumnWidth(64),
                1: FixedColumnWidth(18),
                2: FixedColumnWidth(52),
                3: FixedColumnWidth(58),
                4: FixedColumnWidth(18),
                5: FixedColumnWidth(80),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: anakPecahan,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, thickness: 0.6),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tunai admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 18,
                  child: Text('=', textAlign: TextAlign.center, style: _gaya),
                ),
                SizedBox(width: 80, child: _uangSel(total, tebal: true)),
              ],
            ),
            if (pecahanKosong)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Total tersimpan Rp ${Uang.angka(tunaiTersimpan)}. '
                  'Rincian pecahan belum ada; isi lalu simpan.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ...extra,
          ],
        ),
      ),
    ),
    actions: aksi,
  );
}

TableRow _barisPecahan({
  required Widget qty,
  required String jenis,
  required String label,
  required int hasil,
}) {
  Widget teks(String s, {TextAlign align = TextAlign.left}) {
    return Text(s, style: _gaya, textAlign: align);
  }

  return TableRow(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: qty,
      ),
      teks('×', align: TextAlign.center),
      teks(jenis),
      teks(label, align: TextAlign.right),
      teks('=', align: TextAlign.center),
      _uangSel(hasil),
    ],
  );
}

Widget _uangSel(int n, {bool tebal = false}) {
  final gaya = TextStyle(
    fontSize: 12,
    height: 1.15,
    color: Colors.black,
    fontWeight: tebal ? FontWeight.bold : FontWeight.normal,
  );
  return Row(
    children: [
      SizedBox(width: 22, child: Text('Rp', style: gaya)),
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
