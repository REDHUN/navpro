import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:dio/dio.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import '../appconstant.dart';

class BleService extends ChangeNotifier {
  // Service UUID
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";

  // Characteristic UUIDs
  static const String charConfigUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String charRouteUuid = "beb5483f-36e1-4688-b7f5-ea07361b26a8";
  static const String charTileReqUuid = "beb54840-36e1-4688-b7f5-ea07361b26a8";
  static const String charTileDataUuid = "beb54841-36e1-4688-b7f5-ea07361b26a8";
  static const String charLocationUuid = "beb54842-36e1-4688-b7f5-ea07361b26a8";

  // Retain old UART UUIDs for backwards compatibility or fallback if needed
  static const String nordicUartServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String nordicUartRxCharacteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";

  BluetoothDevice? _connectedDevice;

  // Active characteristics
  BluetoothCharacteristic? _configCharacteristic;
  BluetoothCharacteristic? _routeCharacteristic;
  BluetoothCharacteristic? _tileReqCharacteristic;
  BluetoothCharacteristic? _tileDataCharacteristic;
  BluetoothCharacteristic? _locationCharacteristic;

  // Fallback UART characteristic
  BluetoothCharacteristic? _rxCharacteristic;

  StreamSubscription<List<int>>? _tileReqSubscription;

  // Google 2D Tiles API Session Management
  String? _sessionToken;
  final Dio _dio = Dio();

  // Throughput Tracking & Simulation State
  Timer? _throughputTimer;
  int _bytesSentCount = 0;
  int _tilesSentCount = 0;

  // Current Route List for Location/Index calculations
  List<List<double>> _currentRoute = [];

  // Track the last time we sent data for throttling
  DateTime? _lastSendTime;
  final Duration _throttleDuration = const Duration(seconds: 1);

  bool get isConnected => _connectedDevice != null;

