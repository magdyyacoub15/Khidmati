import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class DeviceInfoUtil {
  static Future<String?> getUniqueDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final webBrowserInfo = await deviceInfo.webBrowserInfo;
        return "${webBrowserInfo.vendor}_${webBrowserInfo.userAgent}_${webBrowserInfo.hardwareConcurrency}";
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return "${androidInfo.model}_${androidInfo.id}_${androidInfo.fingerprint}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } on PlatformException catch (e) {
      debugPrint("PlatformException getting device ID: $e");
    } catch (e) {
      debugPrint("Error getting device ID: $e");
    }
    return null;
  }
}
