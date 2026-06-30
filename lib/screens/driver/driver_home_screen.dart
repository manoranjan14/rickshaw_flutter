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

enum DriverState {
  searching,
  rideSelected,
  activeRide,
}

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({Key? key}) : super(key: key);

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final MapController _mapController = MapController();
  final DatabaseService _dbService = DatabaseService();

  DriverState _currentState = DriverState.searching;
  Position? _currentPosition;
  LatLng? _driverLocation;

  List<RideRequest> _pendingRides = [];
  RideRequest? _selectedRide;
  StreamSubscription<List<RideRequest>>? _pendingRidesSubscription;
  StreamSubscription<Position>? _locationSubscription;

  String _pickupAddress = 'Loading...';
  String _dropAddress = 'Loading...';
  double _rideDistance = 0.0;
  double _rideCost = 0.0;
  bool _isGeocoding = false;

  // UI State: Online / Offline toggle
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
    _listenToPendingRides();
  }

  @override
  void dispose() {
    _pendingRidesSubscription?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  // Location tracking for driver
  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Get initial position
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = pos;
      _driverLocation = LatLng(pos.latitude, pos.longitude);
    });
    _mapController.move(_driverLocation!, 15.0);

    // Track real-time position updates
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) {
      if (mounted && _isOnline) {
        setState(() {
          _currentPosition = position;
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  // Listen to pending requests from Firebase
  void _listenToPendingRides() {
    _pendingRidesSubscription?.cancel();
    _pendingRidesSubscription = _dbService.streamPendingRides().listen((rides) {
      if (_currentState == DriverState.searching && _isOnline) {
        setState(() {
          _pendingRides = rides;
        });
      }
    });
  }

  Future<void> _geocodeLocations(RideRequest ride) async {
    setState(() {
      _isGeocoding = true;
      _pickupAddress = 'Resolving pickup address...';
      _dropAddress = 'Resolving drop address...';
    });

    try {
      final pickupPlacemarks = await placemarkFromCoordinates(ride.currentLat, ride.currentLon);
      final dropPlacemarks = await placemarkFromCoordinates(ride.dropLat, ride.dropLon);

      if (mounted) {
        setState(() {
          if (pickupPlacemarks.isNotEmpty) {
            final pm = pickupPlacemarks.first;
            _pickupAddress = '${pm.name}, ${pm.locality}, ${pm.postalCode}';
          }
          if (dropPlacemarks.isNotEmpty) {
            final pm = dropPlacemarks.first;
            _dropAddress = '${pm.street ?? pm.name}, ${pm.locality}, ${pm.postalCode}';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pickupAddress = 'Lat: ${ride.currentLat.toStringAsFixed(4)}, Lon: ${ride.currentLon.toStringAsFixed(4)}';
          _dropAddress = 'Lat: ${ride.dropLat.toStringAsFixed(4)}, Lon: ${ride.dropLon.toStringAsFixed(4)}';
        });
      }
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  void _selectRide(RideRequest ride) {
    setState(() {
      _selectedRide = ride;
      _currentState = DriverState.rideSelected;
    });

    // Haversine calculation
    final Distance distance = const Distance();
    final double meter = distance(
      LatLng(ride.currentLat, ride.currentLon),
      LatLng(ride.dropLat, ride.dropLon),
    );
    setState(() {
      _rideDistance = meter / 1000.0;
      _rideCost = _rideDistance * 12.0 + 40.0; // Standard Eco Auto tier calculation
    });

    _geocodeLocations(ride);
  }

  Future<void> _acceptRide() async {
    if (_selectedRide == null) return;
    try {
      await _dbService.acceptRideRequest(_selectedRide!.rideId);
      setState(() {
        _currentState = DriverState.activeRide;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride accepted! Navigate to pickup location.'),
          backgroundColor: Colors.amber,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept ride: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _completeRide() async {
    if (_selectedRide == null) return;
    try {
      await _dbService.completeRideRequest(_selectedRide!.rideId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride completed successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _currentState = DriverState.searching;
        _selectedRide = null;
        _rideCost = 0.0;
        _rideDistance = 0.0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete ride: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleLogout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _toggleOnlineState(bool online) {
    setState(() {
      _isOnline = online;
      if (!online) {
        _pendingRides = [];
        _selectedRide = null;
        _currentState = DriverState.searching;
      }
    });
    if (online) {
      _startLocationTracking();
      _listenToPendingRides();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prepare markers based on state
    final markers = <Marker>[];

    // Add Driver Location Marker (Offline shows grey, Online shows amber)
    if (_driverLocation != null) {
      markers.add(
        Marker(
          point: _driverLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: _isOnline ? const Color(0xFFFBBF24).withValues(alpha: 0.25) : Colors.white10,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: BoxDecoration(
                color: _isOnline ? const Color(0xFFF59E0B) : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }

    if (_isOnline) {
      if (_currentState == DriverState.searching) {
        // Show pending ride locations
        for (final ride in _pendingRides) {
          markers.add(
            Marker(
              point: LatLng(ride.currentLat, ride.currentLon),
              width: 48,
              height: 48,
              child: GestureDetector(
                onTap: () => _selectRide(ride),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(Icons.person_pin_circle_rounded, color: Color(0xFFEF4444), size: 26),
                  ),
                ),
              ),
            ),
          );
        }
      } else if (_selectedRide != null) {
        // Show route markers
        markers.add(
          Marker(
            point: LatLng(_selectedRide!.currentLat, _selectedRide!.currentLon),
            width: 48,
            height: 48,
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
              child: const Icon(Icons.radio_button_checked_rounded, color: Colors.white, size: 20),
            ),
          ),
        );
        markers.add(
          Marker(
            point: LatLng(_selectedRide!.dropLat, _selectedRide!.dropLon),
            width: 48,
            height: 48,
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              child: const Icon(Icons.place_rounded, color: Colors.white, size: 20),
            ),
          ),
        );
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _driverLocation ?? const LatLng(20.5937, 78.9629),
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.myapplication',
              ),
              if (_isOnline && _currentState != DriverState.searching && _selectedRide != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(_selectedRide!.currentLat, _selectedRide!.currentLon),
                        LatLng(_selectedRide!.dropLat, _selectedRide!.dropLon),
                      ],
                      color: const Color(0xFFF59E0B),
                      strokeWidth: 4.5,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Uber-style Online/Offline Top Switch
          Positioned(
            top: 54,
            left: 20,
            right: 20,
            child: Row(
              children: [
                // Logout trigger
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF131926),
                  child: IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20),
                    onPressed: _handleLogout,
                  ),
                ),
                const SizedBox(width: 12),

                // Online/Offline Pill Selector
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF131926),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Offline Toggle Button
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _toggleOnlineState(false),
                            child: Container(
                              height: 44,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: !_isOnline ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'OFFLINE',
                                style: TextStyle(
                                  color: !_isOnline ? Colors.grey[400] : Colors.white24,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Online Toggle Button
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _toggleOnlineState(true),
                            child: Container(
                              height: 44,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: _isOnline ? const Color(0xFFF59E0B) : Colors.transparent,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: _isOnline
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        )
                                      ]
                                    : [],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'GO ONLINE',
                                style: TextStyle(
                                  color: _isOnline ? Colors.black : Colors.white24,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Offline Dimming Mask
          if (!_isOnline)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131926),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.wifi_off_rounded, color: Colors.white30, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'You are Offline',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Toggle the "GO ONLINE" switch at the top to receive incoming passenger requests.',
                          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Searching overlay indicator (only when online and idle)
          if (_isOnline && _currentState == DriverState.searching)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24.0),
                  child: GlassPanel(
                    opacity: 0.05,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    borderRadius: BorderRadius.circular(24.0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Finding requests...',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Requests will appear as red pins on the map',
                                style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${_pendingRides.length} active',
                          style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Center Location FAB
          if (_isOnline)
            Positioned(
              right: 20,
              bottom: _currentState == DriverState.searching ? 100 : 340,
              child: FloatingActionButton(
                backgroundColor: const Color(0xFF131926),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: const CircleBorder(),
                onPressed: () {
                  if (_driverLocation != null) {
                    _mapController.move(_driverLocation!, 15.0);
                  }
                },
                child: const Icon(Icons.gps_fixed_rounded, color: Color(0xFFF59E0B)),
              ),
            ),

          // Interactive bottom sheets
          if (_isOnline && _currentState == DriverState.rideSelected)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _buildDetailsPanel(),
            ),

          if (_isOnline && _currentState == DriverState.activeRide)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _buildActiveRidePanel(),
            ),
        ],
      ),
    );
  }

  // Incoming Request card with Swipe-To-Accept
  Widget _buildDetailsPanel() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30.0),
        child: GlassPanel(
          opacity: 0.05,
          padding: const EdgeInsets.all(22.0),
          borderRadius: BorderRadius.circular(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      'INCOMING RIDE REQUEST',
                      style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _currentState = DriverState.searching),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.close_rounded, color: Colors.white60, size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Pickup & Drop
              _buildAddressRow(Icons.radio_button_checked_rounded, const Color(0xFF6366F1), 'PICKUP FROM', _pickupAddress),
              const SizedBox(height: 12),
              _buildAddressRow(Icons.place_rounded, const Color(0xFFEF4444), 'DROP OFF TO', _dropAddress, isLoading: _isGeocoding),

              const Divider(color: Colors.white10, height: 28),

              // Ride Metrics Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('YOUR NET EARNING', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '₹${_rideCost.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('RIDE DISTANCE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '${_rideDistance.toStringAsFixed(1)} km',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Swipe to Accept Button
              SwipeToAcceptButton(
                onAccepted: _acceptRide,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Active Ride Panel
  Widget _buildActiveRidePanel() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30.0),
        child: GlassPanel(
          opacity: 0.05,
          padding: const EdgeInsets.all(22.0),
          borderRadius: BorderRadius.circular(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      'ACTIVE TRIP IN PROGRESS',
                      style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildAddressRow(Icons.radio_button_checked_rounded, const Color(0xFF6366F1), 'PICKING UP FROM', _pickupAddress),
              const SizedBox(height: 12),
              _buildAddressRow(Icons.place_rounded, const Color(0xFFEF4444), 'DELIVERING TO', _dropAddress),
              const Divider(color: Colors.white10, height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FARE VALUE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('₹${_rideCost.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 20, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const Text('Navigating towards drop-off', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: 'End Trip & Complete',
                onPressed: _completeRide,
                gradient: const [Color(0xFF10B981), Color(0xFF059669)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressRow(IconData icon, Color color, String title, String address, {bool isLoading = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(Colors.white38)),
                    )
                  : Text(
                      address,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3, fontWeight: FontWeight.w500),
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

// Custom interactive Swipe to Accept slider (prevent accidental clicks)
class SwipeToAcceptButton extends StatefulWidget {
  final VoidCallback onAccepted;
  const SwipeToAcceptButton({Key? key, required this.onAccepted}) : super(key: key);

  @override
  State<SwipeToAcceptButton> createState() => _SwipeToAcceptButtonState();
}

class _SwipeToAcceptButtonState extends State<SwipeToAcceptButton> {
  double _position = 0.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.15)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSlide = constraints.maxWidth - 58;
          return Stack(
            children: [
              // Background Slide instructions
              const Center(
                child: Text(
                  'SWIPE RIGHT TO ACCEPT',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              // Slidable Knob
              Positioned(
                left: _position,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _position = (_position + details.delta.dx).clamp(0.0, maxSlide);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_position >= maxSlide * 0.8) {
                      widget.onAccepted();
                    }
                    setState(() {
                      _position = 0.0;
                    });
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    margin: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 24),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
