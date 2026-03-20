import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:provider/provider.dart';

import '../viewmodels/navigation_viewmodel.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng destination;
  final LatLng? start;
  final bool simulateRoute;
  final NavigationTravelMode travelMode;
  final bool useAdvancedUi;

  const NavigationScreen({
    super.key,
    required this.destination,
    this.start,
    this.simulateRoute = false,
    this.travelMode = NavigationTravelMode.driving,
    this.useAdvancedUi = true,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  late NavigationViewModel _viewModel;
  GoogleNavigationViewController? _navigationViewController;
  bool _isPromptVisible = false;
  bool _isFollowing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Grab the reference once while the context is valid
    _viewModel = context.read<NavigationViewModel>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-apply padding if dependencies (like MediaQuery) change
    _updateMapPadding();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      debugPrint('NavigationScreen: App state $state, stopping navigation');
      _viewModel.stopNavigation();
    }
  }

  Future<void> _updateMapPadding() async {
    final controller = _navigationViewController;
    if (controller == null || !mounted) return;

    // Small delay to ensure map state has settled before applying padding
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final double pixelRatio = MediaQuery.of(context).devicePixelRatio;

    if (widget.useAdvancedUi) {
      // Professional UI padding
      const double baseBottomPadding = 250.0;
      const double baseTopPadding = 120.0;

      final EdgeInsets padding = EdgeInsets.only(
        bottom: (baseBottomPadding * pixelRatio),
        top: (baseTopPadding * pixelRatio),
        left: 10 * pixelRatio,
        right: 10 * pixelRatio,
      );

      await controller.setNavigationHeaderEnabled(false);
      await controller.setNavigationFooterEnabled(false);
      await controller.setRecenterButtonEnabled(false);
      await controller.setTrafficPromptsEnabled(true);
      await controller.setPadding(padding);
    } else {
      // Default UI: Enable SDK components and use padding for safe area
      final double topSafeArea = MediaQuery.of(context).viewPadding.top;
      final double bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;

      // Use a safer default if MediaQuery returns 0
      final double topVal = topSafeArea > 0 ? topSafeArea : 40.0;
      final double bottomVal = bottomSafeArea > 0 ? bottomSafeArea : 40.0;

      final EdgeInsets padding = EdgeInsets.only(
        top:
            (topVal + 100) *
            pixelRatio, // even more padding for the green header
        bottom: (bottomVal + 40) * pixelRatio,

        left: 10 * pixelRatio,
        right: 10 * pixelRatio,
      );

      await controller.setNavigationHeaderEnabled(true);
      await controller.setNavigationFooterEnabled(true);
      await controller.setRecenterButtonEnabled(
        false,
      ); // Hide SDK's recenter button
      await controller.setTrafficPromptsEnabled(
        true,
      ); // Restore SDK's traffic Prompts / road works notifications
      await controller.setPadding(padding);
    }
  }

  void _onViewCreated(GoogleNavigationViewController controller) async {
    _navigationViewController = controller;
    _viewModel.onMapCreated(controller);

    // Ensure the Google Navigation session is initialized
    await _viewModel.initialize();

    // Initial UI suppression and padding
    await _updateMapPadding();

    if (mounted) {
      await _viewModel.startNavigation(
        widget.destination,
        widget.simulateRoute,
        start: widget.start,
        travelMode: widget.travelMode,
      );

      // Re-apply after guidance starts to override SDK resets
      await _updateMapPadding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _viewModel.stopNavigation();
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          body: Stack(
            children: [
              GoogleMapsNavigationView(
                initialMapToolbarEnabled: !widget.useAdvancedUi,
                initialCompassEnabled: !widget.useAdvancedUi,
                onViewCreated: _onViewCreated,
                initialPadding: widget.useAdvancedUi
                    ? const EdgeInsets.only(bottom: 250)
                    : const EdgeInsets.only(top: 100, bottom: 100),
                initialNavigationUIEnabledPreference: widget.useAdvancedUi
                    ? NavigationUIEnabledPreference.automatic
                    : NavigationUIEnabledPreference.automatic,
                onPromptVisibilityChanged: (bool promptVisible) {
                  if (mounted) {
                    setState(() => _isPromptVisible = promptVisible);
                  }
                },
                onCameraMoveStarted: (CameraPosition position, bool isGesture) {
                  if (isGesture && mounted) {
                    setState(() => _isFollowing = false);
                  }
                },
              ),

              // Status Bar Blur Overlay
              if (widget.useAdvancedUi)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).padding.top,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
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
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(viewModel.errorMessage!)),
                        );
                      }
                    });
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Top Instruction Card
              if (widget.useAdvancedUi)
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    child: Consumer<NavigationViewModel>(
                      builder: (context, vm, _) {
                        final navData = vm.navData;
                        if (navData == null) return const SizedBox.shrink();
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3F51B5),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      _getManeuverIcon(navData.maneuver),
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text(
                                              navData.nextStepDistance.contains(
                                                    ' ',
                                                  )
                                                  ? navData.nextStepDistance
                                                        .split(' ')[0]
                                                  : navData.nextStepDistance,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            if (navData.nextStepDistance
                                                .contains(' '))
                                              Text(
                                                navData.nextStepDistance.split(
                                                  ' ',
                                                )[1],
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.8),
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                        Text(
                                          navData.nextStepInstruction,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                            fontSize: 18,
                                            fontWeight: FontWeight.normal,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      vm.isVoiceEnabled
                                          ? Icons.volume_up
                                          : Icons.volume_off,
                                      color: Colors.white,
                                    ),
                                    onPressed: vm.toggleVoiceGuidance,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

              // Speed Indicator
              if (!_isPromptVisible)
                Positioned(
                  left: 16,
                  bottom:
                      (widget.useAdvancedUi ? 200 : 120) +
                      60, // Move above Re-centre

                  child: Selector<NavigationViewModel, double>(
                    selector: (_, vm) => vm.currentSpeed,
                    builder: (context, speed, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              speed.toStringAsFixed(0),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3F51B5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'km/h',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // Bottom Left "Re-centre" Button
              if (!_isPromptVisible && !_isFollowing)
                Positioned(
                  left: 16,
                  bottom: widget.useAdvancedUi ? 330 : 120,
                  child: GestureDetector(
                    onTap: () {
                      _navigationViewController?.followMyLocation(
                        CameraPerspective.tilted,
                      );
                      setState(() => _isFollowing = true);
                    },

                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.navigation_outlined,
                            color: Color(0xFF00796B),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Re-centre',
                            style: TextStyle(
                              color: Color(0xFF00796B),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Floating Map Controls (Right Side)
              if (!_isPromptVisible)
                Positioned(
                  right: 30,

                  bottom: widget.useAdvancedUi ? 250 : 150,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search button (mimicking image)
                      const SizedBox(height: 12),
                      // Sound toggle button (mimicking image)
                      if (!widget.useAdvancedUi)
                        Consumer<NavigationViewModel>(
                          builder: (context, vm, _) {
                            return _MapButton(
                              icon: vm.isVoiceEnabled
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              onPressed: vm.toggleVoiceGuidance,
                            );
                          },
                        ),
                      const SizedBox(height: 12),

                      // Hazard button (mimicking image)
                    ],
                  ),
                ),

              // Bottom Arrival Card
              if (widget.useAdvancedUi && !_isPromptVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Consumer<NavigationViewModel>(
                    builder: (context, vm, _) {
                      final navData = vm.navData;
                      if (navData == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 20,
                              offset: Offset(0, -5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'TIME TO ARRIVAL',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          navData.totalTimeRemaining.contains(
                                                ' ',
                                              )
                                              ? navData.totalTimeRemaining
                                                    .split(' ')[0]
                                              : navData.totalTimeRemaining,
                                          style: const TextStyle(
                                            color: Color(0xFF1A237E),
                                            fontSize: 48,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (navData.totalTimeRemaining.contains(
                                          ' ',
                                        ))
                                          Text(
                                            navData.totalTimeRemaining.split(
                                              ' ',
                                            )[1],
                                            style: const TextStyle(
                                              color: Color(0xFF1A237E),
                                              fontSize: 24,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      navData.totalDistanceRemaining,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time,
                                          size: 18,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          navData.estimatedArrivalTime,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.share,
                                      color: Colors.white,
                                    ),
                                    label: const Text('Share ETA'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF3F51B5),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () {},
                                  ),
                                ),
                                const SizedBox(width: 16),
                                InkWell(
                                  onTap: () async {
                                    await _viewModel.stopNavigation();
                                    if (mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.stopNavigation();
    super.dispose();
  }

  IconData _getManeuverIcon(Maneuver? maneuver) {
    if (maneuver == null) return Icons.navigation;
    switch (maneuver) {
      case Maneuver.turnLeft:
      case Maneuver.turnSharpLeft:
      case Maneuver.offRampLeft:
        return Icons.turn_left;
      case Maneuver.turnRight:
      case Maneuver.turnSharpRight:
      case Maneuver.offRampRight:
        return Icons.turn_right;
      case Maneuver.turnSlightLeft:
      case Maneuver.forkLeft:
        return Icons.turn_slight_left;
      case Maneuver.turnSlightRight:
      case Maneuver.forkRight:
        return Icons.turn_slight_right;
      case Maneuver.turnUTurnClockwise:
      case Maneuver.turnUTurnCounterclockwise:
        return Icons.u_turn_left;
      case Maneuver.straight:
        return Icons.straight;
      case Maneuver.destination:
      case Maneuver.destinationLeft:
      case Maneuver.destinationRight:
        return Icons.place;
      default:
        return Icons.navigation;
    }
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MapButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87),
        onPressed: onPressed,
      ),
    );
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
