import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported application languages.
enum AppLanguage {
  geo('ქართული', 'ka', 'GE'),
  eng('English', 'en', 'US');

  final String displayName;
  final String languageCode;
  final String countryCode;

  const AppLanguage(this.displayName, this.languageCode, this.countryCode);

  Locale get locale => Locale(languageCode, countryCode);
}

/// Central Language & Localization Controller.
///
/// Features:
/// 1. App-wide language state management (Georgian & English).
/// 2. Instant reactive UI updates across all listening widgets.
/// 3. Persistent language preference via SharedPreferences.
/// 4. Comprehensive technical dictionary for all automotive modules.
class LanguageController extends ChangeNotifier {
  static final LanguageController instance = LanguageController._();

  LanguageController._();

  factory LanguageController() => instance;

  static const String _prefKey = 'app_language_preference';
  AppLanguage _currentLanguage = AppLanguage.geo;
  bool _isInitialized = false;

  AppLanguage get currentLanguage => _currentLanguage;
  bool get isGeorgian => _currentLanguage == AppLanguage.geo;
  bool get isEnglish => _currentLanguage == AppLanguage.eng;
  Locale get locale => _currentLanguage.locale;

  /// Initializes language preference from local storage.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefKey);
      if (savedCode == 'en') {
        _currentLanguage = AppLanguage.eng;
      } else {
        _currentLanguage = AppLanguage.geo;
      }
    } catch (e) {
      debugPrint('[LanguageController] Init notice: $e');
      _currentLanguage = AppLanguage.geo;
    } finally {
      _isInitialized = true;
    }
  }

  /// Sets the application language and persists preference.
  Future<void> setLanguage(AppLanguage language) async {
    if (_currentLanguage == language) return;
    _currentLanguage = language;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, language.languageCode);
    } catch (e) {
      debugPrint('[LanguageController] Save preference notice: $e');
    }
  }

  /// Toggles between Georgian and English.
  Future<void> toggleLanguage() async {
    final next = isGeorgian ? AppLanguage.eng : AppLanguage.geo;
    await setLanguage(next);
  }

  /// Returns the localized string for [key].
  String tr(String key) {
    final map = _translations[key];
    if (map == null) return key;
    return isGeorgian ? (map['ka'] ?? key) : (map['en'] ?? key);
  }

  static const Map<String, Map<String, String>> _translations = {
    // -------------------------------------------------------------
    // General & Actions
    // -------------------------------------------------------------
    'cancel': {'ka': 'გაუქმება', 'en': 'Cancel'},
    'confirm': {'ka': 'დადასტურება', 'en': 'Confirm'},
    'save': {'ka': 'შენახვა', 'en': 'Save'},
    'close': {'ka': 'დახურვა', 'en': 'Close'},
    'ok': {'ka': 'გასაგებია', 'en': 'OK'},
    'back': {'ka': 'უკან', 'en': 'Back'},
    'error': {'ka': 'შეცდომა', 'en': 'Error'},
    'success': {'ka': 'წარმატება', 'en': 'Success'},
    'warning': {'ka': 'გაფრთხილება', 'en': 'Warning'},
    'active': {'ka': 'აქტიური', 'en': 'Active'},
    'inactive': {'ka': 'არააქტიური', 'en': 'Inactive'},
    'ready': {'ka': 'მზადაა', 'en': 'Ready'},
    'loading': {'ka': 'იტვირთება...', 'en': 'Loading...'},
    'refresh': {'ka': 'განახლება', 'en': 'Refresh'},
    'reset': {'ka': 'განულება', 'en': 'Reset'},
    'apply': {'ka': 'ჩაწერა', 'en': 'Apply'},
    'search': {'ka': 'ძიება...', 'en': 'Search...'},
    'all': {'ka': 'ყველა', 'en': 'All'},
    'none': {'ka': 'არცერთი', 'en': 'None'},
    'details': {'ka': 'დეტალები', 'en': 'Details'},
    'status': {'ka': 'სტატუსი', 'en': 'Status'},

    // -------------------------------------------------------------
    // App Branding & Navigation
    // -------------------------------------------------------------
    'app_title': {'ka': 'FIX AI', 'en': 'FIX AI'},
    'app_subtitle': {'ka': 'ქარხნული დიაგნოსტიკა და ტიუნინგი', 'en': 'FACTORY DIAGNOSTICS & TUNING'},
    'language': {'ka': 'ენა', 'en': 'Language'},
    'geo_lang': {'ka': 'ქართული', 'en': 'Georgian'},
    'eng_lang': {'ka': 'English', 'en': 'English'},
    'switch_language': {'ka': 'ენის შეცვლა', 'en': 'Switch Language'},

    // Drawer Modules
    'full_diagnostic_scan': {'ka': 'სრული დიაგნოსტიკური სკანირება', 'en': 'Full Diagnostic Scan'},
    'workshop_modules': {'ka': 'სახელოსნოს მოდულები', 'en': 'WORKSHOP MODULES'},
    'ecu_topology_title': {'ka': 'ECU ტოპოლოგია და DTC-ები', 'en': 'ECU Topology & DTCs'},
    'ecu_topology_sub': {'ka': '32 ბლოკის სკანირება და Freeze Frame', 'en': 'Full 32-module scan & freeze frames'},
    'dealer_routines_title': {'ka': 'დილერული სერვის-რუტინები', 'en': 'Dealer Workshop Routines'},
    'dealer_routines_sub': {'ka': '12 ავტორიზებული სერვისული პროცედურა', 'en': '12 authorized dealer service routines'},
    'live_datalogger_title': {'ka': 'Live ტელემეტრია და სენსორები', 'en': 'Live Datalogger & Gauges'},
    'live_datalogger_sub': {'ka': 'OLED HUD ტელემეტრია და აქტუატორები', 'en': 'OLED HUD telemetry & actuators'},
    'xdrive_title': {'ka': 'xDrive და VTG რაზდატკა', 'en': 'xDrive & VTG Transfer Case'},
    'xdrive_sub': {'ka': '2WD/AWD რეჟიმები და გადაბმულობა', 'en': '2WD/AWD modes & clutch calibration'},
    'flash_tuning_title': {'ka': 'DME და TCU ჩაწერა / ტიუნინგი', 'en': 'DME & TCU Flash Tuning'},
    'flash_tuning_sub': {'ka': 'Custom ROM, OTS რუკები და xHP', 'en': 'Custom ROM, OTS maps & xHP tuning'},
    'coding_title': {'ka': '1-Tap FDL Cheat კოდირება', 'en': '1-Tap FDL Cheat Coding'},
    'coding_sub': {'ka': 'Start-Stop, სარკეები, VO/FA, NCD', 'en': 'Start-Stop, mirrors, VO/FA, NCD backups'},
    'adapter_setup_title': {'ka': 'ადაპტერის კონფიგურაცია', 'en': 'Adapter Hardware Setup'},
    'adapter_setup_sub': {'ka': 'ENET, Wi-Fi, Bluetooth ELM327', 'en': 'ENET, Wi-Fi, Bluetooth ELM327'},
    'my_garage': {'ka': 'ჩემი ავტოფარეხი', 'en': 'MY GARAGE'},
    'add_vehicle': {'ka': 'ავტომობილის დამატება', 'en': 'Add Vehicle'},
    'no_vehicles': {'ka': 'ავტომობილები არ არის რეგისტრირებული.', 'en': 'No vehicles registered in garage.'},
    'settings_prefs': {'ka': 'პარამეტრები', 'en': 'SETTINGS & PREFERENCES'},
    'app_settings': {'ka': 'აპლიკაციის პარამეტრები', 'en': 'Application Settings'},
    'app_settings_sub': {'ka': 'თემა, ერთეულები, ენა, ოფლაინ ბაზა', 'en': 'Theme, units, language, offline database'},

    // -------------------------------------------------------------
    // Connection & Link Hub
    // -------------------------------------------------------------
    'connected': {'ka': 'დაკავშირებულია', 'en': 'Connected'},
    'disconnected': {'ka': 'გათიშულია', 'en': 'Disconnected'},
    'connecting': {'ka': 'დაკავშირება...', 'en': 'Connecting...'},
    'reconnect': {'ka': 'ხელახლა დაკავშირება', 'en': 'Reconnect'},
    'connection_options': {'ka': 'ადაპტერის პარამეტრები', 'en': 'Adapter Link Options'},
    'connection_lost': {'ka': 'კავშირი გაწყდა', 'en': 'Connection Lost'},
    'link_lost_location': {'ka': 'კავშირის გაწყვეტის ადგილი', 'en': 'Where connection broke'},
    'probing_modules': {'ka': 'ბლოკების შემოწმება...', 'en': 'Probing ECU modules...'},
    'start_vehicle_link': {'ka': 'ავტომობილთან დაკავშირება', 'en': 'Connect to Vehicle'},
    'vehicle_connection_hub': {'ka': 'ავტომობილის კავშირის ჰაბი', 'en': 'Vehicle Connection Hub'},
    'auto_detect_target': {'ka': 'ადაპტერის ავტო-დეტექცია', 'en': 'Auto-Detect Adapter IP & Port'},
    'ip_address': {'ka': 'IP მისამართი', 'en': 'IP Address'},
    'port': {'ka': 'პორტი', 'en': 'Port'},
    'chassis_series': {'ka': 'ძარის სერია', 'en': 'Chassis Series'},
    'battery_voltage': {'ka': 'აკუმულატორის ძაბვა', 'en': 'Battery Voltage'},
    'active_vin': {'ka': 'VIN კოდი', 'en': 'VIN'},
    'connection_progress': {'ka': 'დაკავშირების პროცესი', 'en': 'Connection Progress'},
    'connection_error_occurred': {'ka': 'დაფიქსირდა კავშირის შეფერხება', 'en': 'Connection error occurred'},
    'recommendation': {'ka': 'რეკომენდაცია', 'en': 'Recommendation'},

    // Phases
    'phase_idle': {'ka': 'მზადყოფნა', 'en': 'Idle'},
    'phase_adapter': {'ka': 'ადაპტერთან კავშირი (TCP/UDP)', 'en': 'Adapter Link (TCP/UDP)'},
    'phase_gateway': {'ka': 'ავტომობილის კარიბჭე (Gateway/ZGW)', 'en': 'Vehicle Gateway (ZGW/BDC)'},
    'phase_session': {'ka': 'დიაგნოსტიკური სესია (UDS 0x10)', 'en': 'Diagnostic Session (UDS 0x10)'},
    'phase_probing': {'ka': 'ECU ბლოკების შემოწმება (32 მოდული)', 'en': 'ECU Probing (32 Modules)'},
    'phase_ready': {'ka': 'სისტემა დაკავშირებულია და მზადაა', 'en': 'Connected & Operational'},
    'phase_failed': {'ka': 'კავშირი ვერ დამყარდა', 'en': 'Connection Failed'},
    'phase_lost': {'ka': 'კავშირი მოულოდნელად გაწყდა', 'en': 'Connection Dropped'},

    // -------------------------------------------------------------
    // ECU Diagnostics & DTC Explanations
    // -------------------------------------------------------------
    'ecu_diagnostics': {'ka': 'ECU დიაგნოსტიკა', 'en': 'ECU Diagnostics'},
    'scan_all_modules': {'ka': 'ყველა ბლოკის სკანირება', 'en': 'Scan All ECUs'},
    'scanning_progress': {'ka': 'სკანირება მიმდინარეობს...', 'en': 'Scanning ECUs...'},
    'clear_dtcs': {'ka': 'შეცდომების წაშლა', 'en': 'Clear Fault Codes'},
    'clear_dtcs_all': {'ka': 'ყველა ბლოკიდან წაშლა', 'en': 'Clear All Faults'},
    'clearing_dtcs': {'ka': 'შეცდომების წაშლა მიმდინარეობს...', 'en': 'Clearing Fault Codes...'},
    'dtcs_cleared': {'ka': 'შეცდომები წარმატებით წაიშალა', 'en': 'All faults successfully cleared'},
    'no_faults_found': {'ka': 'შეცდომის კოდები არ დაფიქსირებულა', 'en': 'No fault codes detected'},
    'fault_detected': {'ka': 'შეცდომა', 'en': 'Fault'},
    'faults_detected': {'ka': 'შეცდომა დაფიქსირდა', 'en': 'Faults Detected'},
    'modules_healthy': {'ka': 'ბლოკი მუშაობს გამართულად', 'en': 'ECUs Healthy'},
    'modules_faulted': {'ka': 'ბლოკში არის შეცდომა', 'en': 'ECUs with Faults'},
    'standard_faults': {'ka': 'სტანდარტული შეცდომა', 'en': 'Standard DTC'},
    'shadow_faults': {'ka': 'ჩრდილოვანი შეცდომა (Infospeicher)', 'en': 'Shadow DTC (Infospeicher)'},
    'history_faults': {'ka': 'ისტორიის შეცდომა (Historienspeicher)', 'en': 'History DTC'},

    // Fault Card Tabs & Badges
    'tab_overview': {'ka': 'მიმოხილვა', 'en': 'Overview'},
    'tab_guided_repair': {'ka': 'შეკეთების გეგმა', 'en': 'Guided Repair'},
    'tab_symptoms': {'ka': 'სიმპტომები', 'en': 'Symptoms'},
    'tab_factory_texts': {'ka': 'ქარხნული აღწერა', 'en': 'Factory Texts'},
    'tab_glossary': {'ka': 'ტერმინები', 'en': 'Glossary'},
    'tab_freeze_frame': {'ka': 'Freeze Frame', 'en': 'Freeze Frame'},
    'safe_to_drive': {'ka': 'მოძრაობა დასაშვებია', 'en': 'Safe to Drive'},
    'safe_with_caution': {'ka': 'მოძრაობა დასაშვებია ფრთხილად', 'en': 'Drive with Caution'},
    'stop_immediately': {'ka': 'დაუყოვნებლივ გააჩერეთ', 'en': 'Stop Vehicle Immediately'},
    'severity_low': {'ka': 'დაბალი', 'en': 'Low'},
    'severity_medium': {'ka': 'საშუალო', 'en': 'Medium'},
    'severity_high': {'ka': 'მაღალი', 'en': 'High'},
    'severity_critical': {'ka': 'კრიტიკული', 'en': 'Critical'},
    'share_report': {'ka': 'რეპორტის გაზიარება', 'en': 'Share Report'},
    'save_report': {'ka': 'რეპორტის შენახვა', 'en': 'Save Report'},
    'freeze_frame_data': {'ka': 'გარემო პირობების მონაცემები (Freeze Frame)', 'en': 'Environmental Freeze Frame Data'},
    'mileage_at_fault': {'ka': 'გარბენი დაფიქსირებისას', 'en': 'Mileage at Fault'},
    'frequency_counter': {'ka': 'გამეორების მთვლელი', 'en': 'Frequency Counter'},
    'terminal_status': {'ka': 'ანთების სტატუსი (Terminal 15)', 'en': 'Terminal 15 Status'},

    // -------------------------------------------------------------
    // Service Routines & CBS
    // -------------------------------------------------------------
    'workshop_routines': {'ka': 'სახელოსნოს რუტინები', 'en': 'Workshop Routines'},
    'cbs_title': {'ka': 'სერვისული ინტერვალები (CBS)', 'en': 'Condition Based Service (CBS)'},
    'remaining': {'ka': 'დარჩენილია', 'en': 'Remaining'},
    'expiry': {'ka': 'ვადა', 'en': 'Expiry'},
    'cbs_ok': {'ka': 'ნორმა', 'en': 'OK'},
    'cbs_warning': {'ka': 'ყურადღება', 'en': 'Warning'},
    'cbs_overdue': {'ka': 'ვადაგასული', 'en': 'Overdue'},
    'cbs_reset_confirm': {'ka': 'სერვისული ინტერვალის განულება', 'en': 'Reset Service Interval'},
    'cbs_reset_prompt': {'ka': 'ნამდვილად გსურთ არჩეული CBS ერთეულის განულება 100%-მდე?', 'en': 'Are you sure you want to reset this CBS item to 100%?'},
    'battery_reg_title': {'ka': 'აკუმულატორის რეგისტრაცია', 'en': 'Battery Registration'},
    'brake_bleed_title': {'ka': 'ABS/DSC მუხრუჭების გამორეცხვა', 'en': 'ABS/DSC Hydraulic Brake Bleeding'},
    'parking_brake_title': {'ka': 'ელექტრო ხელის მუხრუჭი (სერვის რეჟიმი)', 'en': 'Parking Brake (EMF Service Mode)'},
    'trans_adapt_title': {'ka': 'ZF გადაცემათა კოლოფის ადაპტაციები', 'en': 'ZF Transmission Adaptations & Reset'},
    'throttle_idle_title': {'ka': 'დროსელის და Valvetronic-ის ადაპტაცია', 'en': 'Throttle & Valvetronic Re-learn'},
    'dpf_regen_title': {'ka': 'DPF რეგენერაცია და ნაცრის განულება', 'en': 'DPF Regeneration & Ash Reset'},
    'szl_calib_title': {'ka': 'საჭის კუთხის სენსორის (SZL) კალიბრაცია', 'en': 'Steering Angle Sensor Calibration'},
    'frm_reset_title': {'ka': 'FRM მოკლე ჩართვის მრიცხველის განულება', 'en': 'FRM Short-Circuit Counter Reset'},
    'fuel_prime_title': {'ka': 'საწვავის დაბალი წნევის ტუმბოს დატუმბვა', 'en': 'Low Pressure Fuel Pump Priming'},
    'transport_mode_title': {'ka': 'ტრანსპორტირების რეჟიმის დეაქტივაცია', 'en': 'Transport Mode Deactivation'},
    'vtg_fluid_title': {'ka': 'VTG რაზდატკის ზეთის განულება', 'en': 'VTG Transfer Case Fluid Reset'},

    // -------------------------------------------------------------
    // 1-Tap Coding & FDL Cheat Codes
    // -------------------------------------------------------------
    'bmw_coding': {'ka': 'BMW კოდირება', 'en': 'BMW Coding'},
    'cheat_codes_tab': {'ka': '1-Tap Cheat კოდები', 'en': '1-Tap Cheat Codes'},
    'vehicle_order_tab': {'ka': 'სატრანსპორტო შეკვეთა (VO / FA)', 'en': 'Vehicle Order (VO / FA)'},
    'shadow_memory_tab': {'ka': 'ჩრდილოვანი მეხსიერება', 'en': 'Shadow Fault Memory'},
    'backups_tab': {'ka': 'NCD ასლები', 'en': 'NCD Backups'},
    'apply_coding': {'ka': 'კოდირების ჩაწერა', 'en': 'Apply Coding'},
    'create_backup': {'ka': 'ასლის შექმნა', 'en': 'Create Backup'},
    'restore_backup': {'ka': 'ასლის აღდგენა', 'en': 'Restore Backup'},
    'coding_safety_notice': {'ka': 'კოდირებისას აუცილებელია: ანთება ჩართული, ძრავი გამორთული, ძაბვა > 12.5V.', 'en': 'During coding: Ignition ON, Engine OFF, Voltage > 12.5V.'},

    // -------------------------------------------------------------
    // Live Telemetry & Actuators
    // -------------------------------------------------------------
    'live_datalogger': {'ka': 'BMW Live ტელემეტრია', 'en': 'BMW Live Datalogger'},
    'channels': {'ka': 'არხი', 'en': 'Channels'},
    'actuators': {'ka': 'აქტუატორები', 'en': 'Actuators'},
    'record_log': {'ka': 'სესიის ჩაწერა', 'en': 'Record Session Log'},
    'stop_log': {'ka': 'ჩაწერის შეჩერება', 'en': 'Stop Recording'},
    'rpm': {'ka': 'ძრავის ბრუნი', 'en': 'Engine RPM'},
    'boost': {'ka': 'ტურბოს წნევა', 'en': 'Boost Pressure'},
    'coolant_temp': {'ka': 'გაგრილების ტემპერატურა', 'en': 'Coolant Temperature'},
    'oil_temp': {'ka': 'ზეთის ტემპერატურა', 'en': 'Oil Temperature'},
    'lambda': {'ka': 'ლამბდა', 'en': 'Lambda'},
    'knock_detected': {'ka': 'დეტონაცია დაფიქსირდა', 'en': 'Knock Detected'},

    // -------------------------------------------------------------
    // Flash Tuning & OTS
    // -------------------------------------------------------------
    'dme_tuning': {'ka': 'BMW DME ჩაწერა', 'en': 'BMW DME Tuning'},
    'custom_rom': {'ka': 'Custom ROM', 'en': 'Custom ROM'},
    'ots_maps': {'ka': 'OTS რუკები', 'en': 'OTS Maps'},
    'multimap_slot': {'ka': 'Multimap სლოტი', 'en': 'Multimap Slot'},
    'exhaust_burble': {'ka': 'მაყუჩის Burble ხმები', 'en': 'Exhaust Burble'},
    'top_speed_limiter': {'ka': 'მაქსიმალური სიჩქარის ლიმიტი', 'en': 'Top Speed Limiter'},
    'cold_start_noise': {'ka': 'ცივი დაქოქვის ხმაურის შემცირება', 'en': 'Cold Start Noise Reduction'},
    'flash_ecu': {'ka': 'ECU-ს ჩაწერა', 'en': 'Flash ECU'},
    'slide_to_confirm': {'ka': 'გასწიეთ დასადასტურებლად', 'en': 'Slide to Confirm'},

    // -------------------------------------------------------------
    // xDrive & VTG
    // -------------------------------------------------------------
    'xdrive_control': {'ka': 'xDrive და VTG მართვა', 'en': 'xDrive & VTG Control'},
    'awd_mode': {'ka': 'სრული ამძრავი (AWD 100% ქარხნული)', 'en': 'Full All-Wheel Drive (AWD Factory)'},
    'rwd_sport_mode': {'ka': 'უკანა ამძრავი (RWD Sport 0% წინა ხიდი)', 'en': 'Rear-Wheel Drive (RWD Sport 0% Front)'},
    'custom_clutch_mode': {'ka': 'მორგებული გადაბმულობის პროცენტი', 'en': 'Custom Clutch Lock Percentage'},
    'calibrate_vtg': {'ka': 'VTG გადაბმულობის კალიბრაცია', 'en': 'Calibrate VTG Clutch (0xA101)'},

    // -------------------------------------------------------------
    // Settings & Dialogs
    // -------------------------------------------------------------
    'appearance_theme': {'ka': 'დიზაინის თემა', 'en': 'Appearance Theme'},
    'theme_auto': {'ka': 'ავტო', 'en': 'Auto'},
    'theme_light': {'ka': 'ღია', 'en': 'Light'},
    'theme_dark': {'ka': 'მუქი', 'en': 'Dark'},
    'measurement_units': {'ka': 'ერთეულები', 'en': 'Measurement Units'},
    'metric_units': {'ka': 'მეტრული (კმ, °C, Bar)', 'en': 'Metric (km, °C, Bar)'},
    'imperial_units': {'ka': 'იმპერიული (მილი, °F, PSI)', 'en': 'Imperial (mi, °F, PSI)'},
    'clear_history': {'ka': 'დიაგნოსტიკის ისტორიის წაშლა', 'en': 'Clear Diagnostic History'},
    'select_language': {'ka': 'ენის არჩევა', 'en': 'Select Language'},
  };
}

/// Extension on [BuildContext] for ergonomic localization access.
extension LocalizationExtension on BuildContext {
  LanguageController get languageController => LanguageController.instance;
  AppLanguage get currentLanguage => LanguageController.instance.currentLanguage;
  bool get isGeorgian => LanguageController.instance.isGeorgian;
  bool get isEnglish => LanguageController.instance.isEnglish;
  String tr(String key) => LanguageController.instance.tr(key);
}
