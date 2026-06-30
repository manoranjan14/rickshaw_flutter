import 'dart:async';
import 'dart:math' as math;
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

class _PassengerHomeScreenState extends State<PassengerHomeScreen> with TickerProviderStateMixin {
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
  bool _isMapReady = false;

  // UI State: selected category (Eco, Premium, Shared)
  String _selectedCategory = 'Eco';

  // Animation controller for search radar pulse
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    _rideSubscription?.cancel();
    super.dispose();
  }

  // Get current user location and permission
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
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

      if (_isMapReady) {
        _mapController.move(_pickupLocation!, 16.5);
      }
      _getPickupAddress();
    } catch (e) {
      debugPrint('Error determining location: $e');
    }
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

  void _onMapLongPress(TapPosition tapPosition, LatLng latLng) {
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
    _rideDistance = meter / 1000.0;
    _updatePricing();
  }

  void _updatePricing() {
    setState(() {
      if (_selectedCategory == 'Eco') {
        _rideCost = _rideDistance * 12.0 + 40.0; // Min ₹40, ₹12/km
      } else if (_selectedCategory == 'Premium') {
        _rideCost = _rideDistance * 15.0 + 60.0; // Min ₹60, ₹15/km
      } else {
        _rideCost = _rideDistance * 8.0 + 25.0; // Min ₹25, ₹8/km
      }
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
          const SnackBar(
            content: Text('A driver has accepted your ride request!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
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
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showRideCompletedDialog() {
    _rideSubscription?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131926),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28.0),
          side: const BorderSide(color: Colors.white10),
        ),
        title: Row(
          children: const [
            Icon(Icons.stars_rounded, color: Color(0xFFFBBF24), size: 30),
            SizedBox(width: 12),
            Text('Ride Completed!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thank you for riding with Rickshaww. Hope you had a comfortable journey!',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Fare Paid', style: TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(
                    '₹${_rideCost.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 22),
                  ),
                ],
              ),
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
            child: const Text(
              'Done',
              style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.w800, fontSize: 16),
            ),
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
    // Compile map markers
    final markers = <Marker>[];
    if (_pickupLocation != null) {
      markers.add(
        Marker(
          point: _pickupLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF818CF8).withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
    }
    if (_dropLocation != null) {
      markers.add(
        Marker(
          point: _dropLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.place_rounded, color: Colors.white, size: 18),
            ),
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
              initialCenter: _pickupLocation ?? const LatLng(20.5937, 78.9629),
              initialZoom: 15.0,
              onLongPress: _onMapLongPress,
              onMapReady: () {
                setState(() => _isMapReady = true);
                if (_pickupLocation != null) {
                  _mapController.move(_pickupLocation!, 16.5);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.myapplication',
              ),
              if (_pickupLocation != null && _dropLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_pickupLocation!, _dropLocation!],
                      color: const Color(0xFF6366F1),
                      strokeWidth: 4.5,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Uber-style Floating Top Header (Profile + Search Input)
          if (_currentState == PassengerState.idle)
            Positioned(
              top: 54,
              left: 20,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28.0),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28.0),
                  child: GlassPanel(
                    opacity: 0.08,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    borderRadius: BorderRadius.circular(28.0),
                    child: Row(
                      children: [
                        // Profile Avatar / Logout trigger
                        GestureDetector(
                          onTap: _handleLogout,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            child: const Icon(Icons.logout_rounded, color: Color(0xFF818CF8), size: 18),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Simulated Search Bar
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Where to?',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Long-press map to drop destination pin',
                                style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.search_rounded, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Target Pin Info Tooltip (Only shown during active pin selecting or confirmation)
          if (_currentState == PassengerState.confirmation)
            Positioned(
              top: 54,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131926).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.location_searching_rounded, color: Color(0xFFEF4444), size: 14),
                      SizedBox(width: 8),
                      Text(
                        'Confirming Destination Pin',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Centering GPS FAB
          Positioned(
            right: 20,
            bottom: _currentState == PassengerState.idle ? 40 : 340,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF131926),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              onPressed: () {
                if (_pickupLocation != null) {
                  _mapController.move(_pickupLocation!, 16.5);
                }
              },
              child: const Icon(Icons.gps_fixed_rounded, color: Color(0xFF818CF8)),
            ),
          ),

          // Ola/Uber Style Bottom Sheets
          if (_currentState == PassengerState.confirmation)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _buildConfirmationPanel(),
            ),

          if (_currentState == PassengerState.waiting)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _buildWaitingPanel(),
            ),

          if (_currentState == PassengerState.activeRide)
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

  // Redesigned Confirmation Panel (Ola style multi-tier vehicle selector)
  Widget _buildConfirmationPanel() {
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Ride Tier',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _currentState = PassengerState.idle),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.close_rounded, color: Colors.white60, size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Horizontal Category Cards Selector
              Row(
                children: [
                  _buildCategoryCard('Eco', 'Rickshaw Eco', 'Standard Auto', 3),
                  const SizedBox(width: 8),
                  _buildCategoryCard('Premium', 'Rickshaw Prime', 'Premium Ride', 3),
                  const SizedBox(width: 8),
                  _buildCategoryCard('Shared', 'Rickshaw Share', 'Shared Fare', 2),
                ],
              ),
              const SizedBox(height: 18),

              // Route details
              _buildAddressRow(Icons.radio_button_checked, const Color(0xFF6366F1), 'PICKUP FROM', _pickupAddress),
              const SizedBox(height: 12),
              _buildAddressRow(Icons.place, const Color(0xFFEF4444), 'DROP OFF AT', _dropAddress, isLoading: _isGeocoding),

              const Divider(color: Colors.white10, height: 28),

              // Final Details & Booking Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL EST. FARE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
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
                      const Text('DISTANCE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '${_rideDistance.toStringAsFixed(1)} km',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: 'Confirm Booking • $_selectedCategory',
                onPressed: _requestRide,
                gradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Category Selector Card Widget
  Widget _buildCategoryCard(String id, String label, String sub, int cap) {
    final isSelected = _selectedCategory == id;
    final accent = id == 'Eco'
        ? const Color(0xFF818CF8)
        : id == 'Premium'
            ? const Color(0xFFFBBF24)
            : const Color(0xFF34D399);

    double tempCost = 0.0;
    if (id == 'Eco') {
      tempCost = _rideDistance * 12.0 + 40.0;
    } else if (id == 'Premium') {
      tempCost = _rideDistance * 15.0 + 60.0;
    } else {
      tempCost = _rideDistance * 8.0 + 25.0;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedCategory = id;
          });
          _updatePricing();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.015),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? accent : Colors.white.withValues(alpha: 0.05),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.local_taxi_rounded,
                color: isSelected ? accent : Colors.white38,
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '₹${tempCost.toStringAsFixed(0)}',
                style: TextStyle(
                  color: isSelected ? accent : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Redesigned Waiting Panel (Rapido style radar animation)
  Widget _buildWaitingPanel() {
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
          padding: const EdgeInsets.all(24.0),
          borderRadius: BorderRadius.circular(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Circular Pulse Radar Visual
              Center(
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Animated pulse rings
                      AnimatedBuilder(
                        animation: _radarController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: List.generate(3, (index) {
                              final delayValue = (index * 0.33);
                              double val = _radarController.value - delayValue;
                              if (val < 0) val += 1.0;
                              return Container(
                                width: 90 * val,
                                height: 90 * val,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF6366F1).withValues(alpha: 1.0 - val),
                                    width: 2.0,
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                      // Core Rickshaw Finder Icon
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF6366F1),
                        child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Searching for Drivers...',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Broadcasting request to nearby Rickshaw partners',
                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Cancel Request',
                onPressed: _cancelRide,
                gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Redesigned Active Ride Panel (Uber style driver info profile card)
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
          padding: const EdgeInsets.all(24.0),
          borderRadius: BorderRadius.circular(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Badge Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      'DRIVER ON THE WAY',
                      style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Driver profile card (Uber/Ola format)
              Row(
                children: [
                  // Profile Photo
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF818CF8), width: 1.5),
                    ),
                    child: const CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white10,
                      child: Icon(Icons.person, color: Colors.white70, size: 28),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Name & Star Rating
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ramesh Kumar', // Static placeholder matching Uber/Ola premium experience
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                            SizedBox(width: 4),
                            Text(
                              '4.9 (248 rides)',
                              style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Vehicle Registration Plate Tag
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'MH 12 AB 1234',
                          style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Bajaj RE Auto',
                        style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(color: Colors.white10, height: 28),

              // Driver Actions Row
              Row(
                children: [
                  // Call button
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: TextButton.icon(
                        onPressed: () {
                          // Call driver trigger
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Calling driver...'), behavior: SnackBarBehavior.floating),
                          );
                        },
                        icon: const Icon(Icons.call_rounded, color: Color(0xFF818CF8), size: 18),
                        label: const Text(
                          'Call Partner',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Cancel button
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
                      ),
                      child: TextButton.icon(
                        onPressed: _cancelRide,
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 18),
                        label: const Text(
                          'Cancel Ride',
                          style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
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
