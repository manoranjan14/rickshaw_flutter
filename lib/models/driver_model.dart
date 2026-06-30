class DriverModel {
  final String userId;
  final String email;
  final String userType;

  DriverModel({
    required this.userId,
    required this.email,
    this.userType = 'driver',
  });

  factory DriverModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return DriverModel(
      userId: id,
      email: map['email'] as String? ?? '',
      userType: map['userType'] as String? ?? 'driver',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'email': email,
      'userType': userType,
    };
  }
}
