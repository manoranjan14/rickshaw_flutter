import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'widgets/glass_panel.dart';

class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Ultra-premium deep slate/black
      body: Stack(
        children: [
          // Radial glow background effects (Uber/Ola styling)
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: size.width * 0.9,
              height: size.width * 0.9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1F6366F1), // Indigo soft glow
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -80,
            child: Container(
              width: size.width * 0.9,
              height: size.width * 0.9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1AF59E0B), // Amber soft glow (Rapido yellow vibe)
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(),
              ),
            ),
          ),

          // Main Onboarding Layout
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  // Brand Hero Header
                  Column(
                    children: [
                      // Golden Auto-Rickshaw Capsule Icon
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: const Color(0x15F59E0B), // Rapido Yellow hint
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0x35F59E0B),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                              blurRadius: 24,
                              spreadRadius: 4,
                            )
                          ],
                        ),
                        child: const Icon(
                          Icons.local_taxi_rounded,
                          size: 44,
                          color: Color(0xFFF59E0B), // Rapido Accent Yellow
                        ),
                      ),
                      const SizedBox(height: 20),
                      // App Name
                      const Text(
                        'Rickshaww',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.8,
                          fontFamily: 'Montserrat', // Modern look
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Tagline
                      const Text(
                        'Modern, Safe & Instant Rickshaw Booking',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white54,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Onboarding Options Title
                  const Text(
                    'GET STARTED AS',
                    style: TextStyle(
                      color: Colors.white30,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.0,
                      letterSpacing: 2.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Passenger Selector Card
                  _RoleCard(
                    title: 'Book a Ride',
                    subtitle: 'Passenger',
                    description: 'Get affordable, doorstep auto-rickshaws. Fast, secure, and tracked live.',
                    icon: Icons.person_pin_circle_rounded,
                    accentColor: const Color(0xFF6366F1), // Indigo
                    onTap: () {
                      Navigator.pushNamed(context, '/passenger-auth');
                    },
                  ),
                  const SizedBox(height: 20),

                  // Driver Selector Card
                  _RoleCard(
                    title: 'Drive & Earn',
                    subtitle: 'Driver Partner',
                    description: 'Accept local rides, view pickup locations, and track earnings instantly.',
                    icon: Icons.sports_motorsports_rounded, // Motorsports/driver vibe
                    accentColor: const Color(0xFFF59E0B), // Gold Yellow
                    onTap: () {
                      Navigator.pushNamed(context, '/driver-auth');
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Role Card widget matching Rapido/Uber card sheets
class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _RoleCard({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: GlassPanel(
          opacity: 0.04,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(16.0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              splashColor: accentColor.withValues(alpha: 0.15),
              highlightColor: accentColor.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon Capsule
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  subtitle.toUpperCase(),
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 8.0,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11.5,
                              height: 1.45,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Action arrow
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white30,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
