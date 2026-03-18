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
  StreamSubscription<OnArrivalEvent>? _onArrivalSubscription;

  bool _isNavigating = false;
  final ValueNotifier<double> speedNotifier = ValueNotifier<double>(0.0);
  bool _sessionActive = false;

  NavigationService(this.bleService);

  bool get isNavigating => _isNavigating;
  bool get isSessionActive => _sessionActive;
  double get currentSpeedKmH => speedNotifier.value;

  Future<bool> initialize() async {
    try {
      // Check if terms are accepted. The dialog must be shown before
      // initializeNavigationSession() if they haven't been accepted yet.
      final bool termsAccepted = await GoogleMapsNavigator.areTermsAccepted();
      if (!termsAccepted) {
        debugPrint('NavigationService: Terms not accepted. Showing dialog...');
        final bool
        accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
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
          speedNotifier.value = position.speed * 3.6;
          if (speedNotifier.value < 0) speedNotifier.value = 0;
        });
  }

  Future<bool> startNavigation(
    LatLng dest,
    bool simulate, {
    LatLng? start,
    NavigationTravelMode travelMode = NavigationTravelMode.driving,
  }) async {
    try {
      final List<NavigationWaypoint> waypoints = [];

      // The destination is the target we want to reach.
      // We don't add the 'start' LatLng as a waypoint because the
      // Google Navigation SDK automatically uses the device's current
      // location as the origin for guidance.
      waypoints.add(
        NavigationWaypoint.withLatLngTarget(title: 'Destination', target: dest),
      );

      final Destinations msg = Destinations(
        waypoints: waypoints,
        displayOptions: NavigationDisplayOptions(showDestinationMarkers: true),
        routingOptions: RoutingOptions(travelMode: travelMode),
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
    _onArrivalSubscription?.cancel();
    _onArrivalSubscription = GoogleMapsNavigator.setOnArrivalListener((arrivalEvent) {
      debugPrint('Arrived at waypoint: ${arrivalEvent.waypoint.title}');
      if (bleService.isConnected) {
        bleService.sendNavigationData(
          speed: speedNotifier.value,
          distanceToTurn: 0,
          maneuverCode: 6, // Destination Reached
          arrivalTime: 0,
        );
      }
    });
  }

  Future<void> setVoiceGuidance(bool enabled) async {
    await GoogleMapsNavigator.setAudioGuidance(
      NavigationAudioGuidanceSettings(
        isBluetoothAudioEnabled: true,
        isVibrationEnabled: true,
        guidanceType: enabled
            ? NavigationAudioGuidanceType.alertsAndGuidance
            : NavigationAudioGuidanceType.silent,
      ),
    );
  }

  void _onNavInfoEvent(NavInfoEvent event) {
    if (!_isNavigating) return;

    final navInfo = event.navInfo;

    // Default values if data varies
    double distToNextTurn = (navInfo.distanceToCurrentStepMeters ?? 0)
        .toDouble();
    int maneuverCode = 0; // STRAIGHT
    int etaSeconds = 0;

    final currentStep = navInfo.currentStep;
    if (currentStep != null) {
      maneuverCode = _mapManeuverToCode(currentStep.maneuver);
    }

    // Check if we reached the destination
    // Handled by setOnArrivalListener for more accuracy

    if (navInfo.timeToNextDestinationSeconds != null) {
      etaSeconds = navInfo.timeToNextDestinationSeconds!;
    }
    final arrivalTimeStr = _calculateEtaHHMM(etaSeconds);

    debugPrint(
      'Nav event: Dist=${distToNextTurn}m, Maneuver=$maneuverCode, ETA=$arrivalTimeStr Current Speed=${speedNotifier.value}km/h',
    );

    if (bleService.isConnected) {
      bleService.sendNavigationData(
        speed: speedNotifier.value,
        distanceToTurn: distToNextTurn,
        maneuverCode: maneuverCode,
        arrivalTime: arrivalTimeStr,
      );
    }
  }

  int _calculateEtaHHMM(int? secondsRemaining) {
    if (secondsRemaining == null) return 0;
    final arrivalTime = DateTime.now().add(Duration(seconds: secondsRemaining));
    return (arrivalTime.hour * 100) + arrivalTime.minute;
  }

  int _mapManeuverToCode(Maneuver maneuver) {
    // 0: Straight, 1: Left, 2: Right, 3: Slight Left, 4: Slight Right, 5: U-Turn, 6: Destination Reached
    switch (maneuver) {
      case Maneuver.straight:
      case Maneuver.unknown:
      case Maneuver.turnKeepLeft:
      case Maneuver.turnKeepRight:
        return 0; // Straight
      case Maneuver.turnLeft:
      case Maneuver.turnSharpLeft:
        return 1; // Left
      case Maneuver.turnRight:
      case Maneuver.turnSharpRight:
        return 2; // Right
      case Maneuver.turnSlightLeft:
      case Maneuver.forkLeft:
      case Maneuver.onRampLeft:
      case Maneuver.offRampLeft:
        return 3; // Slight Left
      case Maneuver.turnSlightRight:
      case Maneuver.forkRight:
      case Maneuver.onRampRight:
      case Maneuver.offRampRight:
        return 4; // Slight Right
      case Maneuver.turnUTurnClockwise:
      case Maneuver.turnUTurnCounterclockwise:
        return 5; // U-Turn
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
        return 0; // Roundabouts treated as straight/follow path unless specific exit turn is needed
      default:
        return 0;
    }
  }

  Future<void> stopNavigation() async {
    debugPrint('NavigationService: stopNavigation starting...');
    _isNavigating = false;
    _sessionActive = false;

    _navInfoSubscription?.cancel();
    _navInfoSubscription = null;
    _onArrivalSubscription?.cancel();
    _onArrivalSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;

    try {
      if (await GoogleMapsNavigator.isGuidanceRunning()) {
        await GoogleMapsNavigator.stopGuidance();
      }
    } catch (e) {
      debugPrint('NavigationService: Error stopping guidance: $e');
    }

    try {
      await GoogleMapsNavigator.simulator.removeUserLocation();
    } catch (e) {
      debugPrint('NavigationService: Error removing user location: $e');
    }

    try {
      await GoogleMapsNavigator.cleanup();
    } catch (e) {
      debugPrint('NavigationService: Error cleaning up navigator: $e');
    }
    debugPrint('NavigationService: stopNavigation complete');
  }

  void dispose() {
    stopNavigation();
    speedNotifier.dispose();
  }
}
