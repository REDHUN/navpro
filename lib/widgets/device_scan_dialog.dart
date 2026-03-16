import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DeviceScanDialog extends StatefulWidget {
  final Future<void> Function(Function(List<ScanResult>)) startScan;
  final void Function() stopScan;
  final Future<bool> Function(BluetoothDevice) connectToDevice;

  const DeviceScanDialog({
    Key? key,
    required this.startScan,
    required this.stopScan,
    required this.connectToDevice,
  }) : super(key: key);

  @override
  _DeviceScanDialogState createState() => _DeviceScanDialogState();
}

class _DeviceScanDialogState extends State<DeviceScanDialog> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  void _startScanning() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });
    
    await widget.startScan((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
        });
      }
    });

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  @override
  void dispose() {
    widget.stopScan();
    super.dispose();
  }

  void _connect(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
    });
    
    final success = await widget.connectToDevice(device);
    
    if (mounted) {
      setState(() {
        _isConnecting = false;
      });
      if (success) {
        Navigator.of(context).pop(true); // Return success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect or find UART service')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to ESP32'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isScanning || _isConnecting)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final result = _scanResults[index];
                  final name = result.device.platformName.isNotEmpty 
                      ? result.device.platformName 
                      : 'Unknown Device';
                  
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(result.device.remoteId.str),
                    onTap: _isConnecting ? null : () => _connect(result.device),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (!_isScanning && !_isConnecting)
          TextButton(
            onPressed: _startScanning,
            child: const Text('Rescan'),
          ),
      ],
    );
  }
}
