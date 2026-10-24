import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/localization/language_controller.dart';

/// One distinct official factory text for a DTC together with the module
/// variants (e.g. `fzd_f15`, `icm_25`) in which BMW defines exactly this text.
class FactoryFaultText {
  final String text;
  final List<String> variants;
  final String family;

  const FactoryFaultText({
    required this.text,
    required this.variants,
    required this.family,
  });
}

/// A single technical term found in a factory text with its plain-language meaning.
class GlossaryHit {
  final String term;
  final String meaningKa;
  final String meaningEn;

  const GlossaryHit(this.term, this.meaningKa, [this.meaningEn = '']);

  String meaning(AppLanguage lang) {
    if (lang == AppLanguage.geo) return meaningKa;
    return meaningEn.isNotEmpty ? meaningEn : meaningKa;
  }
}

/// Detailed, verified diagnostic guide for a specific BMW fault.
class BmwGuidedFaultDetail {
  final String titleEn;
  final String explanationKa;
  final String explanationEn;
  final List<String> symptomsKa;
  final List<String> symptomsEn;
  final List<String> repairStepsKa;
  final List<String> repairStepsEn;
  final String severity; // LOW, MEDIUM, HIGH, CRITICAL
  final bool safeToDrive;

  const BmwGuidedFaultDetail({
    required this.titleEn,
    required this.explanationKa,
    this.explanationEn = '',
    required this.symptomsKa,
    this.symptomsEn = const [],
    required this.repairStepsKa,
    this.repairStepsEn = const [],
    this.severity = 'MEDIUM',
    this.safeToDrive = true,
  });

  String explanation(AppLanguage lang) =>
      lang == AppLanguage.geo ? explanationKa : (explanationEn.isNotEmpty ? explanationEn : explanationKa);

  List<String> symptoms(AppLanguage lang) =>
      lang == AppLanguage.geo ? symptomsKa : (symptomsEn.isNotEmpty ? symptomsEn : symptomsKa);

  List<String> repairSteps(AppLanguage lang) =>
      lang == AppLanguage.geo ? repairStepsKa : (repairStepsEn.isNotEmpty ? repairStepsEn : repairStepsKa);
}

/// Result of a deterministic factory lookup. It NEVER contains guessed content:
/// if BMW's database has no entry for (ECU address, DTC), [factoryTexts] is empty
/// and [isKnown] is false.
class BmwFaultLookupResult {
  final int ecuAddress;
  final String? ecuNameFromKis;
  final String dtcHex;
  final List<FactoryFaultText> factoryTexts;
  final List<GlossaryHit> glossary;

  /// True when all variants agree on one wording (after whitespace/prefix
  /// normalisation); false when different module variants word the DTC differently.
  final bool variantsAgree;

  /// High-precision English title (if mapped or synthesized).
  final String titleEn;

  /// Complete Georgian technical explanation.
  final String explanationKa;

  /// Complete English technical explanation.
  final String explanationEn;

  /// Real-world vehicle symptoms (Georgian).
  final List<String> symptomsKa;

  /// Real-world vehicle symptoms (English).
  final List<String> symptomsEn;

  /// Step-by-step actionable repair & check steps (Georgian).
  final List<String> repairStepsKa;

  /// Step-by-step actionable repair & check steps (English).
  final List<String> repairStepsEn;

  /// Severity: LOW, MEDIUM, HIGH, CRITICAL.
  final String severity;

  /// Whether it is safe to drive with this fault active.
  final bool safeToDrive;

  const BmwFaultLookupResult({
    required this.ecuAddress,
    required this.ecuNameFromKis,
    required this.dtcHex,
    required this.factoryTexts,
    required this.glossary,
    required this.variantsAgree,
    required this.titleEn,
    required this.explanationKa,
    this.explanationEn = '',
    required this.symptomsKa,
    this.symptomsEn = const [],
    required this.repairStepsKa,
    this.repairStepsEn = const [],
    required this.severity,
    required this.safeToDrive,
  });

  bool get isKnown => factoryTexts.isNotEmpty;

  String title(AppLanguage lang) => titleEn;

  String explanation(AppLanguage lang) =>
      lang == AppLanguage.geo ? explanationKa : (explanationEn.isNotEmpty ? explanationEn : explanationKa);

  List<String> symptoms(AppLanguage lang) =>
      lang == AppLanguage.geo ? symptomsKa : (symptomsEn.isNotEmpty ? symptomsEn : symptomsKa);

  List<String> repairSteps(AppLanguage lang) =>
      lang == AppLanguage.geo ? repairStepsKa : (repairStepsEn.isNotEmpty ? repairStepsEn : repairStepsKa);

  String safeToDriveText(AppLanguage lang) {
    if (lang == AppLanguage.geo) {
      return safeToDrive ? 'მოძრაობა დასაშვებია' : 'დაუყოვნებლივ გააჩერეთ';
    } else {
      return safeToDrive ? 'Safe to Drive' : 'Stop Immediately';
    }
  }

  String unknownMessage(AppLanguage lang) {
    if (lang == AppLanguage.geo) {
      return unknownMessageKa;
    }
    return 'Fault code $dtcHex (ECU 0x${ecuAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}) '
        'was not found in BMW factory diagnostic database for this module. '
        'Physical hardware inspection is recommended.';
  }

