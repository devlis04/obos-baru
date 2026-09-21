import 'package:flutter/material.dart';

import 'absensi_repo.dart';

class KartuAbsensi extends StatelessWidget {
  const KartuAbsensi({
    super.key,
    required this.pengirim,
    required this.gudang,
  });

  final List<OrangAbsensi> pengirim;
  final List<OrangAbsensi> gudang;

  static const _kosongPengirim = [
    OrangAbsensi(nama: '—', peran: 'pengirim'),
  ];
  static const _kosongGudang = [
    OrangAbsensi(nama: '—', peran: 'gudang'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _grup(
                      'Pengirim',
                      pengirim.isEmpty ? _kosongPengirim : pengirim,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 18,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                    _grup(
                      'Gudang',
                      gudang.isEmpty ? _kosongGudang : gudang,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grup(String judul, List<OrangAbsensi> orang) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          judul,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        const SizedBox(width: 10),
        for (final o in orang) _orang(o),
      ],
    );
  }

  Widget _orang(OrangAbsensi o) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Tooltip(
        message: o.nama == '—' ? '' : o.keterangan,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: o.warnaTitik,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              o.nama,
              style: TextStyle(
                fontSize: 14,
                height: 1,
                color: o.warnaNama,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
