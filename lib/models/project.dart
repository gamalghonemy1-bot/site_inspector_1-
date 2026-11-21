class Project {
  final String id, name;
  final double lat, lng, radiusM;
  Project({required this.id, required this.name, required this.lat, required this.lng, required this.radiusM});
  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'], name: j['name'],
        lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble(),
        radiusM: (j['radius_m'] as num).toDouble());
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lat': lat, 'lng': lng, 'radius_m': radiusM};
}
