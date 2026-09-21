import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:obos_core/obos_core.dart';
import 'barang_bloc.dart';
import 'barang_event.dart';
import 'barang_state.dart';
import 'pesan_katalog.dart';

class DialogPesanKatalog extends StatelessWidget {
  const DialogPesanKatalog({super.key});

  static Future<void> show(BuildContext context) {
    final bloc = context.read<BarangBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: bloc,
        child: const DialogPesanKatalog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BarangBloc, BarangState>(
      builder: (context, state) {
        final notices = state is BarangSiap ? state.notices : const <PesanKatalog>[];
        final adaBelum = notices.any((item) => !item.sudahDibaca);

        return AlertDialog(
          title: const Text(
            'Pembaruan katalog',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: IsiDialog(
            width: double.maxFinite,
            child: notices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Belum ada pesan pembaruan barang.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  )
                : DaftarGulirDialog(
                    maxTinggi: 360,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: notices.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final pesan = notices[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            pesan.sudahDibaca
                                ? Icons.mark_email_read_outlined
                                : Icons.mark_email_unread_outlined,
                            color: Tema.seed,
                          ),
                          title: Text(
                            pesan.judul,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: pesan.sudahDibaca
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            pesan.isi,
                            style: TextStyle(
                              fontSize: 12,
                              color: pesan.sudahDibaca
                                  ? Colors.grey
                                  : Colors.black87,
                            ),
                          ),
                          onTap: pesan.sudahDibaca
                              ? null
                              : () {
                                  context.read<BarangBloc>().add(
                                        TandaiPesan(pesan.id),
                                      );
                                },
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            if (adaBelum)
              TextButton(
                onPressed: () {
                  context.read<BarangBloc>().add(TandaiSemuaPesan());
                },
                child: const Text('Tandai semua dibaca'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }
}
