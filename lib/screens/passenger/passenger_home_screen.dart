import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/ride_request.dart';
import '../widgets/glass_panel.dart';
import '../widgets/custom_button.dart';

enum PassengerState {
  idle,
  confirmation,
  waiting,
  activeRide,
}

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({Key? key}) : super(key: key);

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  final MapController _mapController = MapController();
  final DatabaseService _dbService = DatabaseService();

  PassengerState _currentState = PassengerState.idle;
  Position? _currentPosition;
  LatLng? _pickupLocation;
  LatLng? _dropLocation;

  String _pickupAddress = 'Fetching location...';
  String _dropAddress = 'Loading...';

  String? _activeRideId;
  StreamSubscription<RideRequest?>? _rideSubscription;

  double _rideDistance = 0.0;
  double _rideCost = 0.0;
  bool _isGeocoding = false;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    super.dispose();
  }

  // Get current user location and permission
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied.')),
        );
      }
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = position;
      _pickupLocation = LatLng(position.latitude, position.longitude);
    });

    _mapController.move(_pickupLocation!, 16.5);
    _getPickupAddress();
  }

  Future<void> _getPickupAddress() async {
    if (_pickupLocation == null) return;
    try {
      final placemarks = await placemarkFromCoordinates(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
      );
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        setState(() {
          _pickupAddress = '${pm.name}, ${pm.locality}, ${pm.postalCode}';
        });
      }
    } catch (e) {
      setState(() {
        _pickupAddress = 'Lat: ${_pickupLocation!.latitude.toStringAsFixed(4)}, Lon: ${_pickupLocation!.longitude.toStringAsFixed(4)}';
      });
    }
  }

  Future<void> _getDropAddress() async {
    if (_dropLocation == null) return;
    setState(() => _isGeocoding = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        _dropLocation!.latitude,
        _dropLocation!.longitude,
      );
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        setState(() {
          _dropAddress = '${pm.street ?? pm.name}, ${pm.locality}, ${pm.postalCode}';
        });
      }
    } catch (e) {
      setState(() {
        _dropAddress = 'Lat: ${_dropLocation!.latitude.toStringAsFixed(4)}, Lon: ${_dropLocation!.longitude.toStringAsFixed(4)}';
      });
    } finally {
      setState(() => _isGeocoding = false);
    }
  }

  void _onMapDoubleTap(TapPosition tapPosition, LatLng latLng) {
    if (_currentState != PassengerState.idle && _currentState != PassengerState.confirmation) {
      // Prevent changing destination during active/waiting state
      return;
    }
    setState(() {
      _dropLocation = latLng;
      _currentState = PassengerState.confirmation;
    });
    _getDropAddress();
    _calculateRideMetrics();
  }

  void _calculateRideMetrics() {
    if (_pickupLocation == null || _dropLocation == null) return;

    // Calculate Haversine distance
    final Distance distance = const Distance();
    final double meter = distance(_pickupLocation!, _dropLocation!);
    setState(() {
      _rideDistance = meter / 1000.0;
      _rideCost = _rideDistance * 50.0; // 50 Rupees per km
    });
  }

  // Request a Ride
  Future<void> _requestRide() async {
    if (_pickupLocation == null || _dropLocation == null) return;
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid ?? 'unknown_user';

    try {
      final rideId = await _dbService.createRideRequest(
        currentLat: _pickupLocation!.latitude,
        currentLon: _pickupLocation!.longitude,
        dropLat: _dropLocation!.latitude,
        dropLon: _dropLocation!.longitude,
        userId: userId,
      );

      setState(() {
        _activeRideId = rideId;
        _currentState = PassengerState.waiting;
      });

      _listenToRideRequest(rideId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to confirm ride: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Listen to active ride updates
  void _listenToRideRequest(String rideId) {
    _rideSubscription?.cancel();
    _rideSubscription = _dbService.streamRideRequest(rideId).listen((ride) {
      if (ride == null) {
        // Ride was deleted (cancelled by driver or user elsewhere)
        _resetToIdle('Your ride was cancelled.');
        return;
      }

      if (ride.status == 'Accepted' && _currentState == PassengerState.waiting) {
        setState(() {
          _currentState = PassengerState.activeRide;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A driver has accepted your ride request!'), backgroundColor: Colors.indigo),
        );
      } else if (ride.status == 'Completed') {
        _showRideCompletedDialog();
      }
    });
  }

  Future<void> _cancelRide() async {
    if (_activeRideId == null) return;
    try {
      await _dbService.cancelRideRequest(_activeRideId!);
      _resetToIdle('Ride cancelled successfully.');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel ride: $e')),
      );
    }
  }

  void _resetToIdle(String message) {
    _rideSubscription?.cancel();
    setState(() {
      _currentState = PassengerState.idle;
      _dropLocation = null;
      _activeRideId = null;
      _rideDistance = 0.0;
      _rideCost = 0.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showRideCompletedDialog() {
    _rideSubscription?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
        title: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 28),
            SizedBox(width: 12),
            Text('Ride Completed', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thank you for using Rickshaww! Your ride has been successfully completed.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Text(
              'Total Cost: ₹${_rideCost.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _currentState = PassengerState.idle;
                _dropLocation = null;
                _activeRideId = null;
                _rideDistance = 0.0;
                _rideCost = 0.0;
              });
            },
            child: const Text('OK', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleLogout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // Compile map markers
    final markers = <Marker>[];
    if (_pickupLocation != null) {
      markers.add(
        Marker(
          point: _pickupLocation!,
          width: 60,
          height: 60,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
                child: const Icon(Icons.person_pin, color: Colors.white, size: 20),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.indigo, size: 15),
            ],
          ),
        ),
      );
    }
    if (_dropLocation != null) {
      markers.add(
        Marker(
          point: _dropLocation!,
          width: 60,
          height: 60,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: const Icon(Icons.location_on, color: Colors.white, size: 20),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.redAccent, size: 15),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickupLocation ?? const LatLng(20.5937, 78.9629), // default center of India
              initialZoom: 15.0,
              onDoubleTap: _onMapDoubleTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.rickshawflutter',
              ),
              if (_pickupLocation != null && _dropLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_pickupLocation!, _dropLocation!],
                      color: Colors.indigo,
                      strokeWidth: 4.5,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Custom Top App Bar (Floating)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              children: [
                // Logout Button / Menu
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                    onPressed: _handleLogout,
                  ),
                ),
                const SizedBox(width: 12),
                // Heading Indicator Box
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.gps_fixed, color: Colors.indigoAccent, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Double-Tap Map to Set Drop Pin',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating Action Button for current location centering
          Positioned(
            right: 20,
            bottom: _currentState == PassengerState.idle ? 40 : 250,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              onPressed: () {
                if (_pickupLocation != null) {
                  _mapController.move(_pickupLocation!, 16.5);
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          // Glassmorphic Overlays (Floating panels at the bottom)
          if (_currentState == PassengerState.confirmation)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildConfirmationPanel(theme),
            ),

          if (_currentState == PassengerState.waiting)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildWaitingPanel(theme),
            ),

          if (_currentState == PassengerState.activeRide)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildActiveRidePanel(theme),
            ),
        ],
      ),
    );
  }

  Widget _buildConfirmationPanel(ThemeData theme) {
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('RIDE OVERVIEW', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded, color: Colors.white38),
                onPressed: () => setState(() => _currentState = PassengerState.idle),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Location Details
          _buildAddressRow(Icons.radio_button_checked, Colors.indigoAccent, 'Pickup', _pickupAddress),
          const SizedBox(height: 12),
          _buildAddressRow(Icons.place, Colors.redAccent, 'Drop-off', _dropAddress, isLoading: _isGeocoding),
          const Divider(color: Colors.white12, height: 24),
          // Cost Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estimated Cost', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₹${_rideCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Distance', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${_rideDistance.toStringAsFixed(1)} km', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Confirm & Book Ride',
            onPressed: _requestRide,
            gradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
            icon: Icons.check,
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingPanel(ThemeData theme) {
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Searching for Drivers...',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.amber)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Your request has been broadcasted to nearby rickshaws. Please wait a moment.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Cancel Request',
            onPressed: _cancelRide,
            gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
            icon: Icons.cancel_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRidePanel(ThemeData theme) {
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('RIDE IN PROGRESS', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAddressRow(Icons.radio_button_checked, Colors.indigoAccent, 'Pickup', _pickupAddress),
          const SizedBox(height: 12),
          _buildAddressRow(Icons.place, Colors.redAccent, 'Drop-off', _dropAddress),
          const Divider(color: Colors.white12, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Fare', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₹${_rideCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
              const Text('Driver is on the way', style: TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(IconData icon, Color color, String title, String address, {bool isLoading = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(Colors.white38)),
                    )
                  : Text(
                      address,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ],
          ),
        ),
      ],
    );
  }
}
