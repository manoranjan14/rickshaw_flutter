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
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  // Listen to pending requests from Firebase
  void _listenToPendingRides() {
    _pendingRidesSubscription = _dbService.streamPendingRides().listen((rides) {
      if (_currentState == DriverState.searching) {
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
      _rideCost = _rideDistance * 50.0;
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
        const SnackBar(content: Text('Ride accepted! Navigate to pickup location.'), backgroundColor: Colors.amber),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept ride: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _completeRide() async {
    if (_selectedRide == null) return;
    try {
      await _dbService.completeRideRequest(_selectedRide!.rideId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride completed successfully!'), backgroundColor: Colors.green),
      );
      setState(() {
        _currentState = DriverState.searching;
        _selectedRide = null;
        _rideCost = 0.0;
        _rideDistance = 0.0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete ride: $e'), backgroundColor: Colors.redAccent),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // Prepare markers based on state
    final markers = <Marker>[];

    // Add Driver Location Marker
    if (_driverLocation != null) {
      markers.add(
        Marker(
          point: _driverLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 24),
          ),
        ),
      );
    }

    if (_currentState == DriverState.searching) {
      // Show all pending ride requests on the map
      for (final ride in _pendingRides) {
        markers.add(
          Marker(
            point: LatLng(ride.currentLat, ride.currentLon),
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: () => _selectRide(ride),
              child: Container(
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 28),
              ),
            ),
          ),
        );
      }
    } else if (_selectedRide != null) {
      // Active or Selected Ride markers
      markers.add(
        Marker(
          point: LatLng(_selectedRide!.currentLat, _selectedRide!.currentLon),
          width: 50,
          height: 50,
          child: Container(
            decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
            child: const Icon(Icons.radio_button_checked, color: Colors.white, size: 24),
          ),
        ),
      );
      markers.add(
        Marker(
          point: LatLng(_selectedRide!.dropLat, _selectedRide!.dropLon),
          width: 50,
          height: 50,
          child: Container(
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            child: const Icon(Icons.location_on, color: Colors.white, size: 24),
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
              initialCenter: _driverLocation ?? const LatLng(20.5937, 78.9629),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.rickshawflutter',
              ),
              if (_currentState != DriverState.searching && _selectedRide != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(_selectedRide!.currentLat, _selectedRide!.currentLon),
                        LatLng(_selectedRide!.dropLat, _selectedRide!.dropLon),
                      ],
                      color: Colors.amber,
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
                // Logout Button
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
                      children: [
                        const Icon(Icons.radar_rounded, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _currentState == DriverState.searching
                              ? 'Scanning for Passengers...'
                              : _currentState == DriverState.rideSelected
                                  ? 'Reviewing Request'
                                  : 'Active Ride',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Center Location FAB
          Positioned(
            right: 20,
            bottom: _currentState == DriverState.searching ? 40 : 260,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              onPressed: () {
                if (_driverLocation != null) {
                  _mapController.move(_driverLocation!, 15.0);
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          // Glassmorphic Details panel
          if (_currentState == DriverState.rideSelected)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildDetailsPanel(theme),
            ),

          if (_currentState == DriverState.activeRide)
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

  Widget _buildDetailsPanel(ThemeData theme) {
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('NEW RIDE REQUEST', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded, color: Colors.white38),
                onPressed: () => setState(() => _currentState = DriverState.searching),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAddressRow(Icons.radio_button_checked, Colors.indigoAccent, 'Pickup From', _pickupAddress),
          const SizedBox(height: 12),
          _buildAddressRow(Icons.place, Colors.redAccent, 'Drop-off To', _dropAddress, isLoading: _isGeocoding),
          const Divider(color: Colors.white12, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Passenger Fare', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₹${_rideCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amberAccent, fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Distance', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${_rideDistance.toStringAsFixed(1)} km', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Accept Ride & Navigate',
            onPressed: _acceptRide,
            gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            icon: Icons.check,
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
                child: const Text('ON THE ROAD', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAddressRow(Icons.radio_button_checked, Colors.indigoAccent, 'Pickup From', _pickupAddress),
          const SizedBox(height: 12),
          _buildAddressRow(Icons.place, Colors.redAccent, 'Drop-off To', _dropAddress),
          const Divider(color: Colors.white12, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ride Value', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('₹${_rideCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
              const Text('Transporting Passenger', style: TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
            ],
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Complete Ride',
            onPressed: _completeRide,
            gradient: const [Color(0xFF10B981), const Color(0xFF059669)],
            icon: Icons.done_all_rounded,
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
