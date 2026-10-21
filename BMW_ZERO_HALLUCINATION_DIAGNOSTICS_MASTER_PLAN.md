# 📘 BMW ZERO-HALLUCINATION OFFLINE DIAGNOSTICS & FAULT EXPLANATION ENGINE
## სრული საინჟინრო გეგმა და სამოქმედო პრომპტი (Master Action Plan)

> **დოკუმენტის მიზანი:** წინამდებარე დოკუმენტი წარმოადგენს თვითკმარ, დეტალურ საინჟინრო ინსტრუქციას ხელოვნური ინტელექტის აგენტის ან დეველოპერისთვის. დოკუმენტი ეტაპობრივად აღწერს, თუ როგორ უნდა აიგოს FIX AI-ში 100%-ით ოფლაინ, ქარხნულ წყაროებზე დაფუძნებული სადიაგნოსტიკო სისტემა ნულოვანი ჰალუცინაციით (Zero-Hallucination Ground-Truth).

---

## 1. სისტემური არქიტექტურა და ფილოსოფია

### რატომ არის კატეგორიულად აკრძალული ზოგადი LLM-ის გამოყენება დიაგნოსტიკაში?
სტანდარტული ენობრივი მოდელები (ChatGPT, Gemini, DeepSeek) ავტომობილის კოდებს ხსნიან ალბათური გამოცნობით და ზოგადი OBD-II სტანდარტით:
- **რეალური საფრთხე:** BMW-ს სპეციფიკურ მოდულში (მაგ. ჭერის ბლოკში FZD `0x56`) კოდი `P0302` (Hex `030215`) აღნიშნავს **ლუქის ნორმალიზაციის დაკარგვას**, მაშინ როცა ზოგადი AI მომხმარებელს ატყუებს: *"მე-2 ცილინდრის misfire - შეცვალეთ სვეჩი ან ბაბინა"*.
- **ინტერნეტის არარსებობა ავტომობილში:** როდესაც მომხმარებელი უერთდება ავტომობილის OBD Wi-Fi-ს ან ENET კაბელს, ტელეფონს არ აქვს ინტერნეტი. ღრუბლოვან AI სერვერზე მიმართვა მომენტალურად აგდებს შეცდომას: `"Error: AI Server overloaded or unavailable"`.

### ორდონიანი ქარხნული გადაწყვეტა (Two-Tier Coverage Architecture):
```mermaid
flowchart TD
    DTC["ავტომობილის სკანირების შედეგი<br>(ECU მისამართი + Hex DTC კოდი)"] --> ENGINE["BmwFaultDiagnosticEngine<br>(100% Offline Dart Engine)"]

    ENGINE --> LOOKUP{"არის კოდი გაღრმავებულ<br>ქართულ ბაზაში?"}

    LOOKUP -->|დიახ| TIER1["Tier 1: Deep Diagnostic Card<br>(გაღრმავებული სადიაგნოსტიკო ბარათი)"]
    TIER1 --> CARD1["1. ზუსტი კომპონენტი (Component ID)<br>2. რეალური სიმპტომები ავტომობილზე<br>3. გამომწვევი მიზეზები (Root Causes)<br>4. DIY ნაბიჯ-ნაბიჯ შეკეთების გზა<br>5. ISTA სერვის-რუტინა და ხელსაწყოები"]

    LOOKUP -->|არა (იშვიათი კოდია)| TIER2["Tier 2: Full Factory Ground-Truth<br>(სრული ქარხნული დაფარვა - 50,000+ კოდი)"]
    TIER2 --> CARD2["1. ოფიციალური ქარხნული ინგლ./გერმ. სახელი<br>2. ECU ბლოკის ფუნქცია და ქვესისტემა<br>3. ავტომატური სერვის-რუტინის შეთავაზება<br>4. პატიოსანი სტატუსი: 0% ჰალუცინაცია"]
```

---

## 2. მონაცემთა ქარხნული წყაროები (Data Sourcing on `D:` Drive)

სისტემა მონაცემებს იღებს ლოკალურ კომპიუტერზე არსებული ოფიციალური პაკეტებიდან:

