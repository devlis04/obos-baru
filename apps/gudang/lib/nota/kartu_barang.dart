import 'package:flutter/material.dart';

import '../barang/barang.dart';
import '../rumus_sederhana.dart';
import 'package:obos_core/obos_core.dart';
import 'transaksi_helper.dart';

class KartuBarang extends StatelessWidget {
  const KartuBarang({
    super.key,
    required this.barang,
    required this.qtyInput,
    required this.qtyGrup,
    required this.hargaDinamis,
    this.onTap,
    this.onLongPress,
  });

  final Barang barang;
  final int qtyInput;
  final int qtyGrup;
  final int hargaDinamis;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final diskon = hargaDinamis < barang.hargaJual;
    final strata = barang.strataAktif;
    final adaStrata = strata.isNotEmpty;
    final grup = barang.idGrup.trim();
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: Tema.sudut,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      barang.nama,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _chip(
                      'Sisa stok ${teksQty(barang.stok)}',
                      Icons.inventory_2_outlined,
                      warna: barang.stokHabis ? Colors.red : Tema.seed,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (adaStrata)
                          _chip(
                            'Strata ${strata.map((s) => s.minimal).join('/')}',
                            Icons.stacked_line_chart_outlined,
                          )
                        else
                          _chip('Tanpa strata', Icons.remove_circle_outline),
                        if (grup.isNotEmpty && qtyGrup > 0)
                          _chip(
                            'Jumlah grup $qtyGrup',
                            Icons.shopping_bag_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (diskon) ...[
                          Text(
                            TransaksiHelper.rp(barang.hargaJual),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          TransaksiHelper.rp(hargaDinamis),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: diskon
                                ? Colors.green.shade700
                                : Colors.black87,
                          ),
                        ),
                        if (diskon)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              'harga strata',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (qtyInput > 0 || barang.hargaBeli > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (qtyInput > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(Tema.pxSudut),
                            border: Border.all(color: Tema.seed, width: 1.2),
                          ),
                          child: Text(
                            '$qtyInput',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Tema.seed,
                            ),
                          ),
                        ),
                      if (barang.hargaBeli > 0) ...[
                        if (qtyInput > 0) const SizedBox(height: 6),
                        Text(
                          TransaksiHelper.rasioItem(
                            hargaJual: hargaDinamis,
                            hargaBeli: barang.hargaBeli,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Tema.seed,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _chip(String label, IconData icon, {Color warna = Tema.seed}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Tema.pxSudut),
        border: Border.all(color: warna, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: warna),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }
}
