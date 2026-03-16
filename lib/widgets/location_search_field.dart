import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../services/places_service.dart';

class LocationSearchField extends StatefulWidget {
  final String label;
  final PlacesService placesService;
  final Function(PlaceModel) onPlaceSelected;

  const LocationSearchField({
    Key? key,
    required this.label,
    required this.placesService,
    required this.onPlaceSelected,
  }) : super(key: key);

  @override
  _LocationSearchFieldState createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  final TextEditingController _controller = TextEditingController();
  List<PlaceModel> _suggestions = [];
  bool _isLoading = false;

  void _onSearchChanged(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final results = await widget.placesService.getAutocomplete(query);

    if (mounted) {
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    }
  }

  void _selectPlace(PlaceModel place) {
    _controller.text = place.description;
    setState(() {
      _suggestions = [];
    });
    widget.onPlaceSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
          ),
          onChanged: _onSearchChanged,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final place = _suggestions[index];
                return ListTile(
                  title: Text(place.description),
                  onTap: () => _selectPlace(place),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
