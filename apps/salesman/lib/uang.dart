import 'package:flutter/material.dart';

class Uang {
  static int dari(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String angka(int nominal) {
    final tanda = nominal < 0 ? '-' : '';
    final n = nominal.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return '$tanda$n';
  }

  static String rp(int nominal) => angka(nominal);
}

class TeksRp extends StatelessWidget {
  const TeksRp(this.nilai, {super.key, this.style});

  final int nilai;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final gaya = style ?? DefaultTextStyle.of(context).style;
    return Row(
      children: [
        Expanded(
          child: Text(
            Uang.angka(nilai),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: gaya.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
