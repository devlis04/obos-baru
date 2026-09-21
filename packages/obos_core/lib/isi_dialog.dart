import 'package:flutter/material.dart';

/// Tinggi kartu [AlertDialog] mengikuti anak, bukan sisa layar.
class IsiDialog extends StatelessWidget {
  const IsiDialog({super.key, this.width, required this.child});

  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget isi = child;
    if (width != null) {
      isi = SizedBox(width: width, child: isi);
    }
    return Align(
      alignment: Alignment.topLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: isi,
    );
  }
}

/// Daftar di dalam dialog: tinggi isi, gulir hanya jika lewat [maxTinggi] / [faktor].
class DaftarGulirDialog extends StatelessWidget {
  const DaftarGulirDialog({
    super.key,
    this.faktor = 0.32,
    this.maxTinggi,
    required this.child,
  });

  final double faktor;
  final double? maxTinggi;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final batas = maxTinggi ?? MediaQuery.sizeOf(context).height * faktor;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: batas),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: child,
      ),
    );
  }
}
