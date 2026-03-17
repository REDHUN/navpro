import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService extends ChangeNotifier {
  static const String nordicUartServiceUuid =
      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String nordicUartRxCharacteristicUuid =
      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;

  // Track the last time we sent data for throttling
  DateTime? _lastSendTime;
  final Duration _throttleDuration = const Duration(seconds: 1);

  bool get isConnected => _connectedDevice != null;

  Future<void> scanForDevices(
      Function(List<ScanResult> results) onScanResults) async {
    FlutterBluePlus.scanResults.listen((results) {
      onScanResults(results);
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      _connectedDevice = device;
      
      // Discover services to find UART RX
      final services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == nordicUartServiceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                nordicUartRxCharacteristicUuid) {
              _rxCharacteristic = characteristic;
              print('Found Nordic UART RX characteristic');
              notifyListeners();
              return true;
            }
          }
        }
      }
      notifyListeners();
      return false;
    } catch (e) {
      print('BLE Connection error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _rxCharacteristic = null;
    notifyListeners();
  }

  Future<void> sendNavigationData({
    required double speed,
    required double distanceToTurn,
    required int maneuverCode,
    required int arrivalTime,
  }) async {
    // Throttle to 1 second
    final now = DateTime.now();
    if (_lastSendTime != null &&
        now.difference(_lastSendTime!) < _throttleDuration) {
      return;
    }
    _lastSendTime = now;

    // Construct payload for logging
    final Map<String, dynamic> payload = {
      "s": double.parse(speed.toStringAsFixed(1)),
      "d": distanceToTurn.toInt(),
      "i": maneuverCode,
      "e": arrivalTime,
    };
    final String jsonStr = jsonEncode(payload);

    print('--- NAV DATA ---');
    print('Speed: $speed km/h');
    print('Distance: ${distanceToTurn.toInt()}m');
    print('Maneuver: $maneuverCode');
    print('ETA: $arrivalTime (HHMM)');
    print('Raw JSON: $jsonStr');
    if (!isConnected) print('(BLE Not Connected - Data not sent)');
    print('----------------');

    if (_rxCharacteristic == null || !isConnected) return;

    try {
      final List<int> bytes = utf8.encode("$jsonStr\n");
      // Use standard write since some devices don't support WRITE_NO_RESPONSE
      await _rxCharacteristic!.write(bytes, withoutResponse: false);
    } catch (e) {
      print('Failed to send BLE data: $e');
    }
  }
}