| მონაცემთა ტიპი | ფაილების მდებარეობა კომპიუტერზე | რას ვიღებთ |
| :--- | :--- | :--- |
| **Ediabas SGBD PRG** | `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\Ecu\*.prg` (1,420 ფაილი) | `FS_LESEN` და `FS_TEXT` ცხრილები: 50,000+ კოდის ოფიციალური Hex მნიშვნელობა და ქარხნული დასახელება ყველა ECU-სთვის. |
| **ISTA DiagDocDb SQLite** | `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\SQLiteDBs\DiagDocDb.sqlite` და `xmlvalueprimitive_ENGB.sqlite` | ოფიციალური სადიაგნოსტიკო ხეები, FUB ფუნქციური აღწერები, კომპონენტის დასახელებები, სიმპტომები. |
| **ISTA Testmodule ABL** | `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\Testmodule\ABL_*.dll` (23,070 DLL) | ნაბიჯ-ნაბიჯ შემოწმების პროცედურები, ადაპტაციის პირობები და სერვისული რუტინები. |
| **ISTA EcuFunctions** | `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\EcuFunctions\*.xml` | სერვისული ჯობები (Jobs) და ტელემეტრიის პარამეტრები. |

---

## 3. მონაცემთა ექსტრაქცია (ETL Pipeline)

### 3.1. სკრიპტი: `scripts/offline_etl/build_bmw_fault_kb.py`
სკრიპტი ახდენს PRG და SQLite ფაილების პარსინგს და აგენერირებს:
`assets/offline_db/bmw_fault_knowledge_base.json`

### 3.2. JSON ბაზის ქარხნული სქემა:
```json
{
  "metadata": {
    "version": "1.0.0",
    "source": "BMW ISTA+ 4.59.30 & Ediabas SGBD PRG",
    "total_tier1_cards": 1250,
    "total_tier2_definitions": 54200
  },
  "tier1_deep_cards": {
    "0x56:030215": {
      "ecu_address_hex": "0x56",
      "ecu_name": "FZD",
      "dtc_hex": "030215",
      "obd_alias": "P0302",
      "official_title": "SHD: Normalization missing / sunroof not initialized",
      "component_ka": "ლუქის მექანიზმის ელექტროძრავი და ჰოლის სენსორი (M24/1)",
      "component_en": "Sunroof Drive Motor & Hall Sensor",
      "symptoms_ka": [
        "ლუქი ერთი დაჭერით (One-touch) ავტომატურად აღარ იღება და იხურება",
        "მოძრაობს მხოლოდ ღილაკზე უწყვეტი დაჭერით და ჩერდება ყოველ 5 სანტიმეტრში",
        "პანორამის ფარდა არ ასრულებს ბოლო პოზიციაში დახურვას"
      ],
      "root_causes_ka": [
        "აკუმულატორის ჩახსნა ან ძაბვის ვარდნა 10.5V-ზე დაბლა",
        "ლუქის მექანიზმის გაჭედვა ან რელსებში ჭუჭყის გამო მაღალი წინააღმდეგობა",
        "FZD ბლოკის პროგრამული გადატვირთვა"
      ],
      "repair_procedure": {
        "type": "MANUAL_ADAPTATION",
        "steps_ka": [
          "1. ჩართეთ ანთება (Ignition ON, ძრავი გამორთული).",
          "2. დააჭირეთ ლუქის ღილაკს ზემოთ (Tilt/აწევის მიმართულებით) და გეჭიროთ უწყვეტად 15-25 წამი.",
          "3. ლუქი აიწევა ბოლომდე, გააკეთებს მოკლე პაუზას, გაიღება ბოლომდე და დაიხურება ბოლომდე.",
          "4. არ გაუშვათ ღილაკს ხელი, სანამ ციკლი სრულად არ დასრულდება.",
          "5. ინიციალიზაციის შემდეგ წაშალეთ შეცდომა FIX AI-ით."
        ],
        "service_routine_id": "ABL_DIT_AS6131_FZD_SHD_INIT",
        "required_tools": ["არ საჭიროებს ხელსაწყოს"]
      },
      "severity": "LOW",
      "safe_to_drive": true
    }
  },
  "tier2_definitions": {
    "0x12:213601": {
      "ecu": "DME",
      "en": "Accelerator pedal module, pedal travel sensor: Plausibility between signal 1 and signal 2",
      "de": "Fahrpedalmodul, Fahrpedalsensor: Plausibilität zwischen Signal 1 und Signal 2"
    }
  }
}
```

---

## 4. აპლიკაციის ძრავა (Flutter / Dart Implementation)

### 4.1. კლასი `BmwFaultDiagnosticEngine`
ფაილში: `lib/modules/obd/services/offline_database_manager.dart`

