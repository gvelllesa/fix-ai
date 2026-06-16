import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

class ChatDrawer extends StatelessWidget {
  const ChatDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.deepObsidian,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Text(
                    'FIX AI',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                  ),
                ],
              ),
            ),

            // New Chat Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Push or reset chat session
                },
                icon: const Icon(Icons.add),
                label: const Text('New Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppTheme.primaryBlue,
                ),
              ).animate(onPlay: (controller) => controller.repeat())
               .boxShadow(
                 begin: BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.0), blurRadius: 0, spreadRadius: 0),
                 end: BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.0), blurRadius: 0, spreadRadius: 10),
                 duration: const Duration(seconds: 2),
                 curve: Curves.easeOutCubic,
               ).fade(begin: 1, end: 0, duration: const Duration(seconds: 2)),
            ),

            const SizedBox(height: 16),

            // Navigation Area
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                children: [
                  // History
                  _buildSectionHeader('HISTORY', Icons.history),
                  _buildNavItem(context, 'N55 Engine Misfire Analysis', false),
                  _buildNavItem(context, 'ISTA Steering Rack Calibration', false),
                  const SizedBox(height: 24),

                  // My Garage
                  _buildSectionHeader('MY GARAGE', Icons.directions_car),
                  _buildNavItem(context, 'BMW X4 F26 - N55', true),
                ],
              ),
            ),

            // Footer (Profile)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.outlineVariant, width: 0.2)),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_circle, size: 20, color: AppTheme.outlineVariant),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Master Tech', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
                        Text('Profile', style: TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 20, color: AppTheme.secondaryText),
                    onPressed: () async {
                      try {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      } catch (e) {
                        debugPrint('Error signing out: $e');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.outlineVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.outlineVariant,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, String title, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.surfaceHighlight.withValues(alpha: 0.3) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? AppTheme.primaryFixedDim : AppTheme.secondaryText,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          onTap: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}
