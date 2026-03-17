import 'package:google_navigation_flutter/google_navigation_flutter.dart';

class PlaceModel {
  final String name;
  final String address;
  final String placeId;
  LatLng? location;

  PlaceModel({
    required this.name,
    required this.address,
    required this.placeId,
    this.location,
  });

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    // Autocomplete results often have 'structured_formatting'
    final structured = json['structured_formatting'];
    if (structured != null) {
      return PlaceModel(
        name: structured['main_text'] ?? '',
        address: structured['secondary_text'] ?? '',
        placeId: json['place_id'] ?? '',
      );
    }
    
    // Fallback or for direct details
    return PlaceModel(
      name: json['description'] ?? json['name'] ?? '',
      address: json['formatted_address'] ?? '',
      placeId: json['place_id'] ?? '',
    );
  }
}