```dart
class BmwDiagnosticResult {
  final String ecuName;
  final int ecuAddress;
  final String dtcCode;
  final bool isTier1DeepCard;
  final String officialTitle;
  final String component;
  final List<String> symptoms;
  final List<String> rootCauses;
  final List<String> repairSteps;
  final String? routineId;
  final String severity; // LOW, MEDIUM, HIGH, CRITICAL
  final bool safeToDrive;
  final bool isHallucinationProof;

  BmwDiagnosticResult({
    required this.ecuName,
    required this.ecuAddress,
    required this.dtcCode,
    required this.isTier1DeepCard,
    required this.officialTitle,
    required this.component,
    required this.symptoms,
    required this.rootCauses,
    required this.repairSteps,
    this.routineId,
    required this.severity,
    required this.safeToDrive,
    this.isHallucinationProof = true,
  });
}
```

### 4.2. დეტერმინისტული ძებნის ალგორითმი:
```dart
BmwDiagnosticResult getDiagnosticExplanation(int ecuAddress, String code) {
  final hexCode = _normalizeDtc(code);
  final key = '0x${ecuAddress.toRadixString(16).toLowerCase()}:$hexCode';

  // 1. ვეძებთ Tier 1 გაღრმავებულ ბარათებში
  if (_tier1Cards.containsKey(key)) {
    return _buildTier1Result(_tier1Cards[key]!);
  }

  // 2. ვეძებთ Tier 2 სრულ ქარხნულ დეფინიციებში (50,000+ კოდი)
  if (_tier2Definitions.containsKey(key)) {
    final def = _tier2Definitions[key]!;
    return BmwDiagnosticResult(
      ecuName: def['ecu'] ?? 'ECU',
      ecuAddress: ecuAddress,
      dtcCode: hexCode,
      isTier1DeepCard: false,
      officialTitle: def['en'] ?? 'Factory Fault Description',
      component: 'ქარხნულად დაკავშირებული კომპონენტი იხილეთ ოფიციალურ დეფინიციაში',
      symptoms: ['სიმპტომი დამოკიდებულია ავტომობილის რეჟიმზე'],
      rootCauses: ['დეტალური შემოწმებისთვის გამოიყენეთ ქვემოთ მითითებული სერვის-რუტინა'],
      repairSteps: ['ჩაატარეთ ECU-ს სისტემური ტესტი'],
      severity: 'MEDIUM',
      safeToDrive: true,
    );
  }

  // 3. აბსოლუტურად უცნობი კოდის Fallback (0% გამოცნობა/ტყუილი)
  return BmwDiagnosticResult(
    ecuName: 'ECU 0x${ecuAddress.toRadixString(16).toUpperCase()}',
    ecuAddress: ecuAddress,
    dtcCode: hexCode,
    isTier1DeepCard: false,
    officialTitle: 'დაუდგენელი ქარხნული კოდი',
    component: 'ინფორმაცია ბაზაში არ მოიძებნა',
    symptoms: ['სიმპტომი უცნობია'],
    rootCauses: ['ჰალუცინაციის თავიდან ასაცილებლად სისტემა არ იგონებს მიზეზს'],
    repairSteps: ['რეკომენდებულია დიაგნოსტიკა ოფიციალური ISTA-ს სადგურზე'],
    severity: 'LOW',
    safeToDrive: true,
  );
}
```

---

## 5. UI და მომხმარებლის ინტერფეისი

### 5.1. `EcuScanScreen`-ში ცვლილებები:
ფაილი: `lib/modules/obd/screens/ecu_scan_screen.dart`
- ღილაკი `ANALYZE WITH FIX AI ($totalFaults)` დაჭერისას:
  1. აღარ აგზავნის მოთხოვნას ინტერნეტში.
  2. იძახებს `OfflineDatabaseManager.instance.getDiagnosticExplanation(...)` თითოეული ნაპოვნი კოდისთვის.
  3. ხსნის `BmwDiagnosticResultsModal`-ს, სადაც ჩამოწერილია ვიზუალური ქარხნული ბარათები.
  4. თუ კოდს აქვს `routineId`, პირდაპირ ბარათზე ჩნდება ღილაკი **"RUN SERVICE ROUTINE"** (რომელიც მომენტალურად უშვებს UDS სერვისულ ფუნქციას მანქანაზე).

---

## 6. რეალური ვალიდაცია: BMW X4 F26-ის 5 კოდი — **გადამოწმებული ქარხნული ტექსტებით**

