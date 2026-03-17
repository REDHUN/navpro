import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import '../models/place_model.dart';
import '../services/places_service.dart';
import 'home_viewmodel.dart';

class PlaceSearchViewModel extends ChangeNotifier {
  final PlacesService _placesService;
  HomeViewModel _homeViewModel;

  PlaceSearchViewModel({
    required PlacesService placesService,
    required HomeViewModel homeViewModel,
  })  : _placesService = placesService,
        _homeViewModel = homeViewModel;

  void updateHomeViewModel(HomeViewModel homeVM) {
    _homeViewModel = homeVM;
  }

  List<PlaceModel> _originSuggestions = [];
  List<PlaceModel> _destinationSuggestions = [];
  bool _isLoadingOrigin = false;
  bool _isLoadingDestination = false;
  String? _errorMessage;

  List<PlaceModel> get originSuggestions => _originSuggestions;
  List<PlaceModel> get destinationSuggestions => _destinationSuggestions;
  bool get isLoadingOrigin => _isLoadingOrigin;
  bool get isLoadingDestination => _isLoadingDestination;
  String? get errorMessage => _errorMessage;

  Timer? _debounce;

  void onOriginQueryChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      _originSuggestions = [];
      notifyListeners();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      _isLoadingOrigin = true;
      _errorMessage = null;
      notifyListeners();

      try {
        _originSuggestions = await _placesService.getAutocomplete(query);
      } catch (e) {
        _errorMessage = 'Search failed: $e';
      } finally {
        _isLoadingOrigin = false;
        notifyListeners();
      }
    });
  }

  void onDestinationQueryChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      _destinationSuggestions = [];
      notifyListeners();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      _isLoadingDestination = true;
      _errorMessage = null;
      notifyListeners();

      try {
        _destinationSuggestions = await _placesService.getAutocomplete(query);
      } catch (e) {
        _errorMessage = 'Search failed: $e';
      } finally {
        _isLoadingDestination = false;
        notifyListeners();
      }
    });
  }

  Future<void> selectOrigin(PlaceModel place) async {
    _errorMessage = null;
    notifyListeners();
    try {
      final latLng = await _placesService.getPlaceDetails(place.placeId);
      if (latLng != null) {
        place.location = latLng;
        _homeViewModel.setStartLocation(place);
        // Also update HomeViewModel's LatLng directly to be sure
        _homeViewModel.onMapTap(latLng); // This is a bit hacky but ensures markers update
        // Actually HomeViewModel.setStartLocation(place) should handle it.
        // Let's refine HomeViewModel later to handle PlaceModel selection better.
      } else {
        _errorMessage = 'Could not get location details';
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
    }
    notifyListeners();
  }

  Future<void> selectDestination(PlaceModel place) async {
    _errorMessage = null;
    notifyListeners();
    try {
      final latLng = await _placesService.getPlaceDetails(place.placeId);
      if (latLng != null) {
        place.location = latLng;
        _homeViewModel.setDestination(place);
      } else {
        _errorMessage = 'Could not get location details';
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
    }
    notifyListeners();
  }

  Future<void> selectCurrentLocation(bool isOrigin) async {
    _isLoadingOrigin = isOrigin;
    _isLoadingDestination = !isOrigin;
    _errorMessage = null;
    notifyListeners();

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(latitude: position.latitude, longitude: position.longitude);
      
      final place = PlaceModel(
        name: 'Current Location',
        address: '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}',
        placeId: 'current_loc',
        location: latLng,
      );

      if (isOrigin) {
        _homeViewModel.setStartLocation(place);
      } else {
        _homeViewModel.setDestination(place);
      }
    } catch (e) {
      _errorMessage = 'Could not get current location: $e';
    } finally {
      _isLoadingOrigin = false;
      _isLoadingDestination = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
