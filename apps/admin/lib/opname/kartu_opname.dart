import 'package:flutter/material.dart';
import 'package:obos_core/obos_core.dart';

import '../uang.dart';
import 'daftar_selisih_dialog.dart';
import 'opname_repo.dart';

class KartuOpname extends StatelessWidget {
  const KartuOpname({
    super.key,
    required this.data,
    required this.sibuk,
    required this.onMuat,
    required this.onKonfirmasi,
  });

  final RingkasOpname data;
  final bool sibuk;
  final Future<void> Function() onMuat;
  final Future<void> Function() onKonfirmasi;

  String get _status {
    if (!data.adaBuku) return 'Menunggu buku';
    if (data.skuFisik == 0) return 'Belum ada input';
    if (data.skuMinusBelum > 0) return 'Perlu konfirmasi admin';
    if (data.skuSelisih == 0) return 'Fisik cocok';
    return 'Selisih sudah diputuskan';
  }

  Color get _warnaStatus {
    if (!data.adaBuku || data.skuFisik == 0) return Colors.grey.shade700;
    if (data.skuMinusBelum > 0) return Colors.orange.shade800;
    if (data.skuSelisih == 0) return const Color(0xFF2E7D32);
    return Tema.seed;
  }

  String get _angkaSku {
    if (!data.adaBuku) return 'Scan masuk gudang membuka buku.';
    if (data.skuFisik == 0) {
      return 'Gudang belum mengirim opname untuk buku ini.';
    }
    if (data.skuSelisih == 0) return 'Tidak ada selisih stok.';
    final bagian = <String>[
      if (data.skuMinusBelum > 0)
        '${data.skuMinusBelum} dari ${data.skuSelisih} SKU'
      else
        '${data.skuSelisih} SKU',
    ];
    if (data.nilaiSelisih != 0) {
      bagian.add('Rp ${Uang.angka(data.nilaiSelisih.abs())}');
    }
    return bagian.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final bisaKonfirmasi =
        !sibuk && data.adaBuku && !data.ditutup && data.skuFisik > 0;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: FilledButton(
                        onPressed: sibuk || !data.adaBuku
                            ? null
                            : () {
                                if (data.skuMinusBelum > 0 && bisaKonfirmasi) {
                                  onKonfirmasi();
                                } else {
                                  bukaDaftarSelisih(
                                    context: context,
                                    data: data,
                                    onMuat: onMuat,
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(
                          data.skuMinusBelum > 0
                              ? 'Konfirmasi opname'
                              : 'Lihat opname',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Fisik gudang; qty sah dikunci admin jika ada selisih',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: sibuk || !data.adaBuku
                    ? null
                    : () => bukaDaftarSelisih(
                          context: context,
                          data: data,
                          onMuat: onMuat,
                        ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _warnaStatus,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _angkaSku,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
