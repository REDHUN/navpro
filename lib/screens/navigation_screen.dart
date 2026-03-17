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

  void _onViewCreated(GoogleNavigationViewController controller) {
    final viewModel = context.read<NavigationViewModel>();
    viewModel.onMapCreated(controller);

    // Initial configuration of the controller in the view
    controller.setNavigationUIEnabled(true);
    controller.setMyLocationEnabled(true);

    viewModel.startNavigation(widget.destination, widget.simulateRoute, start: widget.start);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              context.read<NavigationViewModel>().stopNavigation();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMapsNavigationView(
            initialMapToolbarEnabled: true,
            onViewCreated: _onViewCreated,
            initialNavigationUIEnabledPreference: NavigationUIEnabledPreference.automatic,
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
    );
  }

  @override
  void dispose() {
    // ViewModel is maintained by MultiProvider, but we want to stop navigation on exit
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
