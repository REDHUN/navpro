import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:provider/provider.dart';

import '../services/ble_service.dart';
import '../viewmodels/home_viewmodel.dart';
import '../widgets/device_scan_dialog.dart';
import 'navigation_screen.dart';
import 'place_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().initializeNavigation();
      // Ensure focus is cleared when returning to Home
      FocusManager.instance.primaryFocus?.unfocus();
    });
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
    );
  }

  void _onStartNavigation(HomeViewModel viewModel) async {
    final success = await viewModel.resolvePoints();

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select valid start and destination points'),
          ),
        );
      }
      return;
    }

    if (!viewModel.isBleConnected) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Icon with Status Dot
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bluetooth,
                          color: Color(0xFF3F51B5), size: 32),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Title
                const Text(
                  'BLE Not Connected',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Description
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: 'You are not connected to an '),
                      TextSpan(
                        text: 'ESP32',
                        style: TextStyle(
                          color: const Color(0xFF3F51B5),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: '. Navigate anyway?'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Proceed Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51B5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Proceed',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),

                // Cancel Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF374151),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Footer
                const Text(
                  'HARDWARE STATUS: DISCONNECTED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (proceed != true) return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NavigationScreen(
            destination: viewModel.destinationLatLng!,
            start: viewModel.startLocationLatLng,
            simulateRoute: viewModel.simulateRoute,
            travelMode: viewModel.travelMode,
            useAdvancedUi: viewModel.useAdvancedUi,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<HomeViewModel>();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Map Background
          GoogleMapsNavigationView(
            onViewCreated: viewModel.onMapCreated,
            onMapClicked: viewModel.onMapTap,
            initialNavigationUIEnabledPreference:
                NavigationUIEnabledPreference.automatic,
          ),

          // 2. Top Header
          Positioned(top: 40, left: 20, right: 20, child: _TopHeader()),

          // 3. Floating Overlay Logic
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  children: [
                    const SizedBox(height: 100), // Push down below header
                    // BLE Status Bar
                    _BleStatusBar(onScanRequest: _showBleScanDialog),

                    const SizedBox(height: 16),

                    // Selection Card
                    const _RouteSelectionCard(),

                    // Minimal padding at bottom
                    const SizedBox(
                      height: 120,
                    ), // Keep some padding for the fixed start button
                  ],
                ),
              ),
            ),
          ),

          // 4. Start Navigation Button
          Positioned(
            bottom: 60,
            left: 20,
            right: 20,
            child: _StartNavigationButton(
              onPressed: () => _onStartNavigation(viewModel),
            ),
          ),

          // 5. Picking State Notification
          Selector<HomeViewModel, SelectionType>(
            selector: (_, vm) => vm.pickingType,
            builder: (context, type, _) {
              if (type == SelectionType.none) return const SizedBox.shrink();
              return Positioned(
                top: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Tap map to set ${type == SelectionType.start ? "Starting Point" : "Destination"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 6. Error Notification
          Consumer<HomeViewModel>(
            builder: (context, vm, _) {
              if (vm.errorMessage == null) return const SizedBox.shrink();
              return Positioned(
                bottom: 110,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    vm.errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A5E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'NavPro',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A5E),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.orange, size: 20),
          ),
        ],
      ),
    );
  }
}

class _BleStatusBar extends StatelessWidget {
  final VoidCallback onScanRequest;
  const _BleStatusBar({required this.onScanRequest});

