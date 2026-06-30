import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in Passenger
  Future<User?> signInPassenger(String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (e) {
      debugPrint('Error signing in passenger: $e');
      rethrow;
    }
  }

  // Register Passenger
  Future<User?> registerPassenger(String email, String password) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (e) {
      debugPrint('Error registering passenger: $e');
      rethrow;
    }
  }

  // Sign in Driver and verify role
  Future<User?> signInDriver(String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = credential.user;
      if (user == null) throw Exception('No user found');

      // Verify that user exists in drivers node and userType is driver
      DataSnapshot snapshot = await _dbRef.child('drivers').child(user.uid).child('userType').get();
      if (snapshot.exists && snapshot.value == 'driver') {
        return user;
      } else {
        await signOut();
        throw Exception('This account is not registered as a driver.');
      }
    } catch (e) {
      debugPrint('Error signing in driver: $e');
      rethrow;
    }
  }

  // Register Driver
  Future<User?> registerDriver(String email, String password) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = credential.user;
      if (user == null) throw Exception('Driver registration failed');

      // Store driver details in database
      await _dbRef.child('drivers').child(user.uid).set({
        'userId': user.uid,
        'email': email,
        'userType': 'driver',
      });

      return user;
    } catch (e) {
      debugPrint('Error registering driver: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }
}
