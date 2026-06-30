import 'package:firebase_database/firebase_database.dart';
import '../models/ride_request.dart';

class DatabaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Create a new Ride Request (Passenger)
  Future<String> createRideRequest({
    required double currentLat,
    required double currentLon,
    required double dropLat,
    required double dropLon,
    required String userId,
  }) async {
    final rideRef = _dbRef.child('ride_requests').push();
    final String rideId = rideRef.key!;

    final request = RideRequest(
      currentLat: currentLat,
      currentLon: currentLon,
      dropLat: dropLat,
      dropLon: dropLon,
      userId: userId,
      rideId: rideId,
      status: 'Pending',
    );

    await rideRef.set(request.toMap());
    return rideId;
  }

  // Cancel a Ride Request (Passenger)
  Future<void> cancelRideRequest(String rideId) async {
    await _dbRef.child('ride_requests').child(rideId).remove();
  }

  // Stream a single Ride Request's state (Passenger / Driver)
  Stream<RideRequest?> streamRideRequest(String rideId) {
    return _dbRef.child('ride_requests').child(rideId).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return null;
      return RideRequest.fromMap(data, rideId);
    });
  }

  // Stream all Pending Ride Requests (Driver)
  Stream<List<RideRequest>> streamPendingRides() {
    return _dbRef.child('ride_requests').onValue.map((event) {
      final List<RideRequest> rides = [];
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        data.forEach((key, value) {
          final rideMap = value as Map<dynamic, dynamic>;
          final ride = RideRequest.fromMap(rideMap, key as String);
          if (ride.status == 'Pending') {
            rides.add(ride);
          }
        });
      }
      return rides;
    });
  }

  // Accept a Ride Request (Driver)
  Future<void> acceptRideRequest(String rideId) async {
    await _dbRef.child('ride_requests').child(rideId).update({
      'status': 'Accepted',
    });
  }

  // Complete a Ride Request (Driver)
  Future<void> completeRideRequest(String rideId) async {
    await _dbRef.child('ride_requests').child(rideId).update({
      'status': 'Completed',
    });
  }
}
