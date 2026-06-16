import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

/// A robust ecosystem expansion service that handles long-term vehicle tracking,
/// intelligent mechanic matchmaking, and predictive maintenance logic.
class EcosystemService {
  final SupabaseClient _supabaseClient;

  EcosystemService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  /// Retrieves past diagnoses and completed repairs to give the AI context over time.
  /// Used by the diagnostic engine to analyze recurring faults.
  Future<List<Map<String, dynamic>>> getVehicleServiceHistory(String carProfileId) async {
    try {
      // Fetching the combined timeline of user symptoms and verified workshop fixes.
      final response = await _supabaseClient
          .from('chat_history')
          .select('''
            id,
            created_at,
            user_input,
            ai_response,
            resolved_cases (
              actual_fix,
              cost
            )
          ''')
          .eq('car_profile_id', carProfileId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching vehicle service history: $e');
      return [];
    }
  }

  /// Queries the Supabase 'verified_workshops' table for mechanics matching the fault category.
  Future<List<Map<String, dynamic>>> recommendLocalMechanics(String faultCategory, String city) async {
    try {
      // Query the real 'verified_workshops' Supabase table
      final response = await _supabaseClient
          .from('verified_workshops')
          .select()
          .ilike('city', '%$city%')
          .contains('specialties', [faultCategory.toLowerCase()])
          .order('rating', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error finding local mechanics: $e');
      return [];
    }
  }

  /// Triggers specific advice based on chronic issues stored in 'saved_insights'
  /// evaluated against the vehicle's current real-world mileage.
  Future<String?> checkPredictiveMaintenance(String carProfileId, int currentMileage) async {
    try {
      // 1. Resolve vehicle characteristics
      final carData = await _supabaseClient
          .from('car_profiles')
          .select('brand, model, year')
          .eq('id', carProfileId)
          .maybeSingle();

      if (carData == null) return null;

      final brand = carData['brand'];
      final model = carData['model'];

      // 2. Fetch global crowd-sourced insights specific to this chassis
      final List<dynamic> insights = await _supabaseClient
          .from('saved_insights')
          .select('issue_description, confidence_score')
          .ilike('brand', '%$brand%')
          .ilike('model', '%$model%')
          .gte('confidence_score', 0.70) // We only push verified high-probability alerts
          .limit(10);

      if (insights.isEmpty) return null;

      // 3. Execute heuristic mileage checks against known failure points
      // Note: In a complete DB schema, 'saved_insights' would feature a 'typical_failure_mileage' integer column.
      final List<String> proactiveAlerts = [];

      for (var insight in insights) {
        final issue = insight['issue_description'].toString().toLowerCase();
        
        // Heuristic Mock Rule Engine
        if (currentMileage >= 100000 && issue.contains('timing chain')) {
          proactiveAlerts.add('CRITICAL: High probability of Timing Chain stretch at $currentMileage km. Schedule an immediate inspection.');
        } else if (currentMileage >= 150000 && issue.contains('water pump')) {
          proactiveAlerts.add('PROACTIVE: Water pump failures are common for this model past 150k km. Monitor coolant levels frequently.');
        } else if (currentMileage >= 60000 && issue.contains('gearbox')) {
          proactiveAlerts.add('MAINTENANCE: Change gearbox fluid to prevent known transmission sensor faults common on this platform.');
        }
      }

      if (proactiveAlerts.isNotEmpty) {
        return proactiveAlerts.join('\n\n');
      }

      return null;
    } catch (e) {
      debugPrint('Error executing predictive maintenance scan: $e');
      return null;
    }
  }
}
