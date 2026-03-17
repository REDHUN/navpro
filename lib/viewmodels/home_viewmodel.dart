import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import '../models/place_model.dart';
import '../services/ble_service.dart';
import '../services/places_service.dart';
import '../services/navigation_service.dart';
import '../services/permission_service.dart';

enum SelectionType { none, start, destination }

class HomeViewModel extends ChangeNotifier {
  final BleService _bleService;
  final PlacesService _placesService;
  final NavigationService _navigationService;
  final PermissionService _permissionService;

  HomeViewModel({
    required BleService bleService,
    required PlacesService placesService,
    required NavigationService navigationService,
    required PermissionService permissionService,
  })  : _bleService = bleService,
        _placesService = placesService,
        _navigationService = navigationService,
        _permissionService = permissionService {
    _bleService.addListener(notifyListeners);
  }

  PlaceModel? _startLocation;
  PlaceModel? _destination;
  LatLng? _startLocationLatLng;
  LatLng? _destinationLatLng;

  bool _simulateRoute = false;
  bool _isLoadingRoute = false;
  bool _initializationComplete = false;
  String? _errorMessage;

  GoogleNavigationViewController? _mapController;
  SelectionType _pickingType = SelectionType.none;
  NavigationTravelMode _travelMode = NavigationTravelMode.driving;

  PlaceModel? get startLocation => _startLocation;
  PlaceModel? get destination => _destination;
  LatLng? get startLocationLatLng => _startLocationLatLng;
  LatLng? get destinationLatLng => _destinationLatLng;
  NavigationTravelMode get travelMode => _travelMode;
  
  bool get simulateRoute => _simulateRoute;
  bool get isLoadingRoute => _isLoadingRoute;
  bool get isBleConnected => _bleService.isConnected;
  bool get initializationComplete => _initializationComplete;
  String? get errorMessage => _errorMessage;
  SelectionType get pickingType => _pickingType;

  final List<Marker> _markers = [];

  void onMapCreated(GoogleNavigationViewController controller) {
    _mapController = controller;
    _updateMarkers();
  }

  void setPickingType(SelectionType type) {
    _pickingType = type;
    notifyListeners();
  }

  void onMapTap(LatLng position) {
    if (_pickingType == SelectionType.start) {
      _startLocationLatLng = position;
      _startLocation = PlaceModel(
        name: 'Point on Map',
        address: '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
        placeId: 'manual_start',
        location: position,
      );
      _pickingType = SelectionType.none;
      _updateMarkers();
      notifyListeners();
    } else if (_pickingType == SelectionType.destination) {
      _destinationLatLng = position;
      _destination = PlaceModel(
        name: 'Point on Map',
        address: '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
        placeId: 'manual_dest',
        location: position,
      );
      _pickingType = SelectionType.none;
      _updateMarkers();
      notifyListeners();
    }
  }

  Future<void> _updateMarkers() async {
    if (_mapController == null) return;

    try {
      if (_markers.isNotEmpty) {
        await _mapController!.removeMarkers(_markers);
        _markers.clear();
      }
      
      final List<MarkerOptions> optionsList = [];

      if (_startLocationLatLng != null) {
        optionsList.add(MarkerOptions(
          position: _startLocationLatLng!,
          infoWindow: const InfoWindow(title: 'Starting Point'),
        ));
      }

      if (_destinationLatLng != null) {
        optionsList.add(MarkerOptions(
          position: _destinationLatLng!,
          infoWindow: const InfoWindow(title: 'Destination'),
        ));
      }

      if (optionsList.isNotEmpty) {
        final List<Marker?> added = await _mapController!.addMarkers(optionsList);
        for (final m in added) {
          if (m != null) _markers.add(m);
        }
      }
    } catch (e) {
      debugPrint('Error updating markers: $e');
    }
  }

  void setStartLocation(PlaceModel? place) {
    _startLocation = place;
    _startLocationLatLng = place?.location;
    _updateMarkers();
    notifyListeners();
  }

  void setDestination(PlaceModel? place) {
    _destination = place;
    _destinationLatLng = place?.location;
    _updateMarkers();
    notifyListeners();
  }

  void swapLocations() {
    final tempLoc = _startLocation;
    final tempLatLng = _startLocationLatLng;
    
    _startLocation = _destination;
    _startLocationLatLng = _destinationLatLng;
    
    _destination = tempLoc;
    _destinationLatLng = tempLatLng;
    
    _updateMarkers();
    notifyListeners();
  }

  Future<bool> resolvePoints() async {
    _isLoadingRoute = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_startLocationLatLng == null && _startLocation != null && !_startLocation!.placeId.startsWith('manual')) {
        _startLocationLatLng = await _placesService.getPlaceDetails(_startLocation!.placeId);
      }
      
      if (_destinationLatLng == null && _destination != null && !_destination!.placeId.startsWith('manual')) {
        _destinationLatLng = await _placesService.getPlaceDetails(_destination!.placeId);
      }

      _updateMarkers();
      _isLoadingRoute = false;
      notifyListeners();
      return _destinationLatLng != null;
    } catch (e) {
      _isLoadingRoute = false;
      _errorMessage = 'Resolution error: $e';
      notifyListeners();
      return false;
    }
  }

  void toggleSimulation(bool value) {
    _simulateRoute = value;
    notifyListeners();
  }

  void setTravelMode(NavigationTravelMode mode) {
    _travelMode = mode;
    notifyListeners();
  }

  Future<void> initializeNavigation() async {
    try {
      final permissionsGranted = await _permissionService.requestAllPermissions();
      if (!permissionsGranted) {
        _errorMessage = 'Required permissions were not granted.';
        notifyListeners();
        return;
      }
      
      final initialized = await _navigationService.initialize();
      if (!initialized) {
        _errorMessage = 'Navigation terms were rejected.';
        _initializationComplete = false;
      } else {
        _initializationComplete = true;
        _errorMessage = null;
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Init error: $e.\n\nTroubleshooting:\n1. Ensure "Navigation SDK" is enabled in Google Cloud Console.\n2. Verify API Key restrictions (Package: com.example.navprov2).\n3. Check if billing is enabled on your Cloud Project.';
      _initializationComplete = false;
      notifyListeners();
    }
  }

  void disconnectBle() {
    _bleService.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _bleService.removeListener(notifyListeners);
    super.dispose();
  }
}