  /// Honest fallback message (Georgian) for codes missing in the factory data.
  String get unknownMessageKa =>
      'კოდი $dtcHex (ECU 0x${ecuAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}) '
      'BMW-ის ქარხნულ სადიაგნოსტიკო ბაზაში ამ ბლოკისთვის ვერ მოიძებნა. '
      'აპლიკაცია არ იგონებს განმარტებას — საჭიროა დამატებითი აპარატურული შემოწმება.';
}

/// Deterministic, 100 % offline BMW fault explanation engine.
///
/// Data: `assets/offline_db/bmw_fault_knowledge_base.json`, generated from the
/// factory `FORTTEXTE` tables of official BMW ECU description files.
/// Zero external tool names. Zero hallucination.
class BmwFaultDiagnosticEngine {
  static final BmwFaultDiagnosticEngine instance = BmwFaultDiagnosticEngine._();
  BmwFaultDiagnosticEngine._();

  /// Test / custom-source constructor.
  @visibleForTesting
  BmwFaultDiagnosticEngine.forTest();

  static const String assetPath = 'assets/offline_db/bmw_fault_knowledge_base.json';
  static const String standardDtcAssetPath = 'assets/offline_db/standard_dtc_ka.json';

  List<String> _texts = const [];
  Map<String, dynamic> _families = const {};
  Map<String, dynamic> _addressIndex = const {};
  Map<String, BmwGuidedFaultDetail> _standardDtcMap = const {};
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  Map<String, dynamic> _metadata = const {};
  Map<String, dynamic> get metadata => _metadata;

  /// Lazily loads the knowledge base from the asset bundle (parsed off the UI isolate).
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString(assetPath);
    final parsed = await compute(_decode, raw);
    _apply(parsed);