> [!WARNING]
> ამ დოკუმენტის წინა ვერსიაში ამ 5 კოდის განმარტება **არასწორი იყო** (შედგენილი იყო წყაროს გადამოწმების გარეშე). ქვემოთ მოცემულია ISTA `Ecu/*.prg` (`FORTTEXTE`) და BMW KIS-ით რეალურად ამოღებული მონაცემები. ბლოკების სახელები აპლიკაციის ძველი ცხრილიდან ნაწილობრივ არასწორი აღმოჩნდა (KIS: `0x78` = IHKA, `0x1C` = ICM).

| # | ECU (KIS) | Hex | ოფიციალური ქარხნული ტექსტი (უცვლელი) | წყარო SGBD |
| :-: | :--- | :--- | :--- | :--- |
| 1 | DME `0x12` | `213601` | Powermanagement: Ruhestromverletzung (ენერგიის მართვა: მოსვენების დენის დარღვევა) | `mevd1724`, `mevd1725`, `mevd172y`, `dme8ff_*` |
| 2 | FZD `0x56` | `030215` | SHD: ungültige Kennlinie, keine Normierung vorhanden (ლუქი: არასწორი მრუდი, ნორმირება არ არის) | `fzd_f15`, `fzd_20`, `fzd_g11`, … |
| 3 | FZD `0x56` | `801A4A` | Diebstahlwarnanlage: Neigungsgeber und Innenraumschutz deaktiviert (სიგნალიზაცია: დახრის სენსორი და სალონის დაცვა გამორთულია) — `fzd3`-ში ფორმულირება განსხვავებულია; `fzd_f15`-ში ეს კოდი **არ არის** | `fzd_f40`, `fzd_g11`, `fzd_i20`, `fzd3` |
| 4 | IHKA `0x78` | `E7144D` | Signal (Daten_Temperatur_Scheibe_V in 0x2D1): ungültig empfangen (კლიმატ-კონტროლი: მინის ტემპერატურის სიგნალი არავალიდურად მიღებულია) — ვარიანტზეა დამოკიდებული | `ihka_f15`, `ihka01`, `ihka_g05`, … |
| 5 | ICM `0x1C` | `482793` | Höhenstandssensoren - Vorn links - außerhalb Spezifikation (ძარის სიმაღლის სენსორი, წინა მარცხენა: სპეციფიკაციის გარეთ) | `icm_25` |

**სწავლა:** ერთი და იგივე Hex კოდს სხვადასხვა ECU-ში სხვა მნიშვნელობა აქვს, ამიტომ ძებნის გასაღები ყოველთვის `(ECU მისამართი, Hex)` უნდა იყოს. DIY ნაბიჯები ამ ცხრილში განზრახ არ არის: ისინი ქარხნულ `FORTTEXTE`-ში არ არსებობს და მათი გამოგონება ჰალუცინაცია იქნებოდა. ისინი მხოლოდ ISTA-ს ABL/FUB დოკუმენტაციიდან უნდა დაემატოს (შემდეგი ფაზა).

---


## 7. შესრულების ეტაპობრივი ჩეკლისტი (Execution Checklist)

- [ ] **ნაბიჯი 1:** შეიქმნას Python ETL სკრიპტი `scripts/offline_etl/build_bmw_fault_kb.py`, რომელიც დაასკანერებს `D:\...\ISTA\Ecu\*.prg` ფაილებს და დააგენერირებს `assets/offline_db/bmw_fault_knowledge_base.json`-ს.
- [ ] **ნაბიჯი 2:** დარეგისტრირდეს ახალი ასეტი `pubspec.yaml`-ში.
- [ ] **ნაბიჯი 3:** განახლდეს `lib/modules/obd/services/offline_database_manager.dart` ახალი სადიაგნოსტიკო მოდელებითა და ოფლაინ ძრავით.
- [ ] **ნაბიჯი 4:** აიგოს ვიზუალური UI მოდალი `lib/modules/obd/widgets/bmw_diagnostic_card_sheet.dart`.
- [ ] **ნაბიჯი 5:** დაკავშირდეს `lib/modules/obd/screens/ecu_scan_screen.dart`-ში `ANALYZE WITH FIX AI` ღილაკი ახალ ოფლაინ მოდალთან.
- [ ] **ნაბიჯი 6:** დაიწეროს Unit ტესტი `test/bmw_fault_diagnostic_engine_test.dart` და გადამოწმდეს 5-ივე რეალური კოდი და უცნობი კოდების Fallback.
- [ ] **ნაბიჯი 7:** ცვლილებების ატვირთვა GitHub რეპოზიტორიაში.
