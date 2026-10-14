import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/widgets.dart';

final cairo = LatLng(30.0444, 31.2357);

/// OpenStreetMap tiles (free, no API key). Before a large public launch,
/// switch to a commercial tile provider per the OSM tile usage policy.
TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: AppConfig.appPackage,
    );

Widget osmAttribution() => RichAttributionWidget(
      attributions: [
        TextSourceAttribution('OpenStreetMap contributors',
            onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
      ],
    );

/// Opens Google Maps (app or browser) with driving directions to a point.
Future<void> openDirections(BuildContext context, double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showMessage(context, tr('تعذر فتح تطبيق الخرائط', 'Could not open maps'), error: true);
  }
}

/// Full-screen picker: tap the map or use current location, then confirm.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});
  final LatLng? initial;
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  Future<void> _useMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) showMessage(context, tr('لم يتم السماح باستخدام الموقع', 'Location permission denied'), error: true);
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      final ll = LatLng(p.latitude, p.longitude);
      setState(() => _picked = ll);
      _map.move(ll, 17);
    } catch (_) {
      if (mounted) showMessage(context, tr('تعذر تحديد موقعك. شغّل GPS وحاول مرة أخرى.', 'Could not get location. Turn on GPS.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('موقع العيادة', 'Clinic location'))),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.initial ?? cairo,
            initialZoom: widget.initial != null ? 16 : 11,
            onTap: (_, point) => setState(() => _picked = point),
          ),
          children: [
            osmTiles(),
            if (_picked != null)
              MarkerLayer(markers: [
                Marker(point: _picked!, width: 48, height: 48,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on, color: cs.error, size: 48)),
              ]),
            osmAttribution(),
          ],
        ),
        PositionedDirectional(
          top: 12,
          start: 12,
          end: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr('اضغط على مكان العيادة بالضبط على الخريطة، أو استخدم موقعك الحالي لو أنت في العيادة.',
                  'Tap the exact clinic spot on the map, or use your current location if you are at the clinic.')),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _useMyLocation,
                icon: const Icon(Icons.my_location),
                label: Text(tr('موقعي الحالي', 'My location')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
                child: Text(tr('تأكيد الموقع', 'Confirm')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
