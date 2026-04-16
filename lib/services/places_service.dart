import 'dart:async';

import 'package:dio/dio.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../appconstant.dart';
import '../models/place_model.dart';

class PlacesService {
  // Retrieve API key from constants instead of hardcoding
  static final String _apiKey = AppConstants.googleApiKey;

  final Dio _dio = Dio();

  Future<List<PlaceModel>> getAutocomplete(String query) async {
    if (query.isEmpty) return [];

    final String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$query&key=$_apiKey';

    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          return predictions.map((p) => PlaceModel.fromJson(p)).toList();
        }
      }
    } catch (e) {
      print('Error getting autocomplete: $e');
    }
    return [];
  }

  Future<LatLng?> getPlaceDetails(String placeId) async {
    final String url =
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId&fields=geometry&key=$_apiKey';

    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          return LatLng(latitude: location['lat'], longitude: location['lng']);
        }
      }
    } catch (e) {
      print('Error getting place details: $e');
    }
    return null;
  }
}
