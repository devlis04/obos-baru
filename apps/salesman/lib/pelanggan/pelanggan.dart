class Pelanggan {
  const Pelanggan({
    required this.id,
    required this.nama,
    this.rute,
    this.visit,
    this.urutan,
    this.latitude,
    this.longitude,
    this.waktuMasuk,
    this.waktuKeluar,
  });

  final String id;
  final String nama;
  final String? rute;
  final String? visit;
  final int? urutan;
  final double? latitude;
  final double? longitude;
  final DateTime? waktuMasuk;
  final DateTime? waktuKeluar;

  bool get selesaiMingguIni => MingguKunjungan.diMingguIni(waktuKeluar);
  factory Pelanggan.fromJson(Map<String, dynamic> json) {
    return Pelanggan(
      id: json['id_pelanggan']?.toString() ?? '',
      nama: (json['nama_pelanggan']?.toString() ?? '').toUpperCase(),
      rute: json['rute']?.toString(),
      visit: json['visit']?.toString(),
      urutan: (json['urutan'] as num?)?.toInt(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      waktuMasuk: parseWaktu(json['waktu_masuk']),
      waktuKeluar: parseWaktu(json['waktu_keluar']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_pelanggan': id,
        'nama_pelanggan': nama,
        'rute': rute,
        'visit': visit,
        'urutan': urutan,
        'latitude': latitude,
        'longitude': longitude,
        'waktu_masuk': waktuMasuk?.toIso8601String(),
        'waktu_keluar': waktuKeluar?.toIso8601String(),
      };

  Pelanggan salin({
    DateTime? waktuMasuk,
    DateTime? waktuKeluar,
    int? urutan,
  }) {
    return Pelanggan(
      id: id,
      nama: nama,
      rute: rute,
      visit: visit,
      urutan: urutan ?? this.urutan,
      latitude: latitude,
      longitude: longitude,
      waktuMasuk: waktuMasuk ?? this.waktuMasuk,
      waktuKeluar: waktuKeluar ?? this.waktuKeluar,
    );
  }

  static DateTime? parseWaktu(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

class MingguKunjungan {
  static DateTime senin() {
    final now = DateTime.now();
    final senin = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(senin.year, senin.month, senin.day);
  }

  static DateTime minggu() => senin().add(const Duration(days: 6));

  static DateTime seninSepuluhMinggu() =>
      senin().subtract(const Duration(days: 7 * 9));

  static DateTime hari(DateTime w) => DateTime(w.year, w.month, w.day);

  static DateTime seninDari(DateTime w) {
    final h = hari(w);
    return h.subtract(Duration(days: h.weekday - 1));
  }

  static String namaHari(DateTime w) {
    const daftar = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    final i = w.weekday;
    return (i >= 1 && i <= 7) ? daftar[i - 1] : 'Senin';
  }

  static String tampil(DateTime w) {
    final m = w.month.toString().padLeft(2, '0');
    final d = w.day.toString().padLeft(2, '0');
    return '$d/$m/${w.year}';
  }

  static String tampilPendek(DateTime w) {
    final m = w.month.toString().padLeft(2, '0');
    return '${w.day}/$m';
  }

  static bool samaHari(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool diMingguIni(DateTime? waktu) {
    if (waktu == null) return false;
    final lokal = waktu.isUtc ? waktu.toLocal() : waktu;
    final hari = DateTime(lokal.year, lokal.month, lokal.day);
    return !hari.isBefore(senin()) && !hari.isAfter(minggu());
  }

  static String iso(DateTime hari) {
    final m = hari.month.toString().padLeft(2, '0');
    final d = hari.day.toString().padLeft(2, '0');
    return '${hari.year}-$m-$d';
  }

  static String chip(DateTime? waktu) {
    if (!diMingguIni(waktu)) return '-';
    final lokal = waktu!.isUtc ? waktu.toLocal() : waktu;
    final bulan = lokal.month.toString().padLeft(2, '0');
    final jam = lokal.hour.toString().padLeft(2, '0');
    final menit = lokal.minute.toString().padLeft(2, '0');
    return '${lokal.day}/$bulan $jam:$menit';
  }

  static String chipKeluar(DateTime? masuk, DateTime? keluar) {
    if (!diMingguIni(keluar)) return '-';
    if (masuk != null && keluar != null && keluar.isBefore(masuk)) return '-';
    return chip(keluar);
  }
}
