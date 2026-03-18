import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/ble_service.dart';
import 'services/navigation_service.dart';
import 'services/places_service.dart';
import 'services/permission_service.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/navigation_viewmodel.dart';
import 'viewmodels/place_search_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NavProApp());
}

class NavProApp extends StatefulWidget {
  const NavProApp({Key? key}) : super(key: key);

  @override
  _NavProAppState createState() => _NavProAppState();
}

class _NavProAppState extends State<NavProApp> with WidgetsBindingObserver {
  late final BleService _bleService;
  late final NavigationService _navigationService;
  late final PlacesService _placesService;
  late final PermissionService _permissionService;
  
  static const _channel = MethodChannel('com.example.navprov2/navigation');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleService = BleService();
    _navigationService = NavigationService(_bleService);
    _placesService = PlacesService();
    _permissionService = PermissionService();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Force kill the process on detach to stop sticky foreground services
      _channel.invokeMethod('forceStopNavigation');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: _bleService),
        Provider<NavigationService>.value(value: _navigationService),
        Provider<PlacesService>.value(value: _placesService),
        Provider<PermissionService>.value(value: _permissionService),
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => HomeViewModel(
            bleService: _bleService,
            navigationService: _navigationService,
            placesService: _placesService,
            permissionService: _permissionService,
          ),
        ),
        ChangeNotifierProvider<NavigationViewModel>(
          create: (_) => NavigationViewModel(
            navigationService: _navigationService,
          ),
        ),
        ChangeNotifierProxyProvider<HomeViewModel, PlaceSearchViewModel>(
          create: (context) => PlaceSearchViewModel(
            placesService: context.read<PlacesService>(),
            homeViewModel: context.read<HomeViewModel>(),
          ),
          update: (context, homeVM, searchVM) => searchVM!..updateHomeViewModel(homeVM),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NavPro V2',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
