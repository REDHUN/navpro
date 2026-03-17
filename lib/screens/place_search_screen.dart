import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/place_search_view_model.dart';

class PlaceSearchScreen extends StatefulWidget {
  final bool isOrigin;
  final String initialQuery;

  const PlaceSearchScreen({
    super.key,
    required this.isOrigin,
    this.initialQuery = '',
  });

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: widget.isOrigin ? 'Search starting point' : 'Where to?',
            hintStyle: const TextStyle(color: Color(0xFFBDBDBD)),
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20, color: Color(0xFFBDBDBD)),
                    onPressed: () {
                      _controller.clear();
                      if (widget.isOrigin) {
                        context.read<PlaceSearchViewModel>().onOriginQueryChanged('');
                      } else {
                        context.read<PlaceSearchViewModel>().onDestinationQueryChanged('');
                      }
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            if (widget.isOrigin) {
              context.read<PlaceSearchViewModel>().onOriginQueryChanged(value);
            } else {
              context.read<PlaceSearchViewModel>().onDestinationQueryChanged(value);
            }
            setState(() {});
          },
        ),
      ),
      body: Column(
        children: [
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          // Use Current Location
          ListTile(
            leading: const Icon(Icons.my_location, color: Color(0xFF1565C0)),
            title: const Text(
              'Use current location',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
            onTap: () async {
              final vm = context.read<PlaceSearchViewModel>();
              final navigator = Navigator.of(context);
              await vm.selectCurrentLocation(widget.isOrigin);
              if (mounted && vm.errorMessage == null) {
                navigator.pop();
              }
            },
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(
            child: Consumer<PlaceSearchViewModel>(
              builder: (context, vm, child) {
                final suggestions = widget.isOrigin
                    ? vm.originSuggestions
                    : vm.destinationSuggestions;
                final isLoading = widget.isOrigin
                    ? vm.isLoadingOrigin
                    : vm.isLoadingDestination;

                if (isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                if (vm.errorMessage != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        vm.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  itemBuilder: (context, index) {
                    final place = suggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.place_rounded,
                          color: Color(0xFF9E9E9E), size: 22),
                      title: Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      subtitle: place.address.isNotEmpty
                          ? Text(
                              place.address,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9E9E9E),
                              ),
                            )
                          : null,
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        if (widget.isOrigin) {
                          await vm.selectOrigin(place);
                        } else {
                          await vm.selectDestination(place);
                        }
                        if (mounted && vm.errorMessage == null) {
                          navigator.pop();
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
