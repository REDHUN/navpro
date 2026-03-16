import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/ble_service.dart';
import 'services/navigation_service.dart';
import 'services/places_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NavProApp());
}

class NavProApp extends StatefulWidget {
  const NavProApp({Key? key}) : super(key: key);

  @override
  _NavProAppState createState() => _NavProAppState();
}

class _NavProAppState extends State<NavProApp> {
  late final BleService _bleService;
  late final NavigationService _navigationService;
  late final PlacesService _placesService;

  @override
  void initState() {
    super.initState();
    _bleService = BleService();
    _navigationService = NavigationService(_bleService);
    _placesService = PlacesService();

    // Navigation SDK initialization is deferred to HomeScreen
    // after terms and location permissions are accepted.
  }

  @override
  void dispose() {
    _navigationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: _bleService),
        Provider<NavigationService>.value(value: _navigationService),
        Provider<PlacesService>.value(value: _placesService),
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

