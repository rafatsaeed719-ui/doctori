import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../common/map_widgets.dart';
import '../core/l10n.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'doctor_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  int? _specialty;
  int? _governorate;
  bool _acceptingOnly = false;
  double? _minRating;
  Position? _here;
  bool _showMap = false;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = const [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await rpcList('search_doctors', {
        'p_query': _query.text.trim().isEmpty ? null : _query.text.trim(),
        'p_specialty': _specialty,
        'p_governorate': _governorate,
        'p_lat': _here?.latitude,
        'p_lng': _here?.longitude,
        'p_accepting_only': _acceptingOnly,
        'p_min_rating': _minRating,
        'p_limit': 40,
      });
      if (mounted) setState(() => _results = res);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleNearMe() async {
    if (_here != null) {
      setState(() => _here = null);
      return _search();
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) showMessage(context, tr('شغّل خدمة الموقع (GPS) من إعدادات الموبايل.', 'Turn on location services.'), error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          showMessage(context, tr('لم يتم السماح باستخدام الموقع. يمكنك البحث بالمحافظة بدلاً من ذلك.',
              'Location permission denied. You can search by governorate instead.'), error: true);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      setState(() => _here = pos);
      await _search();
    } catch (_) {
      if (mounted) showMessage(context, tr('تعذر تحديد موقعك. حاول مرة أخرى.', 'Could not get your location.'), error: true);
    }
  }

  Future<void> _openFilters() async {
    int? spec = _specialty;
    int? gov = _governorate;
    bool accepting = _acceptingOnly;
    double? rating = _minRating;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('تصفية النتائج', 'Filters'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: spec,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('التخصص', 'Specialty')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(tr('كل التخصصات', 'All specialties'))),
                for (final s in Lookups.specialties)
                  DropdownMenuItem<int?>(value: s['id'] as int, child: Text(trField(s, 'name'))),
              ],
              onChanged: (v) => setS(() => spec = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: gov,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('المحافظة', 'Governorate')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(tr('كل المحافظات', 'All governorates'))),
                for (final g in Lookups.governorates)
                  DropdownMenuItem<int?>(value: g['id'] as int, child: Text(trField(g, 'name'))),
              ],
              onChanged: (v) => setS(() => gov = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double?>(
              initialValue: rating,
              decoration: InputDecoration(labelText: tr('التقييم', 'Rating')),
              items: [
                DropdownMenuItem<double?>(value: null, child: Text(tr('أي تقييم', 'Any rating'))),
                DropdownMenuItem<double?>(value: 3, child: Text(tr('3 نجوم فأكثر', '3 stars and up'))),
                DropdownMenuItem<double?>(value: 4, child: Text(tr('4 نجوم فأكثر', '4 stars and up'))),
              ],
              onChanged: (v) => setS(() => rating = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: accepting,
              onChanged: (v) => setS(() => accepting = v),
              title: Text(tr('يستقبل مرضى جدد فقط', 'Accepting new patients only')),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('عرض النتائج', 'Show results'))),
            TextButton(
              onPressed: () => setS(() {
                spec = null;
                gov = null;
                accepting = false;
                rating = null;
              }),
              child: Text(tr('مسح التصفية', 'Clear filters')),
            ),
          ]),
        ),
      ),
    );
    if (apply == true) {
      setState(() {
        _specialty = spec;
        _governorate = gov;
        _acceptingOnly = accepting;
        _minRating = rating;
      });
      _search();
    }
  }

  int get _activeFilters =>
      [_specialty != null, _governorate != null, _acceptingOnly, _minRating != null].where((x) => x).length;

  void _openDoctor(Map<String, dynamic> d) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DoctorDetailsScreen(doctorId: d['doctor_id'] as String)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('ابحث عن طبيب', 'Find a doctor')),
        actions: [
          IconButton(
            tooltip: _showMap ? tr('عرض القائمة', 'List view') : tr('عرض الخريطة', 'Map view'),
            icon: Icon(_showMap ? Icons.list : Icons.map_outlined),
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: tr('اسم الطبيب أو التخصص', 'Doctor name or specialty'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close), onPressed: () {
                      _query.clear();
                      _search();
                    }),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            FilterChip(
              avatar: const Icon(Icons.my_location, size: 18),
              label: Text(tr('الأقرب لي', 'Near me')),
              selected: _here != null,
              onSelected: (_) => _toggleNearMe(),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: Text(_activeFilters == 0 ? tr('تصفية', 'Filters') : '${tr('تصفية', 'Filters')} ($_activeFilters)'),
              onPressed: _openFilters,
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text(tr('يستقبل مرضى جدد', 'Accepting')),
              selected: _acceptingOnly,
              onSelected: (v) {
                setState(() => _acceptingOnly = v);
                _search();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _search)
                  : _results.isEmpty
                      ? EmptyView(
                          icon: Icons.person_search,
                          title: tr('لا يوجد أطباء مطابقون', 'No matching doctors'),
                          subtitle: tr('جرّب تغيير التخصص أو المحافظة أو مسح التصفية.', 'Try another specialty or area, or clear filters.'),
                        )
                      : _showMap
                          ? _buildMap(cs)
                          : RefreshList(
                              onRefresh: _search,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: [for (final d in _results) _DoctorCard(d: d, onTap: () => _openDoctor(d))],
                            ),
        ),
      ]),
    );
  }

  Widget _buildMap(ColorScheme cs) {
    final pts = _results.where((d) => d['lat'] != null && d['lng'] != null).toList();
    final center = _here != null
        ? LatLng(_here!.latitude, _here!.longitude)
        : pts.isNotEmpty
            ? LatLng((pts.first['lat'] as num).toDouble(), (pts.first['lng'] as num).toDouble())
            : cairo;
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        osmTiles(),
        MarkerLayer(markers: [
          if (_here != null)
            Marker(
              point: LatLng(_here!.latitude, _here!.longitude),
              child: Icon(Icons.my_location, color: cs.tertiary, size: 28),
            ),
          for (final d in pts)
            Marker(
              point: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
              width: 44,
              height: 44,
              child: GestureDetector(
                onTap: () => _openDoctor(d),
                child: Icon(Icons.location_on, color: cs.primary, size: 44),
              ),
            ),
        ]),
        osmAttribution(),
      ],
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.d, required this.onTap});
  final Map<String, dynamic> d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rating = (d['rating_avg'] as num?)?.toDouble() ?? 0;
    final count = d['rating_count'] as int? ?? 0;
    final dist = (d['distance_km'] as num?)?.toDouble();
    final place = [d['city_ar'], d['governorate_ar']].whereType<String>().where((s) => s.isNotEmpty).join('، ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: cs.primaryContainer,
                child: Text((d['full_name'] as String? ?? '?').characters.first,
                    style: TextStyle(fontSize: 22, color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr('د.', 'Dr.')} ${d['full_name'] ?? ''}', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text([trField(d, 'specialty'), d['title']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      style: tt.bodyMedium?.copyWith(color: cs.primary)),
                  const SizedBox(height: 6),
                  if (place.isNotEmpty || d['clinic_name'] != null)
                    Row(children: [
                      Icon(Icons.place_outlined, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(place.isNotEmpty ? place : (d['clinic_name'] ?? ''),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      if (dist != null)
                        Text(tr('${dist.toStringAsFixed(1)} كم', '${dist.toStringAsFixed(1)} km'),
                            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (count > 0)
                      StatusChip('★ ${rating.toStringAsFixed(1)} ($count)', color: Colors.amber.shade800),
                    StatusChip(
                      d['accepting_new'] == true ? tr('يستقبل مرضى جدد', 'Accepting patients') : tr('لا يستقبل حالياً', 'Not accepting'),
                      color: d['accepting_new'] == true ? Colors.green.shade700 : cs.outline,
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
