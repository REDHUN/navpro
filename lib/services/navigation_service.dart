import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import 'ble_service.dart';

class NavigationService {
  final BleService bleService;

  GoogleNavigationViewController? navigationViewController;
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  StreamSubscription<Position>? _positionSubscription;

  bool _isNavigating = false;
  double _currentSpeedKmH = 0.0;
  bool _sessionActive = false;

  NavigationService(this.bleService);

  bool get isNavigating => _isNavigating;
  bool get isSessionActive => _sessionActive;

  Future<bool> initialize() async {
    try {
      // Check if terms are accepted. The dialog must be shown before
      // initializeNavigationSession() if they haven't been accepted yet.
      final bool termsAccepted = await GoogleMapsNavigator.areTermsAccepted();
      if (!termsAccepted) {
        debugPrint('NavigationService: Terms not accepted. Showing dialog...');
        final bool accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Driving safely',
          'By using this app, you agree to drive safely and follow all rules of the road.',
        );
        if (!accepted) {
          debugPrint('NavigationService: Terms were rejected.');
          return false;
        }
      }

      debugPrint('NavigationService: Initializing session...');
      await GoogleMapsNavigator.initializeNavigationSession();
      _sessionActive = true;
      _setupGeolocatorSpeed();
      debugPrint('NavigationService: Session initialized successfully.');
      return true;
    } catch (e) {
      debugPrint('NavigationService: Failed to initialize session: $e');
      rethrow; // Re-throw so ViewModel can catch and show the error
    }
  }

  void _setupGeolocatorSpeed() {
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen((Position position) {
          // Speed is in m/s, convert to km/h
          _currentSpeedKmH = position.speed * 3.6;
          if (_currentSpeedKmH < 0) _currentSpeedKmH = 0;
        });
  }

  Future<bool> startNavigation(LatLng dest, bool simulate, {LatLng? start}) async {
    try {
      final List<NavigationWaypoint> waypoints = [];
      
      // The destination is the target we want to reach.
      // We don't add the 'start' LatLng as a waypoint because the 
      // Google Navigation SDK automatically uses the device's current 
      // location as the origin for guidance.
      waypoints.add(NavigationWaypoint.withLatLngTarget(
        title: 'Destination',
        target: dest,
      ));

      final Destinations msg = Destinations(
        waypoints: waypoints,
        displayOptions: NavigationDisplayOptions(showDestinationMarkers: true),
      );

      final NavigationRouteStatus status =
          await GoogleMapsNavigator.setDestinations(msg);

      if (status == NavigationRouteStatus.statusOk) {
        await GoogleMapsNavigator.startGuidance();

        if (simulate) {
          if (start != null) {
            // If a custom start is provided for simulation, move the simulator there
            await GoogleMapsNavigator.simulator.setUserLocation(start);
          }
          await GoogleMapsNavigator.simulator
              .simulateLocationsAlongExistingRouteWithOptions(
                SimulationOptions(speedMultiplier: 5.0),
              );
        }

        await navigationViewController?.setNavigationUIEnabled(true);
        await navigationViewController?.followMyLocation(
          CameraPerspective.tilted,
        );

        _isNavigating = true;
        _startListeningToNavEvents();
        return true;
      }
    } catch (e) {
      debugPrint('Error starting navigation: $e');
    }
    return false;
  }

  void _startListeningToNavEvents() {
    _navInfoSubscription?.cancel();
    _navInfoSubscription = GoogleMapsNavigator.setNavInfoListener(
      _onNavInfoEvent,
      numNextStepsToPreview: 3,
    );
  }

  void _onNavInfoEvent(NavInfoEvent event) {
    if (!_isNavigating) return;

    final navInfo = event.navInfo;

    // Default values if data varies
    double distToNextTurn = 0.0;
    int maneuverCode = 0; // STRAIGHT
    int etaSeconds = 0;

    final currentStep = navInfo.currentStep;
    if (currentStep != null) {
      // Fallback to step-by-step distance if direct current step isn't available
      distToNextTurn = (navInfo.distanceToCurrentStepMeters ?? 0).toDouble();
      maneuverCode = _mapManeuverToCode(currentStep.maneuver);
    }

    if (navInfo.timeToNextDestinationSeconds != null) {
      etaSeconds = navInfo.timeToNextDestinationSeconds!;
    }

    debugPrint(
      'Nav event: Dist=${distToNextTurn}m, Maneuver=$maneuverCode, ETA=$etaSeconds Current Speed=${_currentSpeedKmH}km/h',
    );

    if (bleService.isConnected) {
      bleService.sendNavigationData(
        speed: _currentSpeedKmH,
        distanceToTurn: distToNextTurn,
        maneuverCode: maneuverCode,
        etaSeconds: etaSeconds,
      );
    }
  }

  int _mapManeuverToCode(Maneuver maneuver) {
    // 0 = STRAIGHT, 1 = LEFT, 2 = RIGHT, 3 = U-TURN, 4 = SLIGHT_LEFT, 5 = SLIGHT_RIGHT, 6 = ROUNDABOUT
    switch (maneuver) {
      case Maneuver.straight:
      case Maneuver.unknown:
      case Maneuver.turnKeepLeft:
      case Maneuver.turnKeepRight:
        return 0; // STRAIGHT
      case Maneuver.turnLeft:
      case Maneuver.turnSharpLeft:
        return 1; // LEFT
      case Maneuver.turnRight:
      case Maneuver.turnSharpRight:
        return 2; // RIGHT
      case Maneuver.turnUTurnClockwise:
      case Maneuver.turnUTurnCounterclockwise:
        return 3; // U-TURN
      case Maneuver.turnSlightLeft:
      case Maneuver.forkLeft:
      case Maneuver.onRampLeft:
      case Maneuver.offRampLeft:
        return 4; // SLIGHT_LEFT
      case Maneuver.turnSlightRight:
      case Maneuver.forkRight:
      case Maneuver.onRampRight:
      case Maneuver.offRampRight:
        return 5; // SLIGHT_RIGHT
      case Maneuver.roundaboutClockwise:
      case Maneuver.roundaboutCounterclockwise:
      case Maneuver.roundaboutExitClockwise:
      case Maneuver.roundaboutExitCounterclockwise:
      case Maneuver.roundaboutLeftClockwise:
      case Maneuver.roundaboutLeftCounterclockwise:
      case Maneuver.roundaboutRightClockwise:
      case Maneuver.roundaboutRightCounterclockwise:
      case Maneuver.roundaboutStraightClockwise:
      case Maneuver.roundaboutStraightCounterclockwise:
      case Maneuver.roundaboutUTurnClockwise:
      case Maneuver.roundaboutUTurnCounterclockwise:
        return 6; // ROUNDABOUT
      default:
        return 0;
    }
  }

  Future<void> stopNavigation() async {
    if (!_isNavigating && !_sessionActive) return; // already stopped
    _navInfoSubscription?.cancel();
    _isNavigating = false;
    _sessionActive = false;
    try {
      await GoogleMapsNavigator.simulator.removeUserLocation();
    } catch (_) {}
    try {
      await GoogleMapsNavigator.stopGuidance();
    } catch (_) {}
    try {
      await GoogleMapsNavigator.cleanup();
    } catch (_) {}
    debugPrint('NavigationService: stopNavigation complete');
  }

  void dispose() {
    _positionSubscription?.cancel();
    _navInfoSubscription?.cancel();
  }
}
