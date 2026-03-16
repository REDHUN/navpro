import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:provider/provider.dart';

import '../services/navigation_service.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng destination;
  final bool simulateRoute;

  const NavigationScreen({
    Key? key,
    required this.destination,
    this.simulateRoute = false,
  }) : super(key: key);

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _isNavigationReady = false;

  @override
  void initState() {
    super.initState();
  }

  void _onViewCreated(GoogleNavigationViewController controller) async {
    final navigationService = context.read<NavigationService>();
    navigationService.navigationViewController = controller;

    try {
      // Enable navigation UI features
      await controller.setNavigationUIEnabled(true);
      await controller.setMyLocationEnabled(true);
    } catch (e) {
      debugPrint("Error configuring navigation UI: $e");
    }

    if (mounted) {
      _startRoute();
    }
  }

  Future<void> _startRoute() async {
    final navigationService = context.read<NavigationService>();
    try {
      await navigationService.startNavigation(
        widget.destination,
        widget.simulateRoute,
      );
      if (mounted) {
        setState(() {
          _isNavigationReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error calculating route: $e')));
        // Optionally pop the screen or allow retry
      }
    }
  }

  void _stopNavigation() async {
    final navigationService = context.read<NavigationService>();
    await navigationService.stopNavigation();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          IconButton(icon: const Icon(Icons.close), onPressed: _stopNavigation),
        ],
      ),
      body: Stack(
        children: [
          GoogleMapsNavigationView(
            initialMapToolbarEnabled: true,
            onViewCreated: _onViewCreated,
            initialNavigationUIEnabledPreference:
                NavigationUIEnabledPreference.automatic,
          ),
          if (!_isNavigationReady)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Calculating Route...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    context.read<NavigationService>().stopNavigation();
    super.dispose();
  }
}
