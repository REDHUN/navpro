import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import 'ble_service.dart';

class NavData {
  final String nextStepDistance;
  final String nextStepInstruction;
  final Maneuver maneuver;
  final String totalDistanceRemaining;
  final String totalTimeRemaining;
  final String estimatedArrivalTime;
  final String? trafficInfo;

  NavData({
    required this.nextStepDistance,
    required this.nextStepInstruction,
    required this.maneuver,
    required this.totalDistanceRemaining,
    required this.totalTimeRemaining,
    required this.estimatedArrivalTime,
    this.trafficInfo,
  });
}

class NavigationService {
  final BleService bleService;

  GoogleNavigationViewController? navigationViewController;
  StreamSubscription<NavInfoEvent>? _navInfoSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<OnArrivalEvent>? _onArrivalSubscription;

  bool _isNavigating = false;
  final ValueNotifier<double> speedNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<NavData?> navDataNotifier = ValueNotifier<NavData?>(null);
  bool _sessionActive = false;

  NavigationService(this.bleService);

  bool get isNavigating => _isNavigating;
  bool get isSessionActive => _sessionActive;
  double get currentSpeedKmH => speedNotifier.value;
  NavData? get navData => navDataNotifier.value;

  Future<bool> initialize() async {
    try {
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
      rethrow;
    }
  }

  void _setupGeolocatorSpeed() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
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
      waypoints.add(
        NavigationWaypoint.withLatLngTarget(title: 'Destination', target: dest),
      );

      final Destinations msg = Destinations(
        waypoints: waypoints,
        displayOptions: NavigationDisplayOptions(showDestinationMarkers: true),
        routingOptions: RoutingOptions(travelMode: travelMode),
      );

      final NavigationRouteStatus status = await GoogleMapsNavigator.setDestinations(msg);

      if (status == NavigationRouteStatus.statusOk) {
        await GoogleMapsNavigator.startGuidance();

        if (simulate) {
          if (start != null) {
            await GoogleMapsNavigator.simulator.setUserLocation(start);
          }
          await GoogleMapsNavigator.simulator.simulateLocationsAlongExistingRouteWithOptions(
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
        guidanceType: enabled ? NavigationAudioGuidanceType.alertsAndGuidance : NavigationAudioGuidanceType.silent,
      ),
    );
  }

  void _onNavInfoEvent(NavInfoEvent event) {
    if (!_isNavigating) return;

    final navInfo = event.navInfo;
    double distToNextTurn = (navInfo.distanceToCurrentStepMeters ?? 0).toDouble();
    int maneuverCode = 0;
    int etaSeconds = 0;

    final currentStep = navInfo.currentStep;
    String nextStepInstruction = "";
    Maneuver currentManeuver = Maneuver.unknown;

    if (currentStep != null) {
      maneuverCode = _mapManeuverToCode(currentStep.maneuver);
      nextStepInstruction = currentStep.fullInstructions ?? "";
      currentManeuver = currentStep.maneuver;
    }

    if (navInfo.timeToNextDestinationSeconds != null) {
      etaSeconds = navInfo.timeToNextDestinationSeconds!;
    }
    final arrivalTimeInt = _calculateEtaHHMM(etaSeconds);
    final arrivalTimeStr = _formatEtaTime(etaSeconds);

    // Update the UI notifier
    navDataNotifier.value = NavData(
      nextStepDistance: _formatDistance(distToNextTurn),
      nextStepInstruction: nextStepInstruction,
      maneuver: currentManeuver,
      totalDistanceRemaining: _formatDistance((navInfo.distanceToNextDestinationMeters ?? 0).toDouble()),
      totalTimeRemaining: _formatDuration(etaSeconds),
      estimatedArrivalTime: arrivalTimeStr,
      trafficInfo: null,
    );

    debugPrint(
      'Nav event: Dist=${distToNextTurn}m, Maneuver=$maneuverCode, ETA=$arrivalTimeStr Current Speed=${speedNotifier.value}km/h',
    );

    if (bleService.isConnected) {
      bleService.sendNavigationData(
        speed: speedNotifier.value,
        distanceToTurn: distToNextTurn,
        maneuverCode: maneuverCode,
        arrivalTime: arrivalTimeInt,
      );
    }
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return "${(meters / 1000).toStringAsFixed(1)} km";
    } else {
      return "${meters.toStringAsFixed(0)} m";
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return "$seconds sec"; // RESTORED FIX
    }
    int minutes = (seconds / 60).round();
    if (minutes < 60) {
      return "$minutes min";
    } else {
      int hours = minutes ~/ 60;
      int mins = minutes % 60;
      return "${hours}h ${mins}m";
    }
  }

  String _formatEtaTime(int secondsRemaining) {
    final arrivalTime = DateTime.now().add(Duration(seconds: secondsRemaining));
    final hour = arrivalTime.hour > 12 ? arrivalTime.hour - 12 : (arrivalTime.hour == 0 ? 12 : arrivalTime.hour);
    final minute = arrivalTime.minute.toString().padLeft(2, '0');
    final amPm = arrivalTime.hour >= 12 ? "pm" : "am";
    return "$hour:$minute $amPm";
  }

  int _calculateEtaHHMM(int? secondsRemaining) {
    if (secondsRemaining == null) return 0;
    final arrivalTime = DateTime.now().add(Duration(seconds: secondsRemaining));
    return (arrivalTime.hour * 100) + arrivalTime.minute;
  }

  int _mapManeuverToCode(Maneuver maneuver) {
    switch (maneuver) {
      case Maneuver.straight:
      case Maneuver.unknown:
      case Maneuver.turnKeepLeft:
      case Maneuver.turnKeepRight:
        return 0;
      case Maneuver.turnLeft:
      case Maneuver.turnSharpLeft:
        return 1;
      case Maneuver.turnRight:
      case Maneuver.turnSharpRight:
        return 2;
      case Maneuver.turnSlightLeft:
      case Maneuver.forkLeft:
      case Maneuver.onRampLeft:
      case Maneuver.offRampLeft:
        return 3;
      case Maneuver.turnSlightRight:
      case Maneuver.forkRight:
      case Maneuver.onRampRight:
      case Maneuver.offRampRight:
        return 4;
      case Maneuver.turnUTurnClockwise:
      case Maneuver.turnUTurnCounterclockwise:
        return 5;
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
    navDataNotifier.dispose();
  }
}
