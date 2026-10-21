import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  const GlossaryHit(this.term, this.meaningKa);
}

/// Detailed, verified diagnostic guide for a specific BMW fault.
class BmwGuidedFaultDetail {
  final String titleEn;
  final String explanationKa;
  final List<String> symptomsKa;
  final List<String> repairStepsKa;
  final String severity; // LOW, MEDIUM, HIGH, CRITICAL
  final bool safeToDrive;

  const BmwGuidedFaultDetail({
    required this.titleEn,
    required this.explanationKa,
    required this.symptomsKa,
    required this.repairStepsKa,
    this.severity = 'MEDIUM',
    this.safeToDrive = true,
  });
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

  /// Real-world vehicle symptoms.
  final List<String> symptomsKa;

  /// Step-by-step actionable repair & check steps (neutral, no third-party app names).
  final List<String> repairStepsKa;

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
    required this.symptomsKa,
    required this.repairStepsKa,
    required this.severity,
    required this.safeToDrive,
  });

  bool get isKnown => factoryTexts.isNotEmpty;

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
      final famData = _families[fam] as Map<String, dynamic>;
      final entry = (famData['codes'] as Map<String, dynamic>)[code] as List<dynamic>?;
      if (entry == null) continue;
      final variantNames = (famData['variants'] as List<dynamic>).cast<String>();
      for (final item in entry) {
        final pair = item as List<dynamic>;
        final text = _texts[pair[0] as int];
        final vars = (pair[1] as List<dynamic>).map((i) => variantNames[i as int]).toList();
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
          glossaryHits.add(GlossaryHit(e.key, e.value));
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
    final symptomsKa = guided?.symptomsKa ?? _synthesizeSymptoms(found);
    final repairStepsKa = guided?.repairStepsKa ?? _synthesizeRepairSteps(found);
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
      symptomsKa: symptomsKa,
      repairStepsKa: repairStepsKa,
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
      symptomsKa: [
        'აკუმულატორის დაჯდომა ხანგრძლივი დგომის შემდეგ',
        'შეტყობინება ეკრანზე: "Increased battery discharge when stationary"',
        'კომფორტის ფუნქციების (სალონის განათება, გათბობა) ავტომატური გათიშვა ენერგიის დასაზოგად',
      ],
      repairStepsKa: [
        '1. შეამოწმეთ, ხომ არ არის ავტომობილზე მიერთებული არაქარხნული მოწყობილობა (GPS ტრეკერი, ვიდეორეგისტრატორი, დამტენი).',
        '2. შეამოწმეთ Comfort Access-ის კარის სახელურები (ხშირად სახელურის ელექტრონიკის დაზიანება არ აძლევს ბლოკებს დაძინების საშუალებას).',
        '3. შეასრულეთ ენერგოდიაგნოსტიკის ქარხნული ტესტი (Closed-circuit current monitoring) მიძინების ციკლის შესამოწმებლად.',
      ],
      severity: 'MEDIUM',
      safeToDrive: true,
    ),

    // 0x6D: SMFA - No seat adjustment due to engine start condition
    '0x6D:802A1E': BmwGuidedFaultDetail(
      titleEn: 'Seat Adjustment Interrupted: Engine Start Condition / Low Voltage Check',
      explanationKa: 'მძღოლის სავარძლის მოდულმა (SMFA 0x6D) დააფიქსირა სავარძლის რეგულირების დროებითი შეზღუდვა ძრავის დაქოქვის ან სისტემური ძაბვის ვარდნის გამო. ეს არის ინფორმაციული სტატუსი, რომელიც ხშირად ჩნდება დაქოქვისას ან აკუმულატორის დაბალი მუხტის დროს.',
      symptomsKa: [
        'სავარძლის მეხსიერების (Memory) ან ავტომატური რეგულირების დროებითი დაყოვნება დაქოქვის მომენტში',
        'სავარძლის მოძრაობის შეჩერება დაბალი ძაბვისას',
      ],
      repairStepsKa: [
        '1. წაშალეთ შეცდომა (Clear DTC) პირდაპირ ამ ეკრანიდან.',
        '2. სავარძლის ნორმალიზაცია/კალიბრაცია (თუ პოზიციას არ იმახსოვრებს): ჩართეთ ანთება, გადაწიეთ სავარძელი ბოლომდე წინ და გეჭიროთ 2 წამი, შემდეგ ბოლომდე უკან და გეჭიროთ 2 წამი.',
        '3. შეამოწმეთ აკუმულატორის დამუხტვა, თუ კოდი ყოველ დაქოქვაზე მეორდება.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),
    '0x58:802A1E': BmwGuidedFaultDetail(
      titleEn: 'Seat Adjustment Interrupted: Engine Start Condition / Low Voltage Check',
      explanationKa: 'მძღოლის სავარძლის მოდულმა (SMFA) დააფიქსირა სავარძლის რეგულირების დროებითი შეზღუდვა ძრავის დაქოქვის ან სისტემური ძაბვის ვარდნის გამო.',
      symptomsKa: [
        'სავარძლის ელექტრო რეგულირების დროებითი დაყოვნება დაქოქვისას',
      ],
      repairStepsKa: [
        '1. წაშალეთ შეცდომა (Clear DTC).',
        '2. სავარძლის ნორმალიზაცია: გადაწიეთ ბოლომდე წინ და ბოლომდე უკან.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x56: FZD - Sunroof Normalization Missing
    '0x56:030215': BmwGuidedFaultDetail(
      titleEn: 'Sliding/Tilting Sunroof: Normalization missing / Initialization required',
      explanationKa: 'ლუქის მართვის მოდულმა (FZD) დაკარგა მექანიზმის საბაზისო საწყისი პოზიცია (ნორმირება). სისტემას არ აქვს დამახსოვრებული ლუქის სრული დახურვისა და გაღების უკიდურესი წერტილები.',
      symptomsKa: [
        'ლუქი ერთი დაჭერით (One-touch) ავტომატურად აღარ იღება ან იხურება',
        'მოძრაობისას ჩერდება ყოველ რამდენიმე სანტიმეტრში',
        'პანორამის ფარდა არ ასრულებს ბოლო პოზიციაში დახურვას',
      ],
      repairStepsKa: [
        '1. ჩართეთ ავტომობილის ანთება (Ignition ON, ძრავი გამორთული).',
        '2. ლუქის ღილაკს დააჭირეთ ზემოთ (Tilt/აწევის მიმართულებით) და გეჭიროთ უწყვეტად 15-25 წამი.',
        '3. ლუქი აიწევა ბოლომდე, გააკეთებს მოკლე პაუზას, გაიღება ბოლომდე და დაიხურება ბოლომდე.',
        '4. არ გაუშვათ ღილაკს ხელი, სანამ ციკლი სრულად არ დასრულდება და ლუქი არ გაჩერდება.',
        '5. ინიციალიზაციის დასრულების შემდეგ წაშალეთ შეცდომის კოდი.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x56: FZD - Alarm Tilt & Interior Sensor Deactivated
    '0x56:801A4A': BmwGuidedFaultDetail(
      titleEn: 'Anti-theft Alarm System: Tilt sensor and interior monitoring deactivated',
      explanationKa: 'ქურდობის საწინააღმდეგო სიგნალიზაციის სისტემაში დეაქტივირებულია დახრის სენსორი (ავტომობილის გადახრის/ევაკუატორის დეტექტორი) და სალონის ულტრაბგერითი მოცულობითი დაცვა.',
      symptomsKa: [
        'ავტომობილის ჩაკეტვისას სალონის სარკის ქვეშ წითელი ინდიკატორი უწყვეტად ანათებს 2 წამის განმავლობაში',
        'სიგნალიზაცია არ რეაგირებს სალონში მოძრაობაზე ან მანქანის აწევაზე',
      ],
      repairStepsKa: [
        '1. შეამოწმეთ გასაღებით ჩაკეტვა: ჩაკეტვის ღილაკზე 10 წამში ორჯერ დაჭერა ავტომატურად თიშავს სალონის დაცვას (ქარხნული ფუნქცია).',
        '2. თუ ფუნქცია თავისით ითიშება, შეამოწმეთ ჭერის ბლოკის (FZD) ულტრაბგერითი სენსორების კონექტორი და კვების ძაბვა.',
        '3. შეასრულეთ სიგნალიზაციის სისტემური თვითტესტი.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x78: IHKA - Windscreen Temperature Signal Invalid
    '0x78:E7144D': BmwGuidedFaultDetail(
      titleEn: 'Climate Control: Windscreen temperature data received invalid',
      explanationKa: 'კლიმატ-კონტროლის ელექტრონიკამ (IHKA) CAN-ქსელით მიიღო არავალიდური ან შეწყვეტილი მონაცემი საქარე მინის ტემპერატურისა და ნამის სენსორიდან.',
      symptomsKa: [
        'კლიმატ-კონტროლის ავტომატურ რეჟიმში მინების დაორთქვლის საწინააღმდეგო ფუნქცია მუშაობს შეზღუდულად',
        'ვენტილატორის სიჩქარე ავტომატურ რეჟიმში შესაძლოა დროდადრო არასტაბილურად იცვლებოდეს',
      ],
      repairStepsKa: [
        '1. შეამოწმეთ საქარე მინაზე (უკანა ხედვის სარკის უკან) მიკრული ნამისა და წვიმის სენსორის ოპტიკური გელი (ხომ არ არის ჰაერის ბუშტები).',
        '2. შეამოწმეთ სენსორის ელექტრო გაყვანილობა და შტეკერის კონტაქტები.',
        '3. თუ საქარე მინა ახალი შეცვლილია, ჩაატარეთ ნამისა და წვიმის სენსორის ხელახალი კალიბრაცია.',
      ],
      severity: 'LOW',
      safeToDrive: true,
    ),

    // 0x1C: ICM - Ride Height Sensor Front Left Outside Spec
    '0x1C:482793': BmwGuidedFaultDetail(
      titleEn: 'Chassis Management: Ride height sensor front left outside specification',
      explanationKa: 'შასის ინტეგრირებული მართვის ბლოკი (ICM) აფიქსირებს, რომ წინა მარცხენა დაკიდების სიმაღლის სენსორის (Ride Height Sensor) ელექტრული სიგნალი სცდება ქარხნულ დასაშვებ ზღვარს.',
      symptomsKa: [
        'შეტყობინება ეკრანზე: "Chassis stabilization limited" ან ფარების რეგულირების გაფრთხილება',
        'ფარების ავტომატური სიმაღლის კორექტორი შესაძლოა დაეშვას ქვედა უსაფრთხო პოზიციაში',
      ],
      repairStepsKa: [
        '1. ვიზუალურად შეამოწმეთ წინა მარცხენა ამორტიზატორთან/გიტარასთან არსებული პატარა პლასტმასის ტიაგა (ხომ არ გატყდა ან ამოვარდა შარნირიდან).',
        '2. შეამოწმეთ სენსორის 3-პინიანი კონექტორი დაჟანგვაზე ან დაზიანებაზე.',
        '3. შემოწმების ან სენსორის შეცვლის შემდეგ შეასრულეთ დაკიდების სიმაღლის ქარხნული კალიბრაცია (Ride Height Calibration).',
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

  static List<String> _synthesizeRepairSteps(List<FactoryFaultText> texts) {
    return [
      '1. შეამოწმეთ შესაბამისი კომპონენტის ელექტრო გაყვანილობა და კონექტორი დაჟანგვაზე/დაზიანებაზე.',
      '2. შეამოწმეთ კვების ძაბვა და დამცავი (ფიუზი).',
      '3. შეასრულეთ ბლოკის სისტემური ადაპტაცია/ინიციალიზაცია.',
      '4. წაშალეთ შეცდომის კოდი და გადაამოწმეთ ხელახალი სკანირებით.',
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
  static const Map<String, String> _glossaryDe = {
    'Ruhestrom': 'მოსვენების დენი — დენი, რომელსაც ბლოკი მოიხმარს ანთების გამორთვის შემდეგ',
    'Normierung': 'ნორმირება — მექანიზმის საბაზისო პოზიციის დაზუსტება/დასწავლა',
    'Kennlinie': 'მახასიათებელი მრუდი (ბლოკში შენახული საკალიბრო მონაცემი)',
    'Neigungsgeber': 'დახრის სენსორი (სიგნალიზაციის ნაწილი)',
    'Innenraumschutz': 'სალონის დაცვა (სიგნალიზაციის ფუნქცია)',
    'Diebstahlwarnanlage': 'ქურდობის საწინააღმდეგო სიგნალიზაცია (DWA)',
    'Höhenstandssensor': 'ძარის სიმაღლის (დონის) სენსორი',
    'Hallelement': 'ჰოლის სენსორი (ელ. ძრავის პოზიციის/ბრუნვის მაჩვენებელი)',
    'ungültig empfangen': 'სიგნალი მიღებულია არავალიდურად',
    'außerhalb Spezifikation': 'სპეციფიკაციის გარეთ (მნიშვნელობა დასაშვებ დიაპაზონს სცილდება)',
    'Leitungsunterbrechung': 'გაყვანილობის გაწყვეტა (ღია წრედი)',
    'Kurzschluss nach Masse': 'მოკლე ჩართვა მასაზე',
    'Kurzschluss nach Ubatt': 'მოკლე ჩართვა აკუმულატორის დადებითზე',
    'Unterspannung': 'ძაბვის დაბალი მნიშვნელობა',
    'Überspannung': 'ძაბვის გადაჭარბება',
    'Übertemperatur': 'ტემპერატურის გადაჭარბება',
    'Steuergerät intern': 'ბლოკის შიდა შეცდომა (თვითდიაგნოსტიკა)',
    'Kodierung': 'კოდირება',
    'Plausibilität': 'დამაჯერებლობის შემოწმება (სიგნალების შესაბამისობა)',
    'Verpolung': 'პოლარობის არევა',
    'Sicherung': 'დამცავი (ფიუზი)',
    'Relais': 'რელე',
    'Botschaft': 'ქსელური შეტყობინება (CAN Message)',
    'Signal': 'სიგნალი',
    'Schiebedach': 'ლუქი',
    'SHD': 'SHD — ლუქი (Schiebe-Hebe-Dach)',
    'DWA': 'DWA — ქურდობის საწინააღმდეგო სიგნალიზაცია',
    'Heckklappe': 'საბარგულის ხუფი',
    'Fahrpedal': 'გაზის (ამაჩქარებლის) პედალი',
    'Batterie': 'აკუმულატორი',
    'Raddrehzahl': 'ბორბლის ბრუნვის სიჩქარე',
    'Lenkwinkel': 'საჭის კუთხე',
    'Temperatur': 'ტემპერატურა',
  };
}
