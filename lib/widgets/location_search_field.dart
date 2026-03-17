import 'package:flutter/material.dart';
import '../models/place_model.dart';
import '../services/places_service.dart';

class LocationSearchField extends StatefulWidget {
  final String label;
  final String? hint;
  final String? initialValue;
  final PlacesService placesService;
  final Function(PlaceModel) onPlaceSelected;

  const LocationSearchField({
    Key? key,
    required this.label,
    this.hint,
    this.initialValue,
    required this.placesService,
    required this.onPlaceSelected,
  }) : super(key: key);

  @override
  _LocationSearchFieldState createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  late TextEditingController _controller;
  List<PlaceModel> _suggestions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(LocationSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue ?? '';
    }
  }

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
    _controller.text = place.name;
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
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          onChanged: _onSearchChanged,
        ),
        if (_suggestions.isNotEmpty)
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final place = _suggestions[index];
                  return ListTile(
                    title: Text(place.name, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    onTap: () => _selectPlace(place),
                  );
                },
              ),
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
