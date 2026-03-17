import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:provider/provider.dart';

import '../viewmodels/navigation_viewmodel.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng destination;
  final LatLng? start;
  final bool simulateRoute;

  const NavigationScreen({
    Key? key,
    required this.destination,
    this.start,
    this.simulateRoute = false,
  }) : super(key: key);

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  @override
  void initState() {
    super.initState();
  }

  void _onViewCreated(GoogleNavigationViewController controller) async {
    final viewModel = context.read<NavigationViewModel>();
    viewModel.onMapCreated(controller);

    // Ensure the Google Navigation session is initialized before setting
    // destinations. The home screen initializes it on first load, but if
    // stopNavigation() cleaned it up we need to re-initialize here.
    await viewModel.initialize();

    if (mounted) {
      viewModel.startNavigation(
        widget.destination,
        widget.simulateRoute,
        start: widget.start,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Ensure we stop navigation when the user tries to pop back
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.read<NavigationViewModel>().stopNavigation();
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Navigation'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              context.read<NavigationViewModel>().stopNavigation();
              Navigator.of(context).pop();
            },
          ),
        ),
        body: Stack(
          children: [
            GoogleMapsNavigationView(
              initialMapToolbarEnabled: true,
              onViewCreated: _onViewCreated,
              initialNavigationUIEnabledPreference:
                  NavigationUIEnabledPreference.automatic,
            ),
            Selector<NavigationViewModel, bool>(
              selector: (_, vm) => vm.isNavigationReady,
              builder: (context, isReady, _) {
                if (isReady) return const SizedBox.shrink();
                return const _CalculatingRouteOverlay();
              },
            ),
            Consumer<NavigationViewModel>(
              builder: (context, viewModel, _) {
                if (viewModel.errorMessage != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(viewModel.errorMessage!)),
                    );
                  });
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // ViewModel is in provider, but double-calling stopNavigation in dispose
    // is safe and acts as a final cleanup for any edge cases.
    context.read<NavigationViewModel>().stopNavigation();
    super.dispose();
  }
}

class _CalculatingRouteOverlay extends StatelessWidget {
  const _CalculatingRouteOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(
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
    );
  }
}
