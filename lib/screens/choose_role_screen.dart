import 'package:flutter/material.dart';
import 'widgets/glass_panel.dart';

class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient and decorative blur circles
          Container(
            color: const Color(0xFF0F172A),
          ),
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: size.width * 0.8,
              height: size.width * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.08),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // Brand Header
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.secondary.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.local_taxi,
                          size: 48,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Rickshaww',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Premium Ride Booking & Tracking App',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                        textAlign: Center,
                      ),
                    ],
                  ),
                  const Spacer(),

                  Text(
                    'CHOOSE YOUR ROLE',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white38,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Passenger Option Card
                  _RoleCard(
                    title: 'Passenger',
                    description: 'Book rides, track rickshaws, and travel comfortably.',
                    icon: Icons.person_pin_circle_outlined,
                    gradientColors: [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                    onTap: () {
                      Navigator.pushNamed(context, '/passenger-auth');
                    },
                  ),
                  const SizedBox(height: 20),

                  // Driver Option Card
                  _RoleCard(
                    title: 'Driver',
                    description: 'Accept passenger requests, find rides, and earn.',
                    icon: Icons.directions_car_filled_outlined,
                    gradientColors: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                    onTap: () {
                      Navigator.pushNamed(context, '/driver-auth');
                    },
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper Widget for BackdropFilter
import 'dart:ui' show ImageFilter;

class _RoleCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _RoleCard({
    Key? key,
    required this.title,
    required this.description,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: GlassPanel(
        opacity: 0.05,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(24.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24.0),
            splashColor: gradientColors.first.withOpacity(0.1),
            highlightColor: gradientColors.first.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  // Icon container with gradient background
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: gradientColors.first.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Text information
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13.0,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.3),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