  Future<void> scanForDevices(
      Function(List<ScanResult> results) onScanResults) async {
    try {
      // Check if bluetooth is on
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is turned off. Please turn it on to scan.');
      }

      FlutterBluePlus.scanResults.listen((results) {
        onScanResults(results);
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    } catch (e) {
      print('BLE Scan error: $e');
      rethrow;
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      _connectedDevice = device;

      // Negotiate maximum MTU size (up to 251)
      try {
        await device.requestMtu(251);
        print('Successfully negotiated MTU: ${device.mtuNow}');
      } catch (e) {
        print('MTU negotiation failed: $e');
      }

      // Discover services to identify target characteristics
      final services = await device.discoverServices();
      bool foundUpgradedService = false;
      bool foundLegacyService = false;

      for (var service in services) {
        final sUuid = service.uuid.toString().toLowerCase();
        if (sUuid == serviceUuid) {
          foundUpgradedService = true;
          for (var characteristic in service.characteristics) {
            final cUuid = characteristic.uuid.toString().toLowerCase();
            if (cUuid == charConfigUuid) {
              _configCharacteristic = characteristic;
            } else if (cUuid == charRouteUuid) {
              _routeCharacteristic = characteristic;
            } else if (cUuid == charTileReqUuid) {
              _tileReqCharacteristic = characteristic;
            } else if (cUuid == charTileDataUuid) {
              _tileDataCharacteristic = characteristic;
            } else if (cUuid == charLocationUuid) {
              _locationCharacteristic = characteristic;
            }
          }
        } else if (sUuid == nordicUartServiceUuid.toLowerCase()) {
          foundLegacyService = true;
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                nordicUartRxCharacteristicUuid.toLowerCase()) {
              _rxCharacteristic = characteristic;
            }
          }
        }
      }

      // Set up listeners for the upgraded protocol
      if (foundUpgradedService &&
          _configCharacteristic != null &&
          _routeCharacteristic != null &&
          _tileReqCharacteristic != null &&
          _tileDataCharacteristic != null &&
          _locationCharacteristic != null) {
        
        print('Successfully found all upgraded BLE characteristics.');

        // Subscribe to Tile Request notifications
        await _tileReqCharacteristic!.setNotifyValue(true);
        _tileReqSubscription?.cancel();
        _tileReqSubscription = _tileReqCharacteristic!.onValueReceived.listen((value) {
          final req = utf8.decode(value).trim();
          _handleTileRequest(req);
        });

        // Initialize throughput stat tracker
        _startThroughputTimer();

        // Send READY signal
        await sendReadySignal();

        notifyListeners();
        return true;
      } else if (foundLegacyService && _rxCharacteristic != null) {
        print('Upgraded characteristics not found. Falling back to Legacy Nordic UART RX.');
        notifyListeners();
        return true;
      }

      print('Failed to find matching services or characteristics.');
      await disconnect();
      return false;
    } catch (e) {
      print('BLE Connection error: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    _throughputTimer?.cancel();
    _tileReqSubscription?.cancel();
    _tileReqSubscription = null;

    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    
    _configCharacteristic = null;
    _routeCharacteristic = null;
    _tileReqCharacteristic = null;
    _tileDataCharacteristic = null;
    _locationCharacteristic = null;
    _rxCharacteristic = null;
    
    notifyListeners();
  }

  // Ready signal written to config characteristic
  Future<void> sendReadySignal() async {
    if (_configCharacteristic == null) return;
    try {
      await _configCharacteristic!.write(utf8.encode("READY"), withoutResponse: false);
      print("Sent READY signal.");
    } catch (e) {
      print("Failed to send READY signal: $e");
    }
  }

  // Get session token for 2D Tiles API
  Future<String?> _getSessionToken() async {
    if (_sessionToken != null) return _sessionToken;

    final String url = 'https://tile.googleapis.com/v1/createSession?key=${AppConstants.googleApiKey}';
    final payload = {"mapType": "roadmap", "language": "en-US", "region": "US"};

    try {
      final response = await _dio.post(
        url,
        data: payload,
        options: Options(headers: {"Content-Type": "application/json"}),
      );

      if (response.statusCode == 200) {
        _sessionToken = response.data['session'];
        print('Obtained new Google Maps Session: ${_sessionToken?.substring(0, 10)}...');
        return _sessionToken;
      }
    } catch (e) {
      print('Failed to get session token: $e');
    }
    return null;
  }

  // Fetch binary tile from Google 2D Tiles API
  Future<Uint8List?> _fetchTileData(String z, String x, String y) async {
    String? token = await _getSessionToken();
    if (token == null) return null;

    final String url = 'https://tile.googleapis.com/v1/2dtiles/$z/$x/$y?session=$token&key=${AppConstants.googleApiKey}&orientation=0';

    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        return Uint8List.fromList(response.data!);
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 400 || statusCode == 401 || statusCode == 403) {
        _sessionToken = null; // force token refresh
        token = await _getSessionToken();
        if (token == null) return null;
        
        final String retryUrl = 'https://tile.googleapis.com/v1/2dtiles/$z/$x/$y?session=$token&key=${AppConstants.googleApiKey}&orientation=0';
        try {
          final retryResponse = await _dio.get<List<int>>(
            retryUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          if (retryResponse.statusCode == 200) {
            return Uint8List.fromList(retryResponse.data!);
          }
        } catch (retryErr) {
          print('Retry failed to fetch tile $z/$x/$y: $retryErr');
        }
      }
      print('Failed to fetch tile $z/$x/$y, status $statusCode');
    } catch (e) {
      print('Error fetching tile: $e');
    }
    return null;
  }

  // Handle tile request notification from device
  Future<void> _handleTileRequest(String req) async {
    final parts = req.split('/');
    if (parts.length == 3) {
      final z = parts[0];
      final x = parts[1];
      final y = parts[2];
      
      print('BLE Device requested tile: $z/$x/$y');
      final pngData = await _fetchTileData(z, x, y);
      if (pngData != null) {
        await sendChunks(_tileDataCharacteristic, pngData);
        _tilesSentCount++;
      } else {
        print("Failed to download tile. Sending ERROR chunk.");
        if (_tileDataCharacteristic != null) {
          try {
            await _tileDataCharacteristic!.write([0x04], withoutResponse: true);
          } catch (e) {
            print("Failed to write ERROR chunk: $e");
          }
        }
      }
    }
  }

