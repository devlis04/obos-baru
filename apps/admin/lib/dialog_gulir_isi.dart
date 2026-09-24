import 'package:flutter/material.dart';

/// Dialog tabel: judul, header, dan baris jumlah tetap; isi digulir.
class DialogGulirIsi extends StatelessWidget {
  const DialogGulirIsi({
    super.key,
    required this.lebar,
    required this.judul,
    required this.kepala,
    required this.jumlah,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.tinggiBaris = 40,
    this.tinggiKepala = 36,
  });

  final double lebar;
  final Widget judul;
  final Widget kepala;
  final Widget jumlah;
  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double tinggiBaris;
  final double tinggiKepala;

  @override
  Widget build(BuildContext context) {
    final layar = MediaQuery.sizeOf(context);
    final maxIsi = layar.height * 0.55;
    final tinggiDaftar = (itemCount * tinggiBaris).clamp(0.0, maxIsi);
    const padSamping = 16.0;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: layar.width - 48,
          maxHeight: layar.height - 48,
        ),
        child: SizedBox(
          width: lebar + padSamping * 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: judul,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: padSamping),
                child: SizedBox(height: tinggiKepala, child: kepala),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: padSamping),
                  child: SizedBox(
                    height: tinggiDaftar,
                    child: Scrollbar(
                      controller: controller,
                      thumbVisibility: itemCount * tinggiBaris > maxIsi,
                      child: ListView.builder(
                        controller: controller,
                        primary: false,
                        itemExtent: tinggiBaris,
                        itemCount: itemCount,
                        itemBuilder: itemBuilder,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: padSamping),
                child: jumlah,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
