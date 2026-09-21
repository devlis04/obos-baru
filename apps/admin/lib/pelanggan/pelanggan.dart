class Pelanggan {
  const Pelanggan({
    required this.id,
    required this.nama,
    this.rute = '',
    this.visit = '',
    this.urutan = 0,
    this.latitude,
    this.longitude,
    this.aktif = true,
  });

  final String id;
  final String nama;
  final String rute;
  final String visit;
  final int urutan;
  final double? latitude;
  final double? longitude;
  final bool aktif;

  static const hariVisit = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  Map<String, dynamic> keSimpan() => {
        'id_pelanggan': id,
        'nama_pelanggan': nama.trim().toUpperCase(),
        'rute': rute.trim(),
        'visit': visit.trim(),
        'urutan': urutan,
        'latitude': latitude,
        'longitude': longitude,
        'aktif': aktif,
      };

  factory Pelanggan.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim().replaceAll(',', '.'));
    }

    return Pelanggan(
      id: json['id_pelanggan']?.toString() ?? '',
      nama: (json['nama_pelanggan']?.toString() ?? '').toUpperCase(),
      rute: json['rute']?.toString() ?? '',
      visit: json['visit']?.toString() ?? '',
      urutan: (json['urutan'] as num?)?.toInt() ?? 0,
      latitude: d(json['latitude']),
      longitude: d(json['longitude']),
      aktif: json['aktif'] != false,
    );
  }
}
