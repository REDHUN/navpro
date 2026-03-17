import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import '../services/navigation_service.dart';

class NavigationViewModel extends ChangeNotifier {
  final NavigationService _navigationService;

  NavigationViewModel({
    required NavigationService navigationService,
  }) : _navigationService = navigationService {
    _navigationService.speedNotifier.addListener(notifyListeners);
  }

  bool _isNavigationReady = false;
  bool _isInitializing = false;
  String? _errorMessage;

  bool get isNavigationReady => _isNavigationReady;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  double get currentSpeed => _navigationService.currentSpeedKmH;

  void onMapCreated(GoogleNavigationViewController controller) {
    _navigationService.navigationViewController = controller;
    _isNavigationReady = false;
    notifyListeners();
  }

  /// Ensures the navigation session is initialized. Called from the
  /// NavigationScreen once the map controller is ready.
  Future<void> initialize() async {
    if (_navigationService.isSessionActive) return; // already initialized
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _navigationService.initialize();
    } catch (e) {
      _errorMessage = 'Initialization error: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> startNavigation(LatLng destination, bool simulate,
      {LatLng? start,
      NavigationTravelMode travelMode = NavigationTravelMode.driving}) async {
    _isNavigationReady = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await _navigationService.startNavigation(destination, simulate,
          start: start, travelMode: travelMode);
      if (success) {
        _isNavigationReady = true;
      } else {
        _errorMessage = 'Failed to calculate route. Check your destination and internet connection.';
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error: $e';
      notifyListeners();
    }
  }

  void stopNavigation() {
    _navigationService.stopNavigation();
    _isNavigationReady = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _navigationService.speedNotifier.removeListener(notifyListeners);
    super.dispose();
  }
}
