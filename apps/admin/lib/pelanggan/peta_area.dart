import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:obos_core/obos_core.dart';

import 'pelanggan.dart';

class PetaAreaKunjungan extends StatefulWidget {
  const PetaAreaKunjungan({
    super.key,
    required this.daftar,
    required this.onPilih,
    this.pilih,
  });

  final List<Pelanggan> daftar;
  final Pelanggan? pilih;
  final ValueChanged<Pelanggan> onPilih;

  @override
  State<PetaAreaKunjungan> createState() => _PetaAreaKunjunganState();
}

class _PetaAreaKunjunganState extends State<PetaAreaKunjungan> {
  final MapController _peta = MapController();
  final MenuController _menuRute = MenuController();
  final MenuController _menuHari = MenuController();
  final Set<String> _ruteMati = {};
  final Set<String> _hariMati = {};
  bool _sudahPas = false;

  static const _warnaHari = <String, Color>{
    'Senin': Color(0xFF1B75CB),
    'Selasa': Color(0xFF2E7D32),
    'Rabu': Color(0xFFE65100),
    'Kamis': Color(0xFF6A1B9A),
    'Jumat': Color(0xFF00838F),
    'Sabtu': Color(0xFF6D4C41),
    'Minggu': Color(0xFFC62828),
  };

