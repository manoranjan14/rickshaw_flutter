class RideRequest {
  double currentLat;
  double currentLon;
  double dropLat;
  double dropLon;
  String userId;
  String rideId;
  String status;

  RideRequest({
    required this.currentLat,
    required this.currentLon,
    required this.dropLat,
    required this.dropLon,
    required this.userId,
    required this.rideId,
    required this.status,
  });

  // Factory constructor to create a RideRequest from a Firebase Realtime Database map
  factory RideRequest.fromMap(Map<dynamic, dynamic> map, String id) {
    return RideRequest(
      currentLat: (map['currentLat'] as num?)?.toDouble() ?? 0.0,
      currentLon: (map['currentLon'] as num?)?.toDouble() ?? 0.0,
      dropLat: (map['dropLat'] as num?)?.toDouble() ?? 0.0,
      dropLon: (map['dropLon'] as num?)?.toDouble() ?? 0.0,
      userId: map['userId'] as String? ?? '',
      rideId: id,
      status: map['status'] as String? ?? 'Pending',
    );
  }

  // Convert a RideRequest into a Map to write to Firebase Realtime Database
  Map<String, dynamic> toMap() {
    return {
      'currentLat': currentLat,
      'currentLon': currentLon,
      'dropLat': dropLat,
      'dropLon': dropLon,
      'userId': userId,
      'rideId': rideId,
      'status': status,
    };
  }

  @override
  String toString() {
    return 'RideRequest{currentLat: $currentLat, currentLon: $currentLon, dropLat: $dropLat, dropLon: $dropLon, userId: $userId, rideId: $rideId, status: $status}';
  }
}
