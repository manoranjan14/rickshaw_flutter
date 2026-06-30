import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/choose_role_screen.dart';
import 'screens/passenger/passenger_auth_screen.dart';
import 'screens/passenger/passenger_home_screen.dart';
import 'screens/driver/driver_auth_screen.dart';
import 'screens/driver/driver_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Note: Firebase.initializeApp() will use the google-services.json configuration on Android
  // or GoogleService-Info.plist configuration on iOS.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization warning: $e. Make sure you set up native configuration.');
  }

  runApp(const RickshawwApp());
}

class RickshawwApp extends StatelessWidget {
  const RickshawwApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        title: 'Rickshaww',
        debugShowCheckedModeBanner: false,
        
        // Premium Dark Theme Configuration
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6366F1), // Indigo
            secondary: Color(0xFFF59E0B), // Amber/Gold
            surface: Color(0xFF1E293B),
            background: const Color(0xFF0F172A),
            error: Color(0xFFEF4444),
          ),
          
          // Modern Typography
          textTheme: const TextTheme(
            headlineMedium: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
            titleMedium: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          
          // Reusable Widget Styling
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          ),
        ),
        
        initialRoute: '/',
        routes: {
          '/': (context) => const ChooseRoleScreen(),
          '/passenger-auth': (context) => const PassengerAuthScreen(),
          '/passenger-home': (context) => const PassengerHomeScreen(),
          '/driver-auth': (context) => const DriverAuthScreen(),
          '/driver-home': (context) => const DriverHomeScreen(),
        },
      ),
    );
  }
}
