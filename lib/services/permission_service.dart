import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.notification,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        debugPrint('Permission ${permission.toString()} was denied: $status');
      }
    });

    return allGranted;
  }

  Future<bool> hasLocationPermission() async {
    return await Permission.location.isGranted;
  }

  Future<bool> hasBluetoothPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Check for Bluetooth Scan & Connect (Android 12+)
      // Note: On older Android, location permission is used for scanning.
      bool scan = await Permission.bluetoothScan.isGranted;
      bool connect = await Permission.bluetoothConnect.isGranted;
      return scan && connect;
    }
    return await Permission.bluetooth.isGranted;
  }
}
