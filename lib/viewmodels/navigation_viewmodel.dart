import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import '../services/navigation_service.dart';

class NavigationViewModel extends ChangeNotifier {
  final NavigationService _navigationService;

  NavigationViewModel({
    required NavigationService navigationService,
  }) : _navigationService = navigationService;

  bool _isNavigationReady = false;
  String? _errorMessage;

  bool get isNavigationReady => _isNavigationReady;
  String? get errorMessage => _errorMessage;

  void onMapCreated(GoogleNavigationViewController controller) {
    _navigationService.navigationViewController = controller;
    _isNavigationReady = false;
    notifyListeners();
  }

  Future<void> startNavigation(LatLng destination, bool simulate, {LatLng? start}) async {
    _isNavigationReady = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await _navigationService.startNavigation(destination, simulate, start: start);
      if (success) {
        _isNavigationReady = true;
      } else {
        _errorMessage = 'Failed to calculate route';
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
}
