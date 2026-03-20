import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/snack_bar_utils.dart';


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
  String? _connectingDeviceId;
  String? _errorMessage;


  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  void _startScanning() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
      _errorMessage = null;
    });

    try {
      await widget.startScan((results) {
        if (mounted) {
          setState(() {
            _scanResults = results;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }

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
      _connectingDeviceId = device.remoteId.str;
    });

    final success = await widget.connectToDevice(device);

    if (mounted) {
      setState(() {
        _connectingDeviceId = null;
      });
      if (success) {
        Navigator.of(context).pop(true); // Return success
      } else {
        SnackBarUtils.showStyledSnackBar(
          context,
          'Failed to connect or find UART service',
          isError: true,
        );
      }

    }
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Icon section
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _errorMessage != null
                    ? Icons.bluetooth_disabled
                    : Icons.bluetooth_searching,
                color: const Color(0xFFEF4444),
                size: 32,
              ),
            ),
            const SizedBox(height: 24),

            // Title and Description
            const Text(
              'Connect to ESP32',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ??
                  (_isScanning
                      ? 'Searching for devices...'
                      : 'Ready to scan for devices.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Scan Results List
            if (_scanResults.isNotEmpty)
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final name = result.device.platformName.isNotEmpty
                          ? result.device.platformName
                          : 'Unknown Device';

                      return ListTile(
                        leading: const Icon(
                          Icons.bluetooth_searching,
                          color: Color(0xFF3F51B5),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          result.device.remoteId.str,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: _connectingDeviceId != null
                            ? null
                            : () => _connect(result.device),
                        trailing: _connectingDeviceId == result.device.remoteId.str
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF3F51B5)),
                                ),
                              )
                            : null,
                      );

                    },
                  ),
                ),
              ),

            // Progress Indicator (Scanning only)
            if (_isScanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3F51B5)),
                ),
              ),


            // ACTION BUTTONS
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed:
                    _isScanning || _connectingDeviceId != null ? null : _startScanning,
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'Rescan',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),

            // Bottom Note Pill
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Color(0xFF3F51B5), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'NAVPRO REQUIRES A STABLE BLE CONNECTION FOR REAL-TIME TURN INSTRUCTIONS.',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B5563),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
