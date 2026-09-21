import 'package:flutter/material.dart';

class Uang {
  static String angka(int nominal) {
    return nominal.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  static String rp(int nominal) => 'Rp ${angka(nominal)}';
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
        Text('Rp', style: gaya),
        const SizedBox(width: 6),
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