  static const _palet = <Color>[
    Color(0xFF1B75CB),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFF6D4C41),
    Color(0xFFC62828),
    Color(0xFF1565C0),
    Color(0xFFAD1457),
    Color(0xFF455A64),
  ];

  bool _lokasiValid(Pelanggan p) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    if (lat.abs() > 90 || lng.abs() > 180) return false;
    return true;
  }

  List<Pelanggan> get _berkoordinat {
    return widget.daftar.where(_lokasiValid).toList();
  }

  List<String> get _rutePilihan {
    final set = <String>{
      for (final p in _berkoordinat)
        if (p.rute.trim().isNotEmpty) p.rute.trim(),
    };
    final list = set.toList()..sort();
    return list;
  }

  bool _ruteNyala(String rute) => !_ruteMati.contains(rute);

  List<String> get _ruteNyalaDaftar {
    return _rutePilihan.where(_ruteNyala).toList();
  }

  String get _labelRute {
    final semua = _rutePilihan;
    final nyala = _ruteNyalaDaftar;
    if (semua.isEmpty || nyala.length == semua.length) return 'Semua rute';
    if (nyala.isEmpty) return 'Tidak ada rute';
    if (nyala.length == 1) return nyala.first;
    return '${nyala.length} rute';
  }

  bool _hariNyala(String hari) => !_hariMati.contains(hari);

  List<String> get _hariNyalaDaftar {
    return Pelanggan.hariVisit.where(_hariNyala).toList();
  }

  String get _labelHari {
    final nyala = _hariNyalaDaftar;
    if (nyala.length == Pelanggan.hariVisit.length) return 'Semua hari';
    if (nyala.isEmpty) return 'Tidak ada hari';
    if (nyala.length == 1) return nyala.first;
    return '${nyala.length} hari';
  }

  List<Pelanggan> get _saring {
    return _berkoordinat.where((p) {
      final rute = p.rute.trim();
      if (rute.isNotEmpty && !_ruteNyala(rute)) return false;
      final hari = p.visit.trim();
      if (hari.isNotEmpty && !_hariNyala(hari)) return false;
      return p.aktif;
    }).toList();
  }

  bool get _warnaPerHari => _ruteNyalaDaftar.length == 1;

  List<_Kelompok> get _kelompok {
    final map = <String, List<Pelanggan>>{};
    for (final p in _saring) {
      final kunci = _warnaPerHari
          ? (p.visit.trim().isEmpty ? 'Tanpa hari' : p.visit.trim())
          : (p.rute.trim().isEmpty ? 'Tanpa rute' : p.rute.trim());
      map.putIfAbsent(kunci, () => []).add(p);
    }
    final kunci = map.keys.toList()..sort();
    return [
      for (var i = 0; i < kunci.length; i++)
        _Kelompok(
          nama: kunci[i],
          warna: _warnaKelompok(kunci[i], i),
          toko: map[kunci[i]]!,
        ),
    ];
  }

  Color _warnaKelompok(String nama, int indeks) {
    if (_warnaPerHari) return _warnaHari[nama] ?? Colors.blueGrey;
    return _palet[indeks % _palet.length];
  }

  List<LatLng> get _titik {
    return [
      for (final p in _saring) LatLng(p.latitude!, p.longitude!),
    ];
  }

  void _ikutiPilihan(Pelanggan? pilih) {
    final rute = pilih?.rute.trim() ?? '';
    if (rute.isNotEmpty) _ruteMati.remove(rute);
    final hari = pilih?.visit.trim() ?? '';
    if (hari.isNotEmpty) _hariMati.remove(hari);
  }

  void _aturRute(void Function() ubah) {
    final buka = _menuRute.isOpen;
    setState(() {
      ubah();
      _sudahPas = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (buka && !_menuRute.isOpen) _menuRute.open();
      _sesuaikan();
    });
  }

  void _aturHari(void Function() ubah) {
    final buka = _menuHari.isOpen;
    setState(() {
      ubah();
      _sudahPas = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (buka && !_menuHari.isOpen) _menuHari.open();
      _sesuaikan();
    });
  }

  @override
  void initState() {
    super.initState();
    _ikutiPilihan(widget.pilih);
  }

  @override
  void didUpdateWidget(PetaAreaKunjungan old) {
    super.didUpdateWidget(old);
    final gantiPilih = widget.pilih?.id != old.pilih?.id;
    if (gantiPilih) _ikutiPilihan(widget.pilih);
    if (gantiPilih || widget.daftar.length != old.daftar.length) {
      _sudahPas = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sesuaikan();
      });
    }
  }

  Widget _itemCekRute({
    required String label,
    required bool nilai,
    required VoidCallback onTap,
  }) {
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: onTap,
      child: Row(
        children: [
          Icon(
            nilai ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: nilai ? Tema.biru : Colors.black54,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.black)),
        ],
      ),
    );
  }

  void _sesuaikan() {
    if (_sudahPas) return;
    final titik = _titik;
    if (titik.isEmpty) return;
    try {
      if (titik.length == 1) {
        _peta.move(titik.first, 15);
      } else {
        _peta.fitCamera(
          CameraFit.coordinates(
            coordinates: titik,
            padding: const EdgeInsets.all(48),
            maxZoom: 16,
          ),
        );
      }
      _sudahPas = true;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final kelompok = _kelompok;
    final tanpaGps = widget.daftar.where((p) => p.aktif && !_lokasiValid(p)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Area kunjungan',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Tema.biru,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: MenuAnchor(
                      controller: _menuRute,
                      style: const MenuStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      menuChildren: [
                        _itemCekRute(
                          label: 'Semua rute',
                          nilai: _rutePilihan.isNotEmpty &&
                              _ruteNyalaDaftar.length == _rutePilihan.length,
                          onTap: () {
                            final hidupkan =
                                _ruteNyalaDaftar.length != _rutePilihan.length;
                            _aturRute(() {
                              _ruteMati.clear();
                              if (!hidupkan) _ruteMati.addAll(_rutePilihan);
                            });
                          },
                        ),
                        for (final r in _rutePilihan)
                          _itemCekRute(
                            label: r,
                            nilai: _ruteNyala(r),
                            onTap: () {
                              _aturRute(() {
                                if (_ruteNyala(r)) {
                                  _ruteMati.add(r);
                                } else {
                                  _ruteMati.remove(r);
                                }
                              });
                            },
                          ),
                      ],
                      builder: (context, controller, child) {
                        return InkWell(
                          onTap: () {
                            if (controller.isOpen) {
                              controller.close();
                            } else {
                              controller.open();
                            }
                          },
                          child: InputDecorator(
                            isEmpty: false,
                            decoration: InputDecoration(
                              labelText: 'Rute',
                              isDense: true,
                              suffixIcon: Icon(
                                controller.isOpen
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                            child: Text(
                              _labelRute,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: MenuAnchor(
                      controller: _menuHari,
                      style: const MenuStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      menuChildren: [
                        _itemCekRute(
                          label: 'Semua hari',
                          nilai: _hariNyalaDaftar.length == Pelanggan.hariVisit.length,
                          onTap: () {
                            final hidupkan =
                                _hariNyalaDaftar.length != Pelanggan.hariVisit.length;
                            _aturHari(() {
                              _hariMati.clear();
                              if (!hidupkan) _hariMati.addAll(Pelanggan.hariVisit);
                            });
                          },
                        ),
                        for (final h in Pelanggan.hariVisit)
                          _itemCekRute(
                            label: h,
                            nilai: _hariNyala(h),
                            onTap: () {
                              _aturHari(() {
                                if (_hariNyala(h)) {
                                  _hariMati.add(h);
                                } else {
                                  _hariMati.remove(h);
                                }
                              });
                            },
                          ),
                      ],
                      builder: (context, controller, child) {
                        return InkWell(
                          onTap: () {
                            if (controller.isOpen) {
                              controller.close();
                            } else {
                              controller.open();
                            }
                          },
                          child: InputDecorator(
                            isEmpty: false,
                            decoration: InputDecoration(
                              labelText: 'Hari',
                              isDense: true,
                              suffixIcon: Icon(
                                controller.isOpen
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                            child: Text(
                              _labelHari,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _saring.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(12, 16, 12, 0),
                  child: Text(
                    'Belum ada toko berkoordinat untuk saringan ini.',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                )
              : FlutterMap(
                  mapController: _peta,
                  options: MapOptions(
                    initialCenter: const LatLng(-6.2, 106.8),
                    initialZoom: 11,
                    onMapReady: _sesuaikan,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.obos.admin',
                    ),
                    PolygonLayer(
                      polygons: [
                        for (final k in kelompok)
                          if (_poligon(k.toko) case final poli?)
                            Polygon(
                              points: poli,
                              color: k.warna.withValues(alpha: 0.22),
                              borderColor: k.warna,
                              borderStrokeWidth: 2,
                            ),
                      ],
                    ),
                    CircleLayer(
                      circles: [
                        for (final k in kelompok)
                          if (_lingkaran(k.toko) case final ling?)
                            CircleMarker(
                              point: ling.pusat,
                              radius: ling.jari,
                              useRadiusInMeter: true,
                              color: k.warna.withValues(alpha: 0.22),
                              borderColor: k.warna,
                              borderStrokeWidth: 2,
                            ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        for (final k in kelompok)
                          for (final p in k.toko)
                            Marker(
                              point: LatLng(p.latitude!, p.longitude!),
                              width: widget.pilih?.id == p.id ? 36 : 28,
                              height: widget.pilih?.id == p.id ? 36 : 28,
                              child: GestureDetector(
                                onTap: () => widget.onPilih(p),
                                child: Tooltip(
                                  message: '${p.nama}\n${p.rute} · ${p.visit}',
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: k.warna,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: widget.pilih?.id == p.id
                                            ? Tema.kuning
                                            : Colors.white,
                                        width: widget.pilih?.id == p.id ? 3 : 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      '${p.urutan == 0 ? '' : p.urutan}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
        ),
        if (kelompok.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final k in kelompok)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: k.warna.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${k.nama} · ${k.toko.length} toko',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (tanpaGps > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '$tanpaGps toko aktif belum punya koordinat.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
    );
  }
}

class _Kelompok {
  const _Kelompok({
    required this.nama,
    required this.warna,
    required this.toko,
  });

  final String nama;
  final Color warna;
  final List<Pelanggan> toko;
}

class _Lingkaran {
  const _Lingkaran(this.pusat, this.jari);
  final LatLng pusat;
  final double jari;
}

List<LatLng> _titikUnik(List<Pelanggan> toko) {
  final unik = <String, LatLng>{};
  for (final p in toko) {
    final lat = p.latitude!;
    final lng = p.longitude!;
    unik['${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}'] = LatLng(lat, lng);
  }
  return unik.values.toList();
}

List<LatLng>? _poligon(List<Pelanggan> toko) {
  final titik = _titikUnik(toko);
  if (titik.length < 3) return null;
  final kulit = _lambung(titik);
  if (kulit.length < 3) return null;
  return _perlebar(kulit, 80);
}

_Lingkaran? _lingkaran(List<Pelanggan> toko) {
  final titik = _titikUnik(toko);
  if (titik.isEmpty || titik.length >= 3) return null;
  if (titik.length == 1) return _Lingkaran(titik.first, 120);
  final a = titik[0];
  final b = titik[1];
  final pusat = LatLng(
    (a.latitude + b.latitude) / 2,
    (a.longitude + b.longitude) / 2,
  );
  final jari = _meter(a, b) / 2 + 80;
  return _Lingkaran(pusat, jari < 120 ? 120 : jari);
}

List<LatLng> _lambung(List<LatLng> titik) {
  final pts = [...titik]..sort((a, b) {
    final c = a.longitude.compareTo(b.longitude);
    if (c != 0) return c;
    return a.latitude.compareTo(b.latitude);
  });
  double silang(LatLng o, LatLng a, LatLng b) {
    return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
        (a.latitude - o.latitude) * (b.longitude - o.longitude);
  }

  final bawah = <LatLng>[];
  for (final p in pts) {
    while (bawah.length >= 2 && silang(bawah[bawah.length - 2], bawah.last, p) <= 0) {
      bawah.removeLast();
    }
    bawah.add(p);
  }
  final atas = <LatLng>[];
  for (final p in pts.reversed) {
    while (atas.length >= 2 && silang(atas[atas.length - 2], atas.last, p) <= 0) {
      atas.removeLast();
    }
    atas.add(p);
  }
  bawah.removeLast();
  atas.removeLast();
  return [...bawah, ...atas];
}

List<LatLng> _perlebar(List<LatLng> kulit, double meter) {
  var lat = 0.0;
  var lng = 0.0;
  for (final p in kulit) {
    lat += p.latitude;
    lng += p.longitude;
  }
  final pusat = LatLng(lat / kulit.length, lng / kulit.length);
  return [
    for (final p in kulit) _dorong(pusat, p, meter),
  ];
}

LatLng _dorong(LatLng pusat, LatLng titik, double meter) {
  final dy = (titik.latitude - pusat.latitude) * 111320;
  final dx = (titik.longitude - pusat.longitude) *
      111320 *
      math.cos(pusat.latitude * math.pi / 180);
  final jarak = math.sqrt(dx * dx + dy * dy);
  if (jarak < 1) return titik;
  final faktor = (jarak + meter) / jarak;
  return LatLng(
    pusat.latitude + (titik.latitude - pusat.latitude) * faktor,
    pusat.longitude + (titik.longitude - pusat.longitude) * faktor,
  );
}

double _meter(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 6371000 * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}