  @override
  Widget build(BuildContext context) {
    return Selector<HomeViewModel, bool>(
      selector: (_, vm) => vm.isBleConnected,
      builder: (context, isConnected, _) {
        return GestureDetector(
          onTap: () {
            final viewModel = context.read<HomeViewModel>();
            if (isConnected) {
              viewModel.disconnectBle();
            } else {
              onScanRequest();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: isConnected ? Colors.blue : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConnected
                        ? 'ESP32 Connected'
                        : 'Scanning for BLE devices...',
                    style: TextStyle(
                      color: isConnected
                          ? Colors.blue.shade800
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RouteSelectionCard extends StatelessWidget {
  const _RouteSelectionCard();

  @override
  Widget build(BuildContext context) {
    // We use context.watch since multiple fields might change
    final viewModel = context.watch<HomeViewModel>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildLocationField(
            context,
            label: 'STARTING POINT',
            hint: 'Search starting point',
            value: viewModel.startLocation?.name,
            icon: Icons.radio_button_checked,
            iconColor: Colors.blue.shade900,
            isOrigin: true,
            onMapPick: () => viewModel.setPickingType(SelectionType.start),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 31, top: 4, bottom: 4),
            child: Row(
              children: [
                const _DashedLine(height: 40),
                const Spacer(),
                GestureDetector(
                  onTap: viewModel.swapLocations,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Icon(
                      Icons.swap_vert,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          _buildLocationField(
            context,
            label: 'DESTINATION',
            hint: 'Where to?',
            value: viewModel.destination?.name,
            icon: Icons.location_on,
            iconColor: Colors.red.shade600,
            isOrigin: false,
            onMapPick: () =>
                viewModel.setPickingType(SelectionType.destination),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTravelModeIcon(
                context,
                viewModel,
                NavigationTravelMode.driving,
                Icons.directions_car,
                'Driving',
              ),
              _buildTravelModeIcon(
                context,
                viewModel,
                NavigationTravelMode.cycling,
                Icons.directions_bike,
                'Cycling',
              ),
              _buildTravelModeIcon(
                context,
                viewModel,
                NavigationTravelMode.walking,
                Icons.directions_walk,
                'Walking',
              ),
              _buildTravelModeIcon(
                context,
                viewModel,
                NavigationTravelMode.twoWheeler,
                Icons.two_wheeler,
                'Two-Wheeler',
              ),
              _buildTravelModeIcon(
                context,
                viewModel,
                NavigationTravelMode.taxi,
                Icons.local_taxi,
                'Taxi',
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),

          Row(
            children: [
              Icon(Icons.route, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Simulate Route',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Switch(
                value: viewModel.simulateRoute,
                onChanged: viewModel.toggleSimulation,
                activeColor: Colors.blue.shade900,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Use Professional UI',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Switch(
                value: viewModel.useAdvancedUi,
                onChanged: viewModel.toggleAdvancedUi,
                activeColor: Colors.blue.shade900,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTravelModeIcon(
    BuildContext context,
    HomeViewModel viewModel,
    NavigationTravelMode mode,
    IconData icon,
    String tooltip,
  ) {
    final isSelected = viewModel.travelMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => viewModel.setTravelMode(mode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade50 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.blue.shade900 : Colors.grey.shade400,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationField(
    BuildContext context, {
    required String label,
    required String hint,
    String? value,
    required IconData icon,
    required Color iconColor,
    required bool isOrigin,
    required VoidCallback onMapPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade400,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlaceSearchScreen(
                        isOrigin: isOrigin,
                        initialQuery: value ?? '',
                      ),
                    ),
                  ).then((_) {
                    if (context.mounted) {
                      FocusScope.of(context).unfocus();
                    }
                  });
                },

                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    value ?? hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: value != null
                          ? const Color(0xFF1A1A2E)
                          : Colors.grey.shade400,
                      fontWeight: value != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.map, color: Colors.grey.shade300, size: 20),
              onPressed: onMapPick,
              tooltip: 'Pick from Map',
            ),
          ],
        ),
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  final double height;
  const _DashedLine({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Column(
        children: List.generate(
          4,
          (index) => Container(
            width: 2,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 2),
            color: Colors.grey.shade300,
          ),
        ),
      ),
    );
  }
}

class _StartNavigationButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _StartNavigationButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<HomeViewModel, bool>(
      (vm) => vm.isLoadingRoute,
    );

    return SizedBox(
      height: 64,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A1A5E).withOpacity(0.9),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          elevation: 8,
          shadowColor: const Color(0xFF1A1A5E).withOpacity(0.4),
        ),
        onPressed: isLoading ? null : onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.navigation, size: 24),
            const SizedBox(width: 12),
            const Text(
              'START NAVIGATION',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