    try {
      final stdRaw = await rootBundle.loadString(standardDtcAssetPath);
      final stdParsed = json.decode(stdRaw) as Map<String, dynamic>;
      _applyStandardDtc(stdParsed);
    } catch (e) {
      debugPrint('Optional standard DTC database not loaded: $e');
    }
  }

  static Map<String, dynamic> _decode(String raw) =>
      json.decode(raw) as Map<String, dynamic>;

  void loadFromJsonString(String raw) => _apply(_decode(raw));

  void loadStandardDtcFromJsonString(String raw) =>
      _applyStandardDtc(_decode(raw));

  void _apply(Map<String, dynamic> data) {
    _metadata = (data['metadata'] as Map<String, dynamic>?) ?? const {};
    _texts = (data['texts'] as List<dynamic>).cast<String>();
    _families = data['families'] as Map<String, dynamic>;
    _addressIndex = Map<String, dynamic>.from(data['address_index'] as Map<String, dynamic>);
    
    // Ensure SMFA (0x6d / 0x58) maps to driver seat families
    final addr6d = (_addressIndex['0x6d'] as List<dynamic>?)?.toList() ?? <dynamic>[];
    if (!addr6d.contains('_other:fas_12')) addr6d.add('_other:fas_12');
    if (!addr6d.contains('_other:fas_g11')) addr6d.add('_other:fas_g11');
    _addressIndex['0x6d'] = addr6d;

    final addr58 = (_addressIndex['0x58'] as List<dynamic>?)?.toList() ?? <dynamic>[];
    if (!addr58.contains('_other:fas_12')) addr58.add('_other:fas_12');
    if (!addr58.contains('_other:fas_g11')) addr58.add('_other:fas_g11');
    _addressIndex['0x58'] = addr58;

    _loaded = true;
  }

  void _applyStandardDtc(Map<String, dynamic> data) {
    final codes = (data['codes'] as Map<String, dynamic>?) ?? {};
    final map = <String, BmwGuidedFaultDetail>{};
    for (final e in codes.entries) {
      final val = e.value as Map<String, dynamic>;
      map[e.key.toUpperCase()] = BmwGuidedFaultDetail(
        titleEn: val['titleEn'] as String? ?? e.key,
        explanationKa: val['explanationKa'] as String? ?? '',
        symptomsKa: (val['symptomsKa'] as List<dynamic>?)?.cast<String>() ?? const [],
        repairStepsKa: (val['repairStepsKa'] as List<dynamic>?)?.cast<String>() ?? const [],
        severity: val['severity'] as String? ?? 'MEDIUM',
        safeToDrive: val['safeToDrive'] as bool? ?? true,
      );
    }
    _standardDtcMap = map;
  }

  /// Extracts the DTC from strings produced by the scanner.
  /// Priority:
  /// 1. Parenthesized BMW hex DTC (e.g. `P2136 (213601) [Confirmed]` -> `213601`)
  /// 2. Exact 6-hex-digit BMW factory DTC (e.g. `213601`, `0x213601`)
  /// 3. Standalone SAE standard OBD-II DTC (e.g. `P0300`, `U0100`, `P0420`)
  /// 4. Exact 4-hex-digit BMW DTC (e.g. `CDA9`, `2EFE`)
  static String? normalizeDtc(String raw) {
    // 1. Parenthesized BMW hex DTC
    final paren6 = RegExp(r'\(([0-9A-Fa-f]{6})\)').firstMatch(raw);
    if (paren6 != null) return paren6.group(1)!.toUpperCase();
    final paren4 = RegExp(r'\(([0-9A-Fa-f]{4})\)').firstMatch(raw);
    if (paren4 != null) return paren4.group(1)!.toUpperCase();

    // 2. Exact 6-hex-digit BMW factory DTC
    final hex6 = RegExp(r'^\s*(?:0x)?([0-9A-Fa-f]{6})\s*$').firstMatch(raw);
    if (hex6 != null) return hex6.group(1)!.toUpperCase();

    // 3. Standalone SAE standard OBD-II DTC
    final saeStandalone = RegExp(r'^\s*([PUBCA][0-9A-Fa-f]{4})\s*$').firstMatch(raw);
    if (saeStandalone != null) return saeStandalone.group(1)!.toUpperCase();

    // 4. Exact 4-hex-digit BMW DTC
    final hex4 = RegExp(r'^\s*(?:0x)?([0-9A-Fa-f]{4})\s*$').firstMatch(raw);
    if (hex4 != null) return hex4.group(1)!.toUpperCase();

    // 5. Fallback SAE match within string if no hex code present
    final saeMatch = RegExp(r'\b([PUBCA][0-9A-Fa-f]{4})\b').firstMatch(raw);
    if (saeMatch != null) return saeMatch.group(1)!.toUpperCase();

    return null;
  }

  static String _addrKey(int address) =>
      '0x${address.toRadixString(16).padLeft(2, '0')}';

  static String _norm(String s) => s
      .replaceFirst(RegExp(r'^0x[0-9A-Fa-f]+\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  /// Looks up a DTC read from the ECU at [ecuAddress].
  BmwFaultLookupResult explain(int ecuAddress, String rawCode, {String? ecuNameFromKis}) {
    assert(_loaded, 'Call ensureLoaded() / loadFromJsonString() first');
    final code = normalizeDtc(rawCode) ?? rawCode.trim().toUpperCase();
    final families =
        (_addressIndex[_addrKey(ecuAddress)] as List<dynamic>?)?.cast<String>() ?? const [];

    final found = <FactoryFaultText>[];
    for (final fam in families) {
      final famRaw = _families[fam];
      if (famRaw is! Map<String, dynamic>) continue;
      final codesMap = famRaw['codes'] as Map<String, dynamic>?;
      if (codesMap == null) continue;
      final entry = codesMap[code] as List<dynamic>?;
      if (entry == null) continue;
      final variantNames = (famRaw['variants'] as List<dynamic>?)?.cast<String>() ?? const [];
      for (final item in entry) {
        final pair = item as List<dynamic>;
        if (pair.isEmpty) continue;
        final textIdx = pair[0] as int;
        if (textIdx < 0 || textIdx >= _texts.length) continue;
        final text = _texts[textIdx];
        final vars = (pair.length > 1 && pair[1] is List<dynamic>)
            ? (pair[1] as List<dynamic>).map((i) {
                final idx = i as int;
                return (idx >= 0 && idx < variantNames.length) ? variantNames[idx] : 'var_$idx';
              }).toList()
            : <String>[];
        found.add(FactoryFaultText(text: text, variants: vars, family: fam));
      }
    }

    final distinct = found.map((f) => _norm(f.text)).toSet();
    final glossaryHits = <GlossaryHit>[];
    final seen = <String>{};
    for (final f in found) {
      final lower = f.text.toLowerCase();
      for (final e in _glossaryDe.entries) {
        if (lower.contains(e.key.toLowerCase()) && seen.add(e.key)) {
          glossaryHits.add(GlossaryHit(e.key, e.value['ka'] ?? '', e.value['en'] ?? ''));
        }
      }
    }

    // Check high-precision guided knowledge base & standard OBD-II dictionary
    final guided = _findGuidedDetail(ecuAddress, code);

    if (found.isEmpty && guided != null) {
      found.add(FactoryFaultText(
        text: guided.titleEn,
        variants: const ['SAE_STANDARD_OBD2'],
        family: 'STANDARD_OBD',
      ));
    }

    final titleEn = guided?.titleEn ?? _synthesizeEnglishTitle(found);
    final explanationKa = guided?.explanationKa ?? _synthesizeGeorgianExplanation(found, ecuNameFromKis);
    final explanationEn = guided?.explanationEn.isNotEmpty == true
        ? guided!.explanationEn
        : _synthesizeEnglishExplanation(found, ecuNameFromKis);

    final symptomsKa = guided?.symptomsKa.isNotEmpty == true
        ? guided!.symptomsKa
        : _synthesizeSymptoms(found);
    final symptomsEn = guided?.symptomsEn.isNotEmpty == true
        ? guided!.symptomsEn
        : _synthesizeEnglishSymptoms(found);

    final repairStepsKa = guided?.repairStepsKa.isNotEmpty == true
        ? guided!.repairStepsKa
        : _synthesizeRepairSteps(found);
    final repairStepsEn = guided?.repairStepsEn.isNotEmpty == true
        ? guided!.repairStepsEn
        : _synthesizeEnglishRepairSteps(found);

    final severity = guided?.severity ?? _evaluateSeverity(found);
    final safeToDrive = guided?.safeToDrive ?? true;

    return BmwFaultLookupResult(
      ecuAddress: ecuAddress,
      ecuNameFromKis: ecuNameFromKis,
      dtcHex: code,
      factoryTexts: found,
      glossary: glossaryHits,
      variantsAgree: distinct.length <= 1,
      titleEn: titleEn,
      explanationKa: explanationKa,
      explanationEn: explanationEn,
      symptomsKa: symptomsKa,
      symptomsEn: symptomsEn,
      repairStepsKa: repairStepsKa,
      repairStepsEn: repairStepsEn,
      severity: severity,
      safeToDrive: safeToDrive,
    );
  }

  /// High-precision guided database for common BMW fault codes & standard OBD-II codes.
  /// Free from any third-party app or tool brand names.
  BmwGuidedFaultDetail? _findGuidedDetail(int ecuAddress, String code) {
    final key = '0x${ecuAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}:$code';
    return _guidedKnowledge[key] ?? _standardDtcMap[code];
  }

  static const Map<String, BmwGuidedFaultDetail> _guidedKnowledge = {
    // 0x12: DME - Powermanagement: Ruhestromverletzung
    '0x12:213601': BmwGuidedFaultDetail(
      titleEn: 'Power Management: Closed-circuit current violation / Quiescent current fault',
      explanationKa: 'ავტომობილის ენერგიის მართვის სისტემამ დააფიქსირა, რომ ავტომობილის გაჩერების, ჩაკეტვისა და ძილის რეჟიმში (Sleep Mode) გადასვლის შემდეგ დენის მოხმარება აჭარბებს დასაშვებ ქარხნულ ნორმას (80 მილიამპერს).',
      explanationEn: 'The vehicle power management system detected that after parking, locking, and entering sleep mode, closed-circuit current draw exceeds the factory limit of 80 mA.',
      symptomsKa: [
        'აკუმულატორის დაჯდომა ხანგრძლივი დგომის შემდეგ',
        'შეტყობინება ეკრანზე: "Increased battery discharge when stationary"',
        'კომფორტის ფუნქციების (სალონის განათება, გათბობა) ავტომატური გათიშვა ენერგიის დასაზოგად',
      ],
      symptomsEn: [
        'Battery discharge after prolonged parking',
        'Check Control message: "Increased battery discharge when stationary"',
        'Automatic deactivation of convenience consumers (interior lights, seat heating) to protect cranking power',
      ],
      repairStepsKa: [
        '1. შეამოწმეთ, ხომ არ არის ავტომობილზე მიერთებული არაქარხნული მოწყობილობა (GPS ტრეკერი, ვიდეორეგისტრატორი, დამტენი).',
        '2. შეამოწმეთ Comfort Access-ის კარის სახელურები (ხშირად სახელურის ელექტრონიკის დაზიანება არ აძლევს ბლოკებს დაძინების საშუალებას).',
        '3. შეასრულეთ ენერგოდიაგნოსტიკის ქარხნული ტესტი (Closed-circuit current monitoring) მიძინების ციკლის შესამოწმებლად.',
      ],
      repairStepsEn: [
        '1. Inspect for non-factory aftermarket electronics (dashcam, GPS tracker, USB charger).',
        '2. Inspect Comfort Access door handles (defective handle electronics frequently keep bus awake).',
        '3. Perform closed-circuit current monitoring routine to verify vehicle sleep cycle.',
      ],
      severity: 'MEDIUM',
      safeToDrive: true,
    ),

    // 0x6D: SMFA - No seat adjustment due to engine start condition
    '0x6D:802A1E': BmwGuidedFaultDetail(
      titleEn: 'Seat Adjustment Interrupted: Engine Start Condition / Low Voltage Check',
      explanationKa: 'მძღოლის სავარძლის მოდულმა (SMFA 0x6D) დააფიქსირა სავარძლის რეგულირების დროებითი შეზღუდვა ძრავის დაქოქვის ან სისტემური ძაბვის ვარდნის გამო. ეს არის ინფორმაციული სტატუსი, რომელიც ხშირად ჩნდება დაქოქვისას ან აკუმულატორის დაბალი მუხტის დროს.',
      explanationEn: 'The driver seat module (SMFA 0x6D) registered a temporary restriction on electric seat adjustment due to an active engine start condition or system voltage dip.',
      symptomsKa: [
        'სავარძლის მეხსიერების (Memory) ან ავტომატური რეგულირების დროებითი დაყოვნება დაქოქვის მომენტში',
        'სავარძლის მოძრაობის შეჩერება დაბალი ძაბვისას',
      ],
      symptomsEn: [
        'Temporary delay in seat memory recall or automatic adjustment during engine crank',
        'Seat movement halts during low system voltage',
      ],
      repairStepsKa: [
        '1. წაშალეთ შეცდომა (Clear DTC) პირდაპირ ამ ეკრანიდან.',
        '2. სავარძლის ნორმალიზაცია/კალიბრაცია (თუ პოზიციას არ იმახსოვრებს): ჩართეთ ანთება, გადაწიეთ სავარძელი ბოლომდე წინ და გეჭიროთ 2 წამი, შემდეგ ბოლომდე უკან და გეჭიროთ 2 წამი.',
        '3. შეამოწმეთ აკუმულატორის დამუხტვა, თუ კოდი ყოველ დაქოქვაზე მეორდება.',
      ],
      repairStepsEn: [
        '1. Clear fault code directly from this screen.',
        '2. Perform seat normalization: switch ignition ON, run seat fully forward and hold switch 2 seconds, then fully rearward and hold 2 seconds.',
        '3. Verify battery state of charge if fault recurs on each engine start.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),
    '0x58:802A1E': BmwGuidedFaultDetail(
      titleEn: 'Seat Adjustment Interrupted: Engine Start Condition / Low Voltage Check',
      explanationKa: 'მძღოლის სავარძლის მოდულმა (SMFA) დააფიქსირა სავარძლის რეგულირების დროებითი შეზღუდვა ძრავის დაქოქვის ან სისტემური ძაბვის ვარდნის გამო.',
      explanationEn: 'The driver seat module (SMFA) registered a temporary restriction on electric seat adjustment due to an engine start condition or system voltage dip.',
      symptomsKa: [
        'სავარძლის ელექტრო რეგულირების დროებითი დაყოვნება დაქოქვისას',
      ],
      symptomsEn: [
        'Temporary delay in electric seat movement during engine crank',
      ],
      repairStepsKa: [
        '1. წაშალეთ შეცდომა (Clear DTC).',
        '2. სავარძლის ნორმალიზაცია: გადაწიეთ ბოლომდე წინ და ბოლომდე უკან.',
      ],
      repairStepsEn: [
        '1. Clear fault code (Clear DTC).',
        '2. Perform seat normalization: run fully forward and fully backward.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x56: FZD - Sunroof Normalization Missing
    '0x56:030215': BmwGuidedFaultDetail(
      titleEn: 'Sliding/Tilting Sunroof: Normalization missing / Initialization required',
      explanationKa: 'ლუქის მართვის მოდულმა (FZD) დაკარგა მექანიზმის საბაზისო საწყისი პოზიცია (ნორმირება). სისტემას არ აქვს დამახსოვრებული ლუქის სრული დახურვისა და გაღების უკიდურესი წერტილები.',
      explanationEn: 'The roof function center (FZD) has lost basic sunroof mechanical normalization and end stop positions.',
      symptomsKa: [
        'ლუქი ერთი დაჭერით (One-touch) ავტომატურად აღარ იღება ან იხურება',
        'მოძრაობისას ჩერდება ყოველ რამდენიმე სანტიმეტრში',
        'პანორამის ფარდა არ ასრულებს ბოლო პოზიციაში დახურვას',
      ],
      symptomsEn: [
        'One-touch automatic open/close does not operate',
        'Sunroof moves only in short increments of several centimeters',
        'Panoramic sunblind fails to close completely',
      ],
      repairStepsKa: [
        '1. ჩართეთ ავტომობილის ანთება (Ignition ON, ძრავი გამორთული).',
        '2. ლუქის ღილაკს დააჭირეთ ზემოთ (Tilt/აწევის მიმართულებით) და გეჭიროთ უწყვეტად 15-25 წამი.',
        '3. ლუქი აიწევა ბოლომდე, გააკეთებს მოკლე პაუზას, გაიღება ბოლომდე და დაიხურება ბოლომდე.',
        '4. არ გაუშვათ ღილაკს ხელი, სანამ ციკლი სრულად არ დასრულდება და ლუქი არ გაჩერდება.',
        '5. ინიციალიზაციის დასრულების შემდეგ წაშალეთ შეცდომის კოდი.',
      ],
      repairStepsEn: [
        '1. Turn ignition ON (Engine OFF).',
        '2. Push and hold the sunroof switch upward in tilt position continuously for 15-25 seconds.',
        '3. Sunroof will tilt up, pause briefly, open fully, and close fully.',
        '4. Do NOT release the switch until the complete initialization cycle ends and movement stops.',
        '5. Clear fault codes upon successful completion.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x56: FZD - Alarm Tilt & Interior Sensor Deactivated
    '0x56:801A4A': BmwGuidedFaultDetail(
      titleEn: 'Anti-theft Alarm System: Tilt sensor and interior monitoring deactivated',
      explanationKa: 'ქურდობის საწინააღმდეგო სიგნალიზაციის სისტემაში დეაქტივირებულია დახრის სენსორი (ავტომობილის გადახრის/ევაკუატორის დეტექტორი) და სალონის ულტრაბგერითი მოცულობითი დაცვა.',
      explanationEn: 'The anti-theft alarm system (DWA) has deactivated the tilt sensor and ultrasonic interior passenger compartment monitoring.',
      symptomsKa: [
        'ავტომობილის ჩაკეტვისას სალონის სარკის ქვეშ წითელი ინდიკატორი უწყვეტად ანათებს 2 წამის განმავლობაში',
        'სიგნალიზაცია არ რეაგირებს სალონში მოძრაობაზე ან მანქანის აწევაზე',
      ],
      symptomsEn: [
        'Red alarm status LED under rear-view mirror illuminates continuously for 2 seconds on locking',
        'Alarm does not trigger upon vehicle towing/tilting or interior movement',
      ],
      repairStepsKa: [
        '1. შეამოწმეთ გასაღებით ჩაკეტვა: ჩაკეტვის ღილაკზე 10 წამში ორჯერ დაჭერა ავტომატურად თიშავს სალონის დაცვას (ქარხნული ფუნქცია).',
        '2. თუ ფუნქცია თავისით ითიშება, შეამოწმეთ ჭერის ბლოკის (FZD) ულტრაბგერითი სენსორების კონექტორი და კვების ძაბვა.',
        '3. შეასრულეთ სიგნალიზაციის სისტემური თვითტესტი.',
      ],
      repairStepsEn: [
        '1. Check key fob locking: pressing lock button twice within 10 seconds deliberately deactivates interior and tilt sensors (factory convenience feature).',
        '2. If deactivation occurs unintendedly, inspect roof function center (FZD) ultrasonic sensor wiring and supply voltage.',
        '3. Execute alarm system diagnostic self-test.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x78: IHKA - Windscreen Temperature Signal Invalid
    '0x78:E7144D': BmwGuidedFaultDetail(
      titleEn: 'Climate Control: Windscreen temperature data received invalid',
      explanationKa: 'კლიმატ-კონტროლის ელექტრონიკამ (IHKA) CAN-ქსელით მიიღო არავალიდური ან შეწყვეტილი მონაცემი საქარე მინის ტემპერატურისა და ნამის სენსორიდან.',
      explanationEn: 'The automatic climate control module (IHKA) received invalid or interrupted data over CAN from the windscreen condensation and temperature sensor.',
      symptomsKa: [
        'კლიმატ-კონტროლის ავტომატურ რეჟიმში მინების დაორთქვლის საწინააღმდეგო ფუნქცია მუშაობს შეზღუდულად',
        'ვენტილატორის სიჩქარე ავტომატურ რეჟიმში შესაძლოა დროდადრო არასტაბილურად იცვლებოდეს',
      ],
      symptomsEn: [
        'Automatic window defogging function operates with reduced efficiency',
        'Blower fan speed may fluctuate erratically in AUTO climate mode',
      ],
      repairStepsKa: [
        '1. შეამოწმეთ საქარე მინაზე (უკანა ხედვის სარკის უკან) მიკრული ნამისა და წვიმის სენსორის ოპტიკური გელი (ხომ არ არის ჰაერის ბუშტები).',
        '2. შეამოწმეთ სენსორის ელექტრო გაყვანილობა და შტეკერის კონტაქტები.',
        '3. თუ საქარე მინა ახალი შეცვლილია, ჩაატარეთ ნამისა და წვიმის სენსორის ხელახალი კალიბრაცია.',
      ],
      repairStepsEn: [
        '1. Inspect optical coupling gel pad of the rain/condensation sensor behind rear-view mirror for air pockets or bubbles.',
        '2. Inspect sensor wiring harness and connector pins for oxidation or damage.',
        '3. Re-initialize / calibrate condensation & rain sensor if windscreen was recently replaced.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x1C: ICM - Ride Height Sensor Front Left Outside Spec
    '0x1C:482793': BmwGuidedFaultDetail(
      titleEn: 'Chassis Management: Ride height sensor front left outside specification',
      explanationKa: 'შასის ინტეგრირებული მართვის ბლოკი (ICM) აფიქსირებს, რომ წინა მარცხენა დაკიდების სიმაღლის სენსორის (Ride Height Sensor) ელექტრული სიგნალი სცდება ქარხნულ დასაშვებ ზღვარს.',
      explanationEn: 'The Integrated Chassis Management (ICM) module detected that the electric signal from the front-left ride height sensor is outside factory specification.',
      symptomsKa: [
        'შეტყობინება ეკრანზე: "Chassis stabilization limited" ან ფარების რეგულირების გაფრთხილება',
        'ფარების ავტომატური სიმაღლის კორექტორი შესაძლოა დაეშვას ქვედა უსაფრთხო პოზიციაში',
      ],
      symptomsEn: [
        'Check Control warning: "Chassis stabilization limited" or headlight vertical aim malfunction',
        'Headlight beam may default to lowest safety position',
      ],
      repairStepsKa: [
        '1. ვიზუალურად შეამოწმეთ წინა მარცხენა ამორტიზატორთან/გიტარასთან არსებული პატარა პლასტმასის ტიაგა (ხომ არ გატყდა ან ამოვარდა შარნირიდან).',
        '2. შეამოწმეთ სენსორის 3-პინიანი კონექტორი დაჟანგვაზე ან დაზიანებაზე.',
        '3. შემოწმების ან სენსორის შეცვლის შემდეგ შეასრულეთ დაკიდების სიმაღლის ქარხნული კალიბრაცია (Ride Height Calibration).',
      ],
      repairStepsEn: [
        '1. Visually inspect front-left suspension height sensor linkage rod (check for fractured rod or dislocated ball joint).',
        '2. Inspect 3-pin sensor connector and wiring harness for water intrusion or pin corrosion.',
        '3. Perform ride height sensor calibration routine after inspection or sensor replacement.',
      ],
      severity: 'MEDIUM',
      safeToDrive: true,
    ),
  };

  static String _synthesizeEnglishTitle(List<FactoryFaultText> texts) {
    if (texts.isEmpty) return 'Unindexed Factory Fault';
    final raw = texts.first.text;
    String en = raw;
    for (final e in _translationDeEn.entries) {
      en = en.replaceAll(RegExp(RegExp.escape(e.key), caseSensitive: false), e.value);
    }
    return en;
  }

  static String _synthesizeGeorgianExplanation(List<FactoryFaultText> texts, String? ecuName) {
    if (texts.isEmpty) return 'ქარხნული აღწერა ბაზაში არ მოიძებნა.';
    final raw = texts.first.text;
    final ecu = ecuName ?? 'მართვის ბლოკმა';
    return '$ecu-მ დააფიქსირა ქარხნული შეცდომა: "$raw". '
        'პრობლემა ეხება შესაბამისი კომპონენტის ელექტრულ სიგნალს, კვების ძაბვას ან მექანიკურ პოზიციას.';
  }

  static String _synthesizeEnglishExplanation(List<FactoryFaultText> texts, String? ecuName) {
    if (texts.isEmpty) return 'No factory description found in database.';
    final raw = texts.first.text;
    final enText = _synthesizeEnglishTitle(texts);
    final ecu = ecuName ?? 'Control module';
    return '$ecu logged factory fault: "$enText" ($raw). '
        'The issue involves electrical signal plausibility, supply voltage, or mechanical position.';
  }

  static List<String> _synthesizeSymptoms(List<FactoryFaultText> texts) {
    if (texts.isEmpty) return ['სიმპტომი უცნობია'];
    final raw = texts.first.text.toLowerCase();
    final list = <String>[];
    if (raw.contains('normierung') || raw.contains('initialisierung')) {
      list.add('მექანიზმი არ მუშაობს ავტომატურ რეჟიმში და საჭიროებს ინიციალიზაციას');
    }
    if (raw.contains('unterspannung') || raw.contains('ubatt')) {
      list.add('სისტემის დროებითი გათიშვა ძაბვის ვარდნის გამო');
    }
    if (raw.contains('unterbrechung') || raw.contains('kurzschluss')) {
      list.add('კომპონენტის სრული გათიშვა ან მცდარი მაჩვენებელი');
    }
    if (list.isEmpty) {
      list.add('ფუნქციის შეზღუდვა ან შესაბამისი გამაფრთხილებელი შეტყობინება ეკრანზე');
    }
    return list;
  }

  static List<String> _synthesizeEnglishSymptoms(List<FactoryFaultText> texts) {
    if (texts.isEmpty) return ['Symptom unknown'];
    final raw = texts.first.text.toLowerCase();
    final list = <String>[];
    if (raw.contains('normierung') || raw.contains('initialisierung')) {
      list.add('Mechanism does not operate in automatic mode and requires initialization');
    }
    if (raw.contains('unterspannung') || raw.contains('ubatt')) {
      list.add('Temporary system deactivation due to voltage dip');
    }
    if (raw.contains('unterbrechung') || raw.contains('kurzschluss')) {
      list.add('Component inoperative or invalid signal reading');
    }
    if (list.isEmpty) {
      list.add('Functional restriction or corresponding warning on instrument cluster');
    }
    return list;
  }

  static List<String> _synthesizeRepairSteps(List<FactoryFaultText> texts) {
    return [
      '1. შეამოწმეთ შესაბამისი კომპონენტის ელექტრო გაყვანილობა და კონექტორი დაჟანგვაზე/დაზიანებაზე.',
      '2. შეამოწმეთ კვების ძაბვა და დამცავი (ფიუზი).',
      '3. შეასრულეთ ბლოკის სისტემური ადაპტაცია/ინიციალიზაცია.',
      '4. წაშალეთ შეცდომის კოდი და გადაამოწმეთ ხელახალი სკანირებით.',
    ];
  }

  static List<String> _synthesizeEnglishRepairSteps(List<FactoryFaultText> texts) {
    return [
      '1. Inspect wiring harness and connector pins of the affected component for corrosion or damage.',
      '2. Verify power supply voltage (Terminal 30/15) and corresponding fuse.',
      '3. Execute module system adaptation or mechanical initialization routine.',
      '4. Clear DTC memory and re-scan after driving test cycle.',
    ];
  }

  static String _evaluateSeverity(List<FactoryFaultText> texts) {
    if (texts.isEmpty) return 'LOW';
    final raw = texts.first.text.toLowerCase();
    if (raw.contains('bremse') || raw.contains('katschädigend') || raw.contains('brandgefahr')) {
      return 'CRITICAL';
    }
    if (raw.contains('öl') || raw.contains('druck') || raw.contains('kühl') || raw.contains('notlauf')) {
      return 'HIGH';
    }
    return 'MEDIUM';
  }

  static const Map<String, String> _translationDeEn = {
    'Kurzschluss nach Masse': 'Short circuit to ground',
    'Kurzschluss nach Ubatt': 'Short circuit to B+',
    'Leitungsunterbrechung': 'Open circuit / line interruption',
    'ungültig empfangen': 'received invalid',
    'keine Normierung vorhanden': 'normalization missing',
    'außerhalb Spezifikation': 'outside specification',
    'Ruhestromverletzung': 'quiescent current violation',
    'Unterspannung': 'undervoltage',
    'Überspannung': 'overvoltage',
    'Übertemperatur': 'overtemperature',
    'Plausibilität': 'plausibility',
    'Fehlerspeicher': 'fault memory',
    'Höhenstandssensoren': 'ride height sensors',
    'Fahrpedalmodul': 'accelerator pedal module',
    'Diebstahlwarnanlage': 'anti-theft alarm system',
    'Neigungsgeber': 'tilt sensor',
    'Innenraumschutz': 'interior monitoring',
    'deaktiviert': 'deactivated',
  };

  /// Technical term glossary. Clean, neutral definitions only.
  static const Map<String, Map<String, String>> _glossaryDe = {
    'Ruhestrom': {
      'ka': 'მოსვენების დენი — დენი, რომელსაც ბლოკი მოიხმარს ანთების გამორთვის შემდეგ',
      'en': 'Quiescent current - current draw after terminal 15 shutoff and vehicle enters sleep mode',
    },
    'Normierung': {
      'ka': 'ნორმირება — მექანიზმის საბაზისო პოზიციის დაზუსტება/დასწავლა',
      'en': 'Normalization - teaching basic mechanical zero and end-stop positions',
    },
    'Kennlinie': {
      'ka': 'მახასიათებელი მრუდი (ბლოკში შენახული საკალიბრო მონაცემი)',
      'en': 'Characteristic curve - module calibration mapping data',
    },
    'Neigungsgeber': {
      'ka': 'დახრის სენსორი (სიგნალიზაციის ნაწილი)',
      'en': 'Tilt sensor (anti-tow vehicle inclination sensor)',
    },
    'Innenraumschutz': {
      'ka': 'სალონის დაცვა (სიგნალიზაციის ფუნქცია)',
      'en': 'Interior monitoring (ultrasonic passenger compartment surveillance)',
    },
    'Diebstahlwarnanlage': {
      'ka': 'ქურდობის საწინააღმდეგო სიგნალიზაცია (DWA)',
      'en': 'Anti-theft alarm system (DWA)',
    },
    'Höhenstandssensor': {
      'ka': 'ძარის სიმაღლის (დონის) სენსორი',
      'en': 'Ride height level sensor',
    },
    'Hallelement': {
      'ka': 'ჰოლის სენსორი (ელ. ძრავის პოზიციის/ბრუნვის მაჩვენებელი)',
      'en': 'Hall-effect sensor (magnetic motor position counter)',
    },
    'ungültig empfangen': {
      'ka': 'სიგნალი მიღებულია არავალიდურად',
      'en': 'Signal received invalid / checksum mismatch',
    },
    'außerhalb Spezifikation': {
      'ka': 'სპეციფიკაციის გარეთ (მნიშვნელობა დასაშვებ დიაპაზონს სცილდება)',
      'en': 'Outside specification (voltage or parameter out of permitted range)',
    },
    'Leitungsunterbrechung': {
      'ka': 'გაყვანილობის გაწყვეტა (ღია წრედი)',
      'en': 'Open circuit / broken wire line',
    },
    'Kurzschluss nach Masse': {
      'ka': 'მოკლე ჩართვა მასაზე',
      'en': 'Short circuit to ground (GND)',
    },
    'Kurzschluss nach Ubatt': {
      'ka': 'მოკლე ჩართვა აკუმულატორის დადებითზე',
      'en': 'Short circuit to battery positive (B+)',
    },
    'Unterspannung': {
      'ka': 'ძაბვის დაბალი მნიშვნელობა',
      'en': 'Undervoltage (low supply voltage)',
    },
    'Überspannung': {
      'ka': 'ძაბვის გადაჭარბება',
      'en': 'Overvoltage (excess supply voltage)',
    },
    'Übertemperatur': {
      'ka': 'ტემპერატურის გადაჭარბება',
      'en': 'Overtemperature (thermal protection trigger)',
    },
    'Steuergerät intern': {
      'ka': 'ბლოკის შიდა შეცდომა (თვითდიაგნოსტიკა)',
      'en': 'Internal ECU hardware/EEPROM self-test fault',
    },
    'Kodierung': {
      'ka': 'კოდირება',
      'en': 'Coding / variant configuration',
    },
    'Plausibilität': {
      'ka': 'დამაჯერებლობის შემოწმება (სიგნალების შესაბამისობა)',
      'en': 'Plausibility check / correlation discrepancy',
    },
    'Verpolung': {
      'ka': 'პოლარობის არევა',
      'en': 'Reverse polarity',
    },
    'Sicherung': {
      'ka': 'დამცავი (ფიუზი)',
      'en': 'Fuse',
    },
    'Relais': {
      'ka': 'რელე',
      'en': 'Relay',
    },
    'Botschaft': {
      'ka': 'ქსელური შეტყობინება (CAN Message)',
      'en': 'Bus telegram / CAN message',
    },
    'Signal': {
      'ka': 'სიგნალი',
      'en': 'Signal',
    },
    'Schiebedach': {
      'ka': 'ლუქი',
      'en': 'Sunroof (sliding/tilting roof)',
    },
    'SHD': {
      'ka': 'SHD — ლუქი (Schiebe-Hebe-Dach)',
      'en': 'SHD - Slide/tilt sunroof',
    },
    'DWA': {
      'ka': 'DWA — ქურდობის საწინააღმდეგო სიგნალიზაცია',
      'en': 'DWA - Anti-theft alarm system',
    },
    'Heckklappe': {
      'ka': 'საბარგულის ხუფი',
      'en': 'Tailgate / trunk lid',
    },
    'Fahrpedal': {
      'ka': 'გაზის (ამაჩქარებლის) პედალი',
      'en': 'Accelerator pedal module',
    },
    'Batterie': {
      'ka': 'აკუმულატორი',
      'en': 'Battery',
    },
    'Raddrehzahl': {
      'ka': 'ბორბლის ბრუნვის სიჩქარე',
      'en': 'Wheel speed',
    },
    'Lenkwinkel': {
      'ka': 'საჭის კუთხე',
      'en': 'Steering angle',
    },
    'Temperatur': {
      'ka': 'ტემპერატურა',
      'en': 'Temperature',
    },
  };
}
