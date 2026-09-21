class BukuHari {
  const BukuHari({
    required this.id,
    required this.tanggal,
    required this.ditutup,
    required this.hidup,
  });

  final int id;
  final DateTime tanggal;
  final bool ditutup;
  final bool hidup;

  static BukuHari? dari(dynamic hasil) {
    Map<String, dynamic>? m;
    if (hasil is Map) {
      m = Map<String, dynamic>.from(hasil);
    } else if (hasil is List && hasil.isNotEmpty && hasil.first is Map) {
      m = Map<String, dynamic>.from(hasil.first as Map);
    }
    if (m == null) return null;
    final id = (m['id'] as num?)?.toInt();
    final raw = m['tanggal']?.toString() ?? '';
    final tgl = DateTime.tryParse(raw);
    if (id == null || tgl == null) return null;
    return BukuHari(
      id: id,
      tanggal: DateTime(tgl.year, tgl.month, tgl.day),
      ditutup: m['ditutup'] == true,
      hidup: m['hidup'] == true,
    );
  }
}
