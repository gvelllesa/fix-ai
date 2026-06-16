import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/ecosystem_service.dart';
import '../../../data/predictive_maintenance_service.dart';
import '../../live_call/screens/voice_call_screen.dart';
// Note: In a production app, you would inject EcosystemService here
// via Provider, Riverpod, or Bloc to fetch real data for these tabs.

class SmartProfileScreen extends StatefulWidget {
  final String carProfileId;

  const SmartProfileScreen({Key? key, required this.carProfileId}) : super(key: key);

  @override
  State<SmartProfileScreen> createState() => _SmartProfileScreenState();
}

class _SmartProfileScreenState extends State<SmartProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 3 Tabs: History, Specialists, Alerts
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepObsidian,
      appBar: AppBar(
        backgroundColor: AppTheme.deepObsidian,
        title: const Text(
          'Smart Vehicle Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryBlue,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.handyman), text: 'Specialists'),
            Tab(icon: Icon(Icons.notification_important), text: 'Alerts'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildPredictiveOverview(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildHistoryTab(),
                _buildSpecialistsTab(),
                _buildPredictiveAlertsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictiveOverview() {
    return FutureBuilder<Map<String, dynamic>>(
      future: PredictiveMaintenanceService().checkPredictiveAlerts(widget.carProfileId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Shimmer loading placeholder
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink(); // Fail silently on error to not break UI
        }

        final data = snapshot.data!;
        final bool shouldWarn = data['should_warn'] == true;

        if (!shouldWarn) {
          // Low-profile green banner
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6), width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vehicle Analytics: All systems optimal for this mileage.',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // High-visibility glowing card
        final warningTitle = data['warning_title'] ?? 'Impending Failure Detected';
        final List<String> steps = List<String>.from(data['preventive_action_steps'] ?? []);

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceObsidian,
              borderRadius: BorderRadius.circular(12),
              border: const Border(left: BorderSide(color: AppTheme.dynamicCrimson, width: 6)),
              boxShadow: [
                BoxShadow(color: AppTheme.dynamicCrimson.withValues(alpha: 0.2), blurRadius: 15, spreadRadius: 2)
              ]
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.dynamicCrimson, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          warningTitle,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Recommended Actions:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...steps.map((step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: AppTheme.dynamicCrimson, fontSize: 18)),
                            Expanded(child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4))),
                          ],
                        ),
                      )),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceCallScreen()));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(color: AppTheme.primaryBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.mic),
                      label: const Text('Run Voice Diagnostic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Visually displays a timeline of past issues and resolved cases
  Widget _buildHistoryTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4, // Mock count representing ecosystemService.getVehicleServiceHistory()
      itemBuilder: (context, index) {
        final isResolved = index % 2 == 0; // Mocking resolved state

        return Card(
          color: Colors.black45,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isResolved ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
              child: Icon(
                isResolved ? Icons.check_circle : Icons.pending_actions,
                color: isResolved ? Colors.green : Colors.orange,
              ),
            ),
            title: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (104 - index).toDouble()),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOutExpo,
              builder: (context, value, child) {
                return Text(
                  'Diagnostic Session #${value.toInt()}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                isResolved ? 'Resolved: Replaced Ignition Coils' : 'Symptom: Transmission Jerking',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          ),
        );
      },
    );
  }

  /// Displays the "Recommended Specialists" matchmaking logic
  Widget _buildSpecialistsTab() {
    final ecosystemService = EcosystemService();
    // In a real scenario, faultCategory and city would be dynamically passed or fetched
    const String faultCategory = 'transmission'; 
    const String city = 'Tbilisi';

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ecosystemService.recommendLocalMechanics(faultCategory, city),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading mechanics: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
        }
        
        final mechanics = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Recommended Local Mechanics\\nFault: $faultCategory | City: $city',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (mechanics.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No mechanics found for this issue.', style: TextStyle(color: Colors.white54)),
                ),
              ),
            ...mechanics.map((mechanic) {
              final specialties = (mechanic['specialties'] as List<dynamic>?)?.join(', ') ?? 'General Repair';
              final phone = mechanic['contact'] ?? '';
              
              return Card(
                color: const Color(0xFF1E1E1E), // High-tech dark-mode card
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.blueAccent, width: 0.5),
                  borderRadius: BorderRadius.circular(12)
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0xFF2C2C2C),
                        child: Icon(Icons.build_circle, color: Colors.blueAccent, size: 36),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mechanic['name'] ?? 'Unknown Workshop', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Rating: ${mechanic['rating']} ★', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Expertise: $specialties', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(mechanic['address'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.phone, color: Colors.green, size: 32),
                        onPressed: () async {
                          if (phone.isNotEmpty) {
                            final Uri callUri = Uri.parse('tel:$phone');
                            if (await canLaunchUrl(callUri)) {
                              await launchUrl(callUri);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not launch phone dialer. Check url_launcher setup.')),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  /// Displays proactive alerts generated by checkPredictiveMaintenance()
  Widget _buildPredictiveAlertsTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          color: Colors.orange.shade900.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.orange.shade700, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                    SizedBox(width: 12),
                    Text('PROACTIVE ALERT', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'Water pump failures are common for this specific model past 150k km based on global crowd-sourced data. We recommend scheduling an inspection to prevent overheating.',
                  style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
}
