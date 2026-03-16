import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/place_model.dart';
import '../services/ble_service.dart';
import '../services/navigation_service.dart';
import '../services/places_service.dart';
import '../widgets/device_scan_dialog.dart';
import '../widgets/location_search_field.dart';
import 'navigation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlaceModel? _startLocation;
  PlaceModel? _destination;
  bool _simulateRoute = false;
  LatLng? _destinationLatLng;
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNavigation();
    });
  }

  Future<void> _initializeNavigation() async {
    // 1. Request location and bluetooth permissions sequentially
    var locStatus = await Permission.locationWhenInUse.request();
    if (locStatus.isGranted) {
      // Optional background location (only if when-in-use is granted)
      await Permission.locationAlways.request();
    }
    
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    // Check if location is granted to proceed with Initialization
    if (!(await Permission.locationWhenInUse.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required for navigation.'),
          ),
        );
      }
      return;
    }

    // 2. Check and request Google Maps Navigation terms acceptance
    bool termsAccepted = await GoogleMapsNavigator.areTermsAccepted();
    if (!termsAccepted) {
      if (!mounted) return;
      termsAccepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
            'NavPro V2',
            'To provide turn-by-turn navigation, NavPro V2 needs to use the Google Maps Navigation SDK.',
          );
    }

    if (termsAccepted) {
      try {
        if (!mounted) return;
        await context.read<NavigationService>().initialize();
      } catch (e) {
        debugPrint("Error initializing navigation: $e");
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Navigation terms must be accepted to use this app.'),
          ),
        );
      }
    }
  }

  void _showBleScanDialog() {
    final bleService = context.read<BleService>();
    showDialog(
      context: context,
      builder: (context) => DeviceScanDialog(
        startScan: bleService.scanForDevices,
        stopScan: bleService.stopScan,
        connectToDevice: bleService.connectToDevice,
      ),
    ).then((connected) {
      // Refresh triggered by notifyListeners in BleService
    });
  }

  void _disconnectBle() async {
    await context.read<BleService>().disconnect();
    setState(() {});
  }

  void _startNavigation() async {
    if (_destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination')),
      );
      return;
    }

    setState(() {
      _isLoadingRoute = true;
    });

    // Resolve LatLng for destination
    _destinationLatLng = await context.read<PlacesService>().getPlaceDetails(_destination!.placeId);

    setState(() {
      _isLoadingRoute = false;
    });

    if (_destinationLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get coordinates for destination')),
      );
      return;
    }

    if (!context.read<BleService>().isConnected) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('BLE Not Connected'),
          content: const Text('You are not connected to an ESP32. Navigate anyway without sending data?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          destination: _destinationLatLng!,
          simulateRoute: _simulateRoute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleService = context.watch<BleService>();
    final isBleConnected = bleService.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NavPro V2'),
        actions: [
          FilterChip(
            label: const Text('Simulate'),
            selected: _simulateRoute,
            onSelected: (val) {
              setState(() {
                _simulateRoute = val;
              });
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: isBleConnected ? Colors.green : Colors.grey,
            ),
            onPressed: _showBleScanDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // BLE Status Card
              Card(
                color: isBleConnected ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        color: isBleConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          isBleConnected ? 'Connected to ESP32' : 'Not Connected to ESP32',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: bleService.isConnected ? _disconnectBle : _showBleScanDialog,
                        child: Text(bleService.isConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Location Inputs
              const Text(
                'Where to?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              /* Note: Current location is assumed as start for real navigation if not simulated,
                 but we allow them to search for start location if they wanted. For Google API, 
                 typically you just simulate start location from emulator or use GPS data. */

              LocationSearchField(
                label: 'Destination',
                placesService: context.read<PlacesService>(),
                onPlaceSelected: (place) {
                  setState(() {
                    _destination = place;
                  });
                },
              ),
              if (_destination != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Selected: ${_destination!.description}',
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
                
              const SizedBox(height: 32),
              
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  icon: _isLoadingRoute 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2,))
                      : const Icon(Icons.navigation),
                  label: const Text('START NAVIGATION', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isLoadingRoute ? null : _startNavigation,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
