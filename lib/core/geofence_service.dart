import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/project.dart';

class GeoResult {
  final bool allowed;
  final String message;
  final Position? position;
  final double? distance;
  GeoResult(this.allowed, this.message, {this.position, this.distance});
}

class GeofenceService {
  /// يتحقق أن المشرف داخل نطاق المشروع. يرفض المواقع الوهمية (Mock Location).
  static Future<GeoResult> check(Project p) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return GeoResult(false, 'فعّل خدمة الموقع (GPS) من إعدادات الهاتف.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return GeoResult(false, 'يجب السماح للتطبيق باستخدام الموقع.');
    }
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 20),
    );
    if (pos.isMocked) {
      return GeoResult(false, 'تم رصد موقع وهمي (Mock Location). أوقفه وأعد المحاولة.', position: pos);
    }
    final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, p.lat, p.lng);
    final tolerance = min(pos.accuracy, 30.0); // هامش دقة الـ GPS
    if (d <= p.radiusM + tolerance) {
      return GeoResult(true, 'داخل النطاق (${d.round()} م)', position: pos, distance: d);
    }
    return GeoResult(false, 'أنت خارج نطاق الموقع. المسافة ${d.round()} م والمسموح ${p.radiusM.round()} م.',
        position: pos, distance: d);
  }
}