  // Chunked transmission protocol matching Python bleak implementation
  Future<void> sendChunks(BluetoothCharacteristic? characteristic, List<int> data) async {
    if (characteristic == null || _connectedDevice == null) return;
    
    final mtu = _connectedDevice!.mtuNow;
    final payloadMtu = mtu - 3;
    final totalLen = data.length;
    
    // First chunk is START (0x01)
    final firstChunkSize = (payloadMtu - 1) < totalLen ? (payloadMtu - 1) : totalLen;
    final List<int> firstPayload = [0x01] + data.sublist(0, firstChunkSize);
    
    try {
      await characteristic.write(firstPayload, withoutResponse: true);
      _bytesSentCount += firstPayload.length;
    } catch (e) {
      print("Failed to send START chunk: $e");
      return;
    }
    
    int offset = firstChunkSize;
    
    // Middle chunks (0x02)
    while (offset < totalLen) {
      final chunkSize = (payloadMtu - 1) < (totalLen - offset) ? (payloadMtu - 1) : (totalLen - offset);
      final List<int> midPayload = [0x02] + data.sublist(offset, offset + chunkSize);
      
      try {
        await characteristic.write(midPayload, withoutResponse: true);
        _bytesSentCount += midPayload.length;
      } catch (e) {
        print("Failed to send MIDDLE chunk at offset $offset: $e");
        return;
      }
      
      offset += chunkSize;
      // Tiny delay to prevent overflowing the ESP32's BLE stack ringbuffer
      await Future.delayed(const Duration(milliseconds: 5));
    }
    
    // END chunk (empty) (0x03)
    try {
      await characteristic.write([0x03], withoutResponse: true);
      _bytesSentCount += 1;
    } catch (e) {
      print("Failed to send END chunk: $e");
    }
  }

  // Directions API route fetching and polyline decoding
  Future<void> sendSdkRoute(List<List<double>> route) async {
    _currentRoute = route;
    print('Sending extracted SDK route coordinates of length ${route.length} points to BLE device...');
    
    if (isConnected && _routeCharacteristic != null) {
      final routeMap = {"route": route};
      final routeJsonBytes = utf8.encode(jsonEncode(routeMap));
      print('Sending route coordinates of length ${routeJsonBytes.length} bytes to BLE device...');
      await sendChunks(_routeCharacteristic, routeJsonBytes);
      print('Route sent successfully.');
    }
  }


  // Location updating and streaming
  Future<void> sendLocation(double latitude, double longitude) async {
    if (_locationCharacteristic == null || !isConnected) return;
    
    // Find closest index in route points
    final int currentIdx = findClosestRouteIndex(LatLng(latitude: latitude, longitude: longitude), _currentRoute);
    
    final String locStr = "${latitude.toStringAsFixed(7)},${longitude.toStringAsFixed(7)},$currentIdx";
    final List<int> bytes = utf8.encode(locStr);
    
    try {
      await _locationCharacteristic!.write(bytes, withoutResponse: true);
      print("[Location] Sent: $locStr");
    } catch (e) {
      print("[Location] Failed to send: $e");
    }
  }

  int findClosestRouteIndex(LatLng currentLocation, List<List<double>> routePoints) {
    if (routePoints.isEmpty) return 0;
    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < routePoints.length; i++) {
      final pt = routePoints[i];
      final double latDiff = pt[0] - currentLocation.latitude;
      final double lngDiff = pt[1] - currentLocation.longitude;
      final double dist = latDiff * latDiff + lngDiff * lngDiff;
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  // Throughput Tracking Timer
  void _startThroughputTimer() {
    _throughputTimer?.cancel();
    _throughputTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_bytesSentCount > 0 || _tilesSentCount > 0) {
        final double kbps = _bytesSentCount / 1024.0;
        print("[Throughput] $_tilesSentCount tiles/sec | ${kbps.toStringAsFixed(2)} KB/sec");
        _bytesSentCount = 0;
        _tilesSentCount = 0;
      }
    });
  }

  // Retain legacy method signature to avoid breaking compile-time safety
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

    final Map<String, dynamic> payload = {
      "s": double.parse(speed.toStringAsFixed(1)),
      "d": distanceToTurn.toInt(),
      "i": maneuverCode,
      "e": arrivalTime,
    };
    final String jsonStr = jsonEncode(payload);

    print('--- LEGACY NAV DATA ---');
    print('Speed: $speed km/h');
    print('Distance: ${distanceToTurn.toInt()}m');
    print('Maneuver: $maneuverCode');
    print('ETA: $arrivalTime');
    print('Raw JSON: $jsonStr');
    if (!isConnected) print('(BLE Not Connected - Legacy data not sent)');
    print('----------------');

    if (_rxCharacteristic == null || !isConnected) return;

    try {
      final List<int> bytes = utf8.encode("$jsonStr\n");
      await _rxCharacteristic!.write(bytes, withoutResponse: false);
    } catch (e) {
      print('Failed to send legacy BLE data: $e');
    }
  }


}
