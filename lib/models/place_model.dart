import 'package:google_navigation_flutter/google_navigation_flutter.dart';

class PlaceModel {
  final String description;
  final String placeId;
  LatLng? location;

  PlaceModel({
    required this.description,
    required this.placeId,
    this.location,
  });

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    return PlaceModel(
      description: json['description'] ?? '',
      placeId: json['place_id'] ?? '',
    );
  }
}
