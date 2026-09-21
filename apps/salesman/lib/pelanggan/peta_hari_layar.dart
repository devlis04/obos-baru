import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:obos_core/obos_core.dart';

import '../buka_maps.dart';
import 'pelanggan.dart';

class PetaHariLayar extends StatefulWidget {
  const PetaHariLayar({
    super.key,
    required this.hari,
    required this.toko,
  });

  final String hari;
  final List<Pelanggan> toko;

  @override
  State<PetaHariLayar> createState() => _PetaHariLayarState();
}

class _PetaHariLayarState extends State<PetaHariLayar> {
  final MapController _peta = MapController();
  bool _sudahPas = false;

  List<Pelanggan> get _tokoBerlokasi {
    return widget.toko
        .where(
          (item) =>
              item.latitude != null &&
              item.longitude != null &&
              item.latitude != 0 &&
              item.longitude != 0,
        )
        .toList();
  }

  List<LatLng> get _titik {
    return _tokoBerlokasi
        .map((item) => LatLng(item.latitude!, item.longitude!))
        .toList();
  }

  LatLng get _pusat {
    final titik = _titik;
    if (titik.isEmpty) return const LatLng(-6.2, 106.8);
    var lat = 0.0;
    var lng = 0.0;
    for (final p in titik) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / titik.length, lng / titik.length);
  }

  void _sesuaikanPeta() {
    if (_sudahPas) return;
    final titik = _titik;
    if (titik.isEmpty) return;
    _sudahPas = true;
    if (titik.length == 1) {
      _peta.move(titik.first, 15);
      return;
    }
    _peta.fitCamera(
      CameraFit.coordinates(
        coordinates: titik,
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      ),
    );
  }

  Future<void> _bukaMapsToko(Pelanggan item) {
    return bukaMapsToko(
      context: context,
      nama: item.nama,
      latitude: item.latitude,
      longitude: item.longitude,
    );
  }

  void _tampilkanToko(Pelanggan item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nama,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kode: ${item.id}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _bukaMapsToko(item);
                    },
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Buka di Maps'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final toko = _tokoBerlokasi;
    final tanpaGps = widget.toko.length - toko.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Peta ${widget.hari}'),
      ),
      body: toko.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Belum ada titik lokasi toko untuk hari ini. Pastikan toko punya koordinat GPS.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                if (tanpaGps > 0)
                  Material(
                    color: Colors.yellow.shade700,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        '$tanpaGps toko tidak ditampilkan karena belum ada koordinat GPS.',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: FlutterMap(
                    mapController: _peta,
                    options: MapOptions(
                      initialCenter: _pusat,
                      initialZoom: 13,
                      onMapReady: _sesuaikanPeta,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.obos.salesman',
                      ),
                      MarkerLayer(
                        markers: [
                          for (var i = 0; i < toko.length; i++)
                            Marker(
                              point: LatLng(
                                toko[i].latitude!,
                                toko[i].longitude!,
                              ),
                              width: 40,
                              height: 40,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                onTap: () => _tampilkanToko(toko[i]),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Tema.seed,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    '${toko[i].urutan ?? (i + 1)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
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
              ],
            ),
    );
  }
}
