# FIX AI — 100% OFFLINE ISTA+ 4.59.30, PSdZData 4.59.30 Full & E-Sys LauncherPRO 3.7.0 ინტეგრაციის მასტერ-პრომპტი და გეგმა

> **დანიშნულება:** ეს ფაილი არის სრული, თვითკმარი სამოქმედო გეგმა და დეტალური პრომპტი (Master Implementation Prompt). როდესაც დაგვჭირდება `D:` დისკზე არსებული **E-Sys LauncherPRO**, **PSdZData 4.59.30 Full** და **BMW ISTA+ 4.59.30** ბაზების სრულად ოფლაინ (100% Offline) რეჟიმში ამოღება და `FIX AI` APK-ში ჩაშენება, მიუთითე აგენტს:
> **„იხელმძღვანელე `OFFLINE_ISTA_PSDZ_INTEGRATION_PROMPT.md` ფაილით და შეასრულე [ფაზა X / სრული გეგმა]“**.

---

## 1. არქიტექტურული მიზანი (100% Offline Vision)

`FIX AI` უნდა მუშაობდეს **100%-ით ოფლაინ რეჟიმში (ინტერნეტისა და გარე სერვერების გარეშე)** და ჰქონდეს:
1. **სრული FDL & FA/VO კოდირება (BimmerCode + E-Sys LauncherPRO დონე):**
   - 2,561 გამზადებული One-Click FDL Cheat Code (`FDLCodes/*.xml`).
   - სრული Expert Mode — ყველა CAFD პარამეტრის რეალური სახელებით (`CafData.dat` + `PSdZdata.dat` + `7,154 CAFD` ფაილი), ბაიტის ოფსეტებით (`start`/`end`), ბიტ-მასკებით (`mask`) და მნიშვნელობებით.
2. **სრული SVT / I-Step / SGBM თავსებადობისა და TAL კალკულაცია (E-Sys KIS დონე):**
   - მანქანიდან წაკითხული SVT-ის (`0xF101`) და FA/VO-ს შედარება ქარხნულ **KIS (Kompatibilitäts- und Informations-System)** ბაზასთან.
   - 24-ვე SGBM Process Class-ის (`HWEL`, `BTLD`, `SWFL`, `CAFD`, `FLSL`, `FAFP`, `IBAD`, `NAVD`, `ENTD` და სხვ.) იდენტიფიკაცია და ზუსტი განსაზღვრა, რომელი ბლოკი რომელ I-Level-ზეა და რომელი განახლება ან CAFD ეკუთვნის.
3. **ქარხნული დიაგნოსტიკა, Live Data და სერვის-ფუნქციები (ISTA+ 4.59.30 დონე):**
   - ISTA-ს `EcuFunctions/*.xml`, `Ecu/*.prg` და `Testmodule/ABL_*.dll` (23,070 სერვის-მოდული) ბაზებიდან ამოღებული UDS DID-ები, სტატუსები, ადაპტაციები, კალიბრაციები და რეტროფიტების (`Change_FA` / HO-Wort) პროცედურები.
   - ISTA-ს SQLite ბაზებიდან (`xmlvalueprimitive_OTHER.sqlite`, `xmlvalueprimitive_ENGB.sqlite`, `IdesModule.sqlite`) ამოღებული ქარხნული DTC შეცდომის კოდების აღწერები და ტესტ-გეგმები.
4. **ოფლაინ ECU Flashing (PSdZData Full):**
   - ტელეფონის მეხსიერებაში (`/Download/FIX_AI_PSDZ/` ან აპლიკაციის ოფლაინ კონტეინერში) შენახული კონკრეტული ძარის (მაგ. `F025` — X3 F25 / X4 F26 / X5 F15 / X6 F16) `SWFL`, `BTLD`, `FLSL` ფაილებით ბლოკების 100% ოფლაინ განახლება.

---

## 2. წყარო ფაილების ზუსტი მდებარეობა და REA ანალიზის მონაცემები

აგენტმა მონაცემების ამოღებისას უნდა გამოიყენოს შემდეგი დადასტურებული მისამართები და სტრუქტურები:

### 2.1. E-Sys / LauncherPRO 3.7.0
- **საქაღალდე:** `D:\D\bmw diagnostic\esys\esys\E-Sys\LauncherPRO-3.7.0 OEM-Coding - NoInstaller\LauncherPRO\`
- **მთავარი ფაილები:**
  - `PSdZHandler.dll` (SHA-256: `cff5e1a76c50a81535a21b442845c18f02e61cdd058c2ff14fdfc7b9eb472dbd`, REA Evidence: `ev_a81dc9300d128ee650dc01452051c41f052d67a1791bb13b42450c1c6670108f`)
    - შეიცავს კლასებს: `LauncherPRO.PSdZHandler.Mapper` (`Initilize(string, string)`), `LauncherPRO.PSdZHandler.MapperManager`, `PSdZHandler.DataMapper.ProcessClass` (24 SGBM კლასი), `PSdZHandler.DataMapper.UnitSize`.
  - `PSdZAPI.dll` (REA Evidence: `ev_9de24023c2d3b9bb99472cc260ff4cbdf0304a4faaf4628571244efc146e688e`) — C++/CLI ხიდი (`PSdZAPI.Mapper`, `PSdZAPI.APIMapper`).
  - `CafData.dat` (**76.49 MB**) და `PSdZdata.dat` (**47.83 MB**) — შეკუმშული/დაშიფრული BSON/XML CAFD Untrimmer ლექსიკონი.
  - `FDLCodes\*.xml` (**15 XML ფაილი, 2,561 FDL Cheat Code, 61 CAFD Storage Group**):
    - `Bundang_Thunder.xml` (1,150 კოდი), `ekfxisid.xml` (437 კოდი), `Almaretto.xml` (392 კოდი), `Botho.xml` (175 კოდი), `otakar.xml` (149 კოდი), `ruben_17non.xml` (90 კოდი), `FDLCodes.xml` (81 კოდი), `packetpilot.xml` (46 კოდი), `SergAA.xml` (19 კოდი), `dimon003.xml` (9 კოდი), `Originals.xml` (6 კოდი), `Coolala.xml` (3 კოდი), `Elder.xml` (2 კოდი), `Justas.xml` (1 კოდი), `stf_1970.xml` (1 კოდი).
    - XML სტრუქტურა:
      ```xml
      <FDL>
        <cafd id="000017BE" name="BDC_01" author="Almaretto" series="F015">
          <code description="ENABLE Electronic (Radio and Nav) SHUTOFF when drivers door opened">
            <group id="3020">
              <function start="9" end="9" comment="TCM_LOGIC_R_OFF_DOOR" mask="00000001b">aktiv</function>
            </group>
          </code>
        </cafd>
      </FDL>
      ```

### 2.2. BMW ISTA+ 4.59.30
- **საქაღალდე:** `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\`
- **მთავარი .NET ბიბლიოთეკები (`TesterGui\bin\Release\`):**
  - `RheingoldProgramming.dll` (REA Evidence: `ev_c0cfa49e69b6bbc612d55875f83c00178d064fc2fd384abd03c333e6484c8b16` — 852 კლასი, 5,783 მეთოდი: `PsdzObjectBuilder`, `ProgrammingApi`, `CoapiProg`, `ECUProg`, `TalLineHelper`, `SweParallelDownloader`).
  - `RheingoldPsdzWebApi.Adapter.Contracts.dll` (REA Evidence: `ev_9ac543fb0a8635e1744d2d1667447a4a30a900db44ff5b537e35b9fd0ad342a6` — 712 კლასი, 4,226 მეთოდი: `CalculatedNcdsEtoModel`, `Coding1NcdEntryModel`, `BuildTalFromXmlRequestModel`, `EcuSecCheckingResponseEtoModel`).
  - `RheingoldInfoProvider.dll` (REA Evidence: `ev_294e55e39e203e777eec68a640a86a84bbe289be88dc005da60806aeb2f5511c` — 898 კლასი, 6,421 მეთოდი: `SWTProcessorImpl`, `SdpPatchProcessor`).
  - `RheingoldVehicleCommunication.dll` (REA Evidence: `ev_d911b97bfe31ac7996c65e237a3116bd2d25da3541a8edd6a0e6e5d53c870953` — `ECUJob`, `ECUKom`, `ECUResult`).
  - `DiagnosticsBusinessData.dll` (REA Evidence: `ev_e6d64aa0439941f57f5c0e5d7dfb212b8b2b9ce5ef901fdcfbf7aee97467b12c` — `SecuredVehicleValidator`, `JobDefinition`).
- **სერვის-მოდულები (`Testmodule\*.dll`):**
  - **23,070 `.dll` ფაილი** (1,450.68 MB). მაგ. `ABL_AUS_ACTIVATE_HAPTICSTEERINGFEEDBACK.dll` (REA Evidence: `ev_845be7e0c76d92aa8ad0cf6306c5ca5f8b14f6bee66e68b23ad9bf6edf4f4c74`).
  - თითოეული მემკვიდრეობით იღებს `BMW.Rheingold.Module.ISTA.ISTAModule`-ს და შეიცავს მეთოდებს `run()`, `Prepare()`, `Start()`, `Reset()`, `Change_FA()` და `#US` სტრიქონებში ინახავს Ediabas Job-ებსა და FA/HO-Wort კოდებს.
- **ECU აღწერები და ფუნქციები:**
  - `EcuFunctions\*.xml` (**26 XML ფაილი, 0.51 MB**) — `ArrayOfXEP_ECUJOBSEX` / `XEP_ECURESULTSEX` / `XEP_STATEVALUES` (სენსორების, სტატუსებისა და მნიშვნელობების თარგმანები).
  - `Ecu\*.prg` & `*.grp` (**1,420 `.prg` + 429 `.grp` ფაილი, 1,675.52 MB**) — Ediabas SGBD ბინარული ბაზები.
  - `KMMdaten\**\*.txt` (**141 ფაილი, 33.72 MB**) — E-სერიის კოდირებისა და ლოგისტიკის ცხრილები (`kmm_SG.txt`, `kmm_CODING.txt`, `kmm_LOGISTIK.txt`, `kmm_ATSH.txt`).
- **SQLite მონაცემთა ბაზები (`SQLiteDBs\` — 76 ფაილი):**
  - დაუშიფრავი (`PlainSQLite=True`) ბაზები:
    - `streamdataprimitive_ENGB.sqlite` (REA Evidence: `ev_37e58a32d9729f1a58bfea4df966508157d9053d6b52c6740eafbe603392eb52`)
    - `xmlvalueprimitive_OTHER.sqlite` (**573.06 MB** — FTS5 ცხრილი `xmlvalueprimitive`, **55,035 ჩანაწერი**)
    - `xmlvalueprimitive_ENGB.sqlite` (**2,047.96 MB** + `.sqlite_xzw_*` ჩანკები)
    - `IdesModule.sqlite` (**477.84 MB**)

### 2.3. PSdZData 4.59.30 (ISTA PSdZ + Full 7z არქივი)
- **ISTA PSdZ საქაღალდე:** `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\PSdZ\data\psdzdata\` (**8,969.03 MB**)
  - `swe\cafd\` — **7,154 CAFD ფაილი** (**525.77 MB**).
  - `kiswb\` — **21 მთავარი სერია** (`F001`, `F010`, `F020`, `F025`, `F056`, `G045`, `G070`, `I001` და სხვ.).
    - თითოეულ სერიაში დევს HSQLDB ბაზა: `KIS.script` (SQL სქემა და ინდექსები) + `KIS.data` (მონაცემები).
    - მაგ. `kiswb\F025\` (მოიცავს **F25 X3, F26 X4, F15 X5, F16 X6, F85 X5M, F86 X6M**, ზომა **238.29 MB**):
      - `KIS.EBR`: 6 ძარა
      - `KIS.FAHRZEUGTYP`: 220 ტიპ-კოდი
      - `KIS.BORDNETZTEILNEHMER`: 128 ECU ბლოკი (`NAME`, `DIAGNOSEADRESSE`, `BESCHREIBUNG`)
      - `KIS.ISTUFE`: 180 I-Level (`F025-xx-xx-xxx`)
      - `KIS.SALAPA`: 2,098 SA/FA ოფციის კოდი
      - `KIS.EINSATZBEDINGUNG`: 4,460 ლოგიკური წესი
      - `KIS.LOGISTISCHESTEIL`: 9,556 ნაწილის ნომერი (`SACHNR`)
      - `KIS.TECHNISCHEEINHEIT`: 10,943 SGBM ერთეული (`SGBMID`, `SGBM_NR`, `MAJOR`, `MINOR`, `PATCH`, `FLASHBAR`, `BESCHREIBUNG`)
      - `KIS.CAFMAPPING`: 89,040 კავშირი
  - `mapping\*.xml` — **96 XML ფაილი** (`*_BTLD.xml`, `*_CAFD.xml`, `*_HWEL.xml`, `*_TYPNR.xml`).
  - `security\` — **14 ფაილი** (`sec_auth_l3.xml`, `sec_auth_l4.xml`, `sec_certificates.pem`, `sec_keyreference.xml`, `sec_ncdkeys.xml`).
- **Full არქივი:** `D:\D\PSdZData 4.59.30 Full.7z` (**118.5 GB**) — დამატებით შეიცავს `swe\swfl\`, `swe\btld\`, `swe\flsl\`, `swe\ibad\`, `swe\navd\`, `swe\entd\`.

---

## 3. ორ-დონიანი 100% ოფლაინ არქიტექტურა Android APK-სთვის

იმისათვის, რომ აპლიკაცია იყოს სწრაფი, არ გაჭედოს Android-ის ოპერატიული მეხსიერება (RAM) და იმუშაოს **100% ოფლაინ რეჟიმში**, მონაცემები იყოფა 2 ოფლაინ შრედ:

### შრე 1: Embedded Core Offline DB (პირდაპირ APK-ში ჩაშენებული — `public/offline-db/`, ~25–40 MB)
ინსტალაციისთანავე მოჰყვება APK-ს და მუშაობს ყოველგვარი დამატებითი ფაილების გარეშე:
1. **`fdl_cheat_codes.json` (~380 KB):**
   - LauncherPRO-ს 15 XML ფაილიდან ამოღებული **2,561 FDL Cheat Code** ყველა F/G სერიისთვის.
2. **`kis_catalog_core.db` / JSON (~12 MB შეკუმშული):**
   - 21-ვე `kiswb` სერიიდან ამოღებული:
     - `BORDNETZTEILNEHMER` (ყველა ECU-ს სახელი, UDS დიაგნოსტიკური მისამართი `0x00..0xFF`, აღწერა).
     - `ISTUFE` (ყველა I-Step ვერსია და გამოშვების თარიღი).
     - `SALAPA` (ყველა SA/FA ოფციის კოდი).
     - `TECHNISCHEEINHEIT` (ყველა `SWFL`, `BTLD`, `CAFD`, `HWEL`, `FLSL` SGBM ID, ვერსია და აღწერა).
     - `mapping/*.xml` (ZB-ნომრებისა და SGBM ID-ების კავშირი).
3. **`cafd_f_g_popular.db` (~10 MB შეკუმშული):**
   - ყველაზე ხშირად კოდირებადი 25 ბლოკის (`BDC_BODY`, `FEM_BODY`, `REM`, `CAS`, `FRM`, `HU_NBT`, `HU_NBT2`, `HU_MGU`, `KOMBI`, `IHKA`, `HKFM`, `ICM`, `PMA`, `DSC`, `EGS`, `ASD`, `KAFAS`, `TRSVC`, `ACSM`, `FLA`, `SZL`, `FZD`, `LMV`, `VDM`, `AMP`) სრული დეკოდირებული CAFD პარამეტრების ლექსიკონი (`CafData.dat`-იდან).
4. **`ista_ecu_functions_and_abl.json` (~4 MB შეკუმშული):**
   - `EcuFunctions/*.xml`-ის ყველა სენსორი და სტატუსი + `Testmodule/ABL_*.dll`-ებიდან ამოღებული სერვის-ფუნქციები (DPF რეგენერაცია, CBS Reset, Battery Registration, EGS Adaptation Reset, VTG Calibration, Valvetronic Limit Learn, Injector Coding, Steering Angle Calibration, EPB Workshop Mode, Bleed Brakes და რეტროფიტების FA კოდები).

### შრე 2: Full Offline Expansion Pack (ტელეფონის მეხსიერებაში `/Download/FIX_AI_OFFLINE/` — 100% Offline Expert & Flash Pack)
მომხმარებელს შეუძლია კომპიუტერიდან USB კაბელით პირდაპირ ტელეფონში ჩააგდოს გენერირებული ოფლაინ პაკეტები:
1. **`fixai_cafd_complete.pack` (~75 MB):**
   - უკლებლივ ყველა **7,154 CAFD ფაილის** სრული Untrimmed დეფინიცია (`CafData.dat` + `swe/cafd`).
2. **`fixai_flash_<MAIN_SERIES>.pack` (მაგ. `fixai_flash_F025.pack` — X3 F25 / X4 F26-ისთვის, ~400–800 MB):**
   - კონკრეტული ძარის უახლესი I-Step-ის (`F025_26_03_550`) ყველა `SWFL`, `BTLD`, `FLSL` და `CAFD` ბინარული კონტეინერი, რაც საშუალებას იძლევა ტელეფონიდანვე, **100% ოფლაინ რეჟიმში** ჩატარდეს ნებისმიერი ბლოკის ქარხნული პროგრამირება (Flashing)!

---

## 4. ეტაპობრივი შესრულების ინსტრუქცია აგენტისთვის (Execution Phases)

როდესაც მომხმარებელი გთხოვს ამ გეგმის შესრულებას, მიჰყევი ქვემოთ მოცემულ 4 ფაზას ზუსტი თანმიმდევრობით:

---

### ფაზა 1: Offline ETL პარსერების შექმნა და მონაცემების ამოღება (`scripts/offline_etl/`)

შექმენი დირექტორია `c:\Users\User\Desktop\ტესტ\fix-ai\scripts\offline_etl\` და დაწერე შემდეგი სკრიპტები:

#### ნაბიჯი 1.1: `extract_fdl_cheat_codes.py`
- წაიკითხე ყველა 15 XML ფაილი საქაღალდიდან:
  `D:\D\bmw diagnostic\esys\esys\E-Sys\LauncherPRO-3.7.0 OEM-Coding - NoInstaller\LauncherPRO\FDLCodes\*.xml`
- გაითვალისწინე UTF-8 BOM (`encoding="utf-8-sig"`).
- ამოიღე ყველა `<cafd>` ტეგი (`id`, `name`, `author`, `series`) და მის შიგნით არსებული `<code>` (`description`, `series`), `<group>` (`id`) და `<function>` (`start`, `end`, `mask`, `comment` და ტექსტური მნიშვნელობა).
- გააერთიანე დუბლიკატები და შეინახე სტრუქტურირებულ ფაილში:
  `c:\Users\User\Desktop\ტესტ\fix-ai\src\services\bmw\data\fdlCheatCodesOffline.json`

#### ნაბიჯი 1.2: `extract_kis_and_mappings.py`
- გადაუარე `D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\PSdZ\data\psdzdata\kiswb\*` საქაღალდეებს (`F001`, `F010`, `F020`, `F025`, `F056`, `G045`, `G070`, `I001` და სხვ.).
- გამოიყენე Java HSQLDB (`extLibs\kis.jar` ან HSQLDB JDBC / Python პარსერი) ან პირდაპირ წაიკითხე `KIS.script` / `KIS.data` და ამოიღე:
  - ძარები (`KIS.EBR`, `KIS.FAHRZEUGTYP`)
  - ECU ბლოკები და მისამართები (`KIS.BORDNETZTEILNEHMER`)
  - I-Step ვერსიები (`KIS.ISTUFE`)
  - SA/FA კოდები (`KIS.SALAPA`)
  - SGBM ერთეულები (`KIS.TECHNISCHEEINHEIT` — `SGBMID`, `SGBM_NR`, `MAJOR`, `MINOR`, `PATCH`, `BESCHREIBUNG`)
- ასევე წაიკითხე `PSdZ\data\psdzdata\mapping\*.xml` (96 ფაილი) და `KMMdaten\**\*.txt`.
- შეინახე შედეგი:
  `c:\Users\User\Desktop\ტესტ\fix-ai\src\services\bmw\data\kisCompatibilityOffline.json`

#### ნაბიჯი 1.3: `CafDataExtractor` (.NET Console Utility `CafData.dat`-ისა და `PSdZdata.dat`-ის გასახსნელად)
- რადგან `CafData.dat` (76.49 MB) და `PSdZdata.dat` (47.83 MB) იყენებს `LauncherPRO`-ს `PSdZHandler.dll`-ში ჩაშენებულ `TokenMaster.CryptLibV3` და `SharpZipLib` ლოგიკას, არ იწვალო ხელით კრიპტოგრაფიის გადაწერაზე:
  - შექმენი პატარა C# (.NET Framework 4.8) კონსოლური პროექტი `scripts/offline_etl/CafDataDumper/`, რომელიც პირდაპირ დაარეფერენსებს:
    - `PSdZHandler.dll`
    - `ICSharpCode.SharpZipLib.dll`
    - `Newtonsoft.Json.dll`
  - გამოიძახე `LauncherPRO.PSdZHandler.MapperManager` / `Mapper.Initilize(cafDataPath, psdzDataPath)` და პირდაპირ დააექსპორტე გაშიფრული CAFD Storage Group-ები, ფუნქციის სახელები, კომენტარები და ერთეულები JSON/SQLite ფორმატში!
  - დააწყვილე ეს მონაცემები `PSdZ\data\psdzdata\swe\cafd\cafd_*.caf.*` ფაილების ბაიტის ოფსეტებთან და ბიტ-მასკებთან.
  - შექმენი:
    1. `src/services/bmw/data/cafdCoreDefinitions.json` (F/G სერიის 25 მთავარი ბლოკისთვის — APK-ში ჩასაშენებლად).
    2. `public/offline-packs/fixai_cafd_complete.pack` (7,154-ვე CAFD-ისთვის).

#### ნაბიჯი 1.4: `extract_ista_functions_and_abl.py`
- წაიკითხე `EcuFunctions\*.xml` (26 ფაილი) და ამოიღე ყველა `XEP_ECUJOBSEX` (`Name`, `FunctionNameJob`, `Results` -> `XEP_ECURESULTSEX` -> `Name`, `Title_engb`, `Title_dede`, `Format`, `StateValues`).
- გადაუარე `Testmodule\ABL_*.dll` ფაილებს Python-ით (`dnfile` / `pefile` ან `.NET Reflection` სკრიპტით) და ამოიღე:
  - მოდულის სახელი და კატეგორია (`ABL_DIT_*`, `ABL_AUS_*`, `ABL_GEN_*`)
  - `#US` (User Strings) ცხრილში არსებული Ediabas Job-ები (მაგ. `STEUERN_ROUTINE`, `STATUS_LESEN`, `FS_LOESCHEN`), პარამეტრები და `Change_FA` (`faElementsToAdd`, `faElementsToRem`) კოდები.
- წაიკითხე `xmlvalueprimitive_OTHER.sqlite` და `IdesModule.sqlite` (`sqlite3` read-only რეჟიმით) სტანდარტული BMW DTC და ტექსტური პრიმიტივების ამოსაღებად.
- შეინახე შედეგი:
  `c:\Users\User\Desktop\ტესტ\fix-ai\src\services\bmw\data\istaServiceFunctionsOffline.json`

---

### ფაზა 2: `FIX AI` სერვისების განახლება 100% ოფლაინ მუშაობისთვის (`src/services/bmw/`)

განაახლე და დააკავშირე ამოღებული ოფლაინ ბაზები აპლიკაციის არსებულ ძრავებთან:

1. **`src/services/bmw/OfflineDatabaseManager.ts` (ახალი სერვისი):**
   - მართავს როგორც APK-ში ჩაშენებულ (`Embedded Core Offline DB`), ისე ტელეფონის მეხსიერებაში არსებულ (`Full Offline Expansion Pack`) ფაილებს.
   - უზრუნველყოფს მყისიერ ძებნას:
     - `getFdlCheatCodes(series?: string, ecuName?: string, cafdId?: string)`
     - `getCafdDefinition(cafdId: string, major?: number, minor?: number, patch?: number)`
     - `resolveSgbmId(processClass: string, idHex: string, major: number, minor: number, patch: number)`
     - `calculateTargetSvtFromKis(mainSeries: string, currentSvt: any, targetILevel?: string)`
     - `getIstaServiceRoutine(routineId: string)`

2. **`src/services/bmw/CodingEngine.ts`:**
   - ჩაანაცვლე შეზღუდული ხელით გაწერილი Cheat Codes სია სრული **2,561 FDL Cheat Code** ბაზით (`fdlCheatCodesOffline.json`) და `cafdCoreDefinitions.json`-ით.
   - როდესაც მანქანიდან იკითხება CAFD Coding Data (`ReadDataByIdentifier 0x0CF0..0x0CFF` ან `0x3000..0x3FFF`), `CodingEngine`:
     - პოულობს შესაბამის `cafd id`-ს (მაგ. `000017BE` `BDC_01`-ისთვის ან `00000794` `FRM`-ისთვის).
     - კითხულობს რეალურ ბაიტს (`start`..`end`), ადებს `mask`-ს (მაგ. `00000001b`) და UI-ში აჩვენებს ზუსტ მიმდინარე სტატუსს (`aktiv` / `nicht_aktiv`).
     - შეცვლის წინ სავალდებულოდ ინახავს ორიგინალ `.ncd` ბექაფს ტელეფონის ოფლაინ მეხსიერებაში (`localStorage` + ფაილური სისტემა).

3. **`src/services/bmw/PsdzContainerParser.ts` & `TalExecutionEngine.ts`:**
   - დაამატე 24-ვე SGBM Process Class-ის მხარდაჭერა (`PC_HWEL`, `PC_BTLD`, `PC_SWFL`, `PC_CAFD`, `PC_FLSL`, `PC_FAFP` და ა.შ. `PSdZHandler.DataMapper.ProcessClass`-ის მიხედვით).
   - დააკავშირე `kisCompatibilityOffline.json`-თან, რათა SVT-ის წაკითხვის შემდეგ აპლიკაციამ ზუსტად დაწეროს:
     - თითოეული ბლოკის ქარხნული სახელი და აღწერა (`BORDNETZTEILNEHMER`).
     - მიმდინარე და სამიზნე I-Step (`ISTUFE`).
     - თავსებადი `CAFD` და `SWFL` ვერსიები.

4. **`src/services/bmw/BmwDiagnosticService.ts`:**
   - დააკავშირე `istaServiceFunctionsOffline.json`-თან, რათა Live Data სენსორებსა და სერვის-ფუნქციებს ჰქონდეთ ISTA-ს ქარხნული სახელები, სტატუსის მნიშვნელობები (`XEP_STATEVALUES`) და შესრულების ეტაპები (`Prepare` -> `Start` -> `Reset`).

---

### ფაზა 3: UI / UX განახლება 100% ოფლაინ რეჟიმისთვის

1. **Offline Database Status & Pack Manager გვერდი/პანელი:**
   - აჩვენებს ჩაშენებული ოფლაინ ბაზის სტატუსს:
     - `FDL Cheat Codes: 2,561 კოდი (Offline Ready)`
     - `KIS SGBM & I-Step DB: 21 სერია (Offline Ready)`
     - `ISTA Service Modules & ECU Functions: Offline Ready`
   - აქვს ღილაკი **„Import Full PSdZ / CAFD Offline Pack“**, საიდანაც მომხმარებელს შეუძლია აირჩიოს ტელეფონში ჩაგდებული `.pack` / `.zip` ფაილი (მაგ. `F025` სრული ფლეშ-პაკეტი).
2. **Coding & Expert Mode ეკრანი:**
   - ფილტრაცია ძარის (`F025/F26`, `F010`, `F020`, `G020` და ა.შ.), ბლოკის (`BDC_01`, `HU_NBT`, `KOMBI`, `CAS`, `HKFM`) და ფუნქციის სახელის მიხედვით.
   - თითოეულ კოდირებაზე ჩანს როგორც გასაგები აღწერა (*„კარის გაღებისას რადიოს/ნავიგაციის გათიშვა“*), ისე ტექნიკური დეტალები (`CAFD 000017BE | Group 3020 | Byte 9 | Mask 00000001b | TCM_LOGIC_R_OFF_DOOR`).
   - ღილაკი **„Backup Original NCD“** და **„Restore Original NCD“** ერთი დაჭერით.

---

### ფაზა 4: უსაფრთხოების პროტოკოლი და APK-ს აწყობა (Safety & Build Verification)

1. **უსაფრთხოების გარანტიები რეალურ მანქანაზე (მათ შორის BMW X4 F26-ზე):**
   - **Read-Only Default:** ნებისმიერი სკანირება, SVT წაკითხვა, I-Step შედარება, შეცდომების წაკითხვა და Live Data იყენებს მხოლოდ უსაფრთხო კითხვის სერვისებს (`0x22`, `0x19`).
   - **Voltage Guard:** კოდირების (`0x2E`) ან ფლეშირების (`0x34`/`0x36`) დაწყებამდე სავალდებულოდ მოწმდება ძაბვა ($\ge 12.5\text{V}$ კოდირებისთვის, $\ge 13.0\text{V}$ ფლეშირებისთვის).
   - **Bitmask Isolation:** FDL კოდირებისას იცვლება მხოლოდ კონკრეტული `mask`-ის ბიტები (`(origByte & ~mask) | (newVal & mask)`), ხოლო ბაიტის დანარჩენი ბიტები ხელუხლებელი რჩება!
   - **Mandatory NCD Backup:** ჩაწერამდე მანქანიდან წაკითხული ორიგინალი ბაიტები ინახება უცვლელად SHA-256 ჰეშით.
2. **ტესტირება და APK Build:**
   - გაუშვი `npm run build` და შეამოწმე TypeScript ტიპები და ბანდლის ზომა.
   - გაუშვი `npx cap sync android` და ააწყვე APK (`gradlew assembleDebug` / `assembleRelease`).
   - შეამოწმე, რომ APK იხსნება მყისიერად (Cold Start < 2 წმ) და ყველა ოფლაინ ბაზა იტვირთება შეფერხების გარეშე.

---

## 5. სწრაფი ბრძანებები (როგორ გავუშვათ ეს პრომპტი მომავალში)

როდესაც მზად იქნები განხორციელებისთვის, უბრალოდ მომწერე ერთ-ერთი:
- **„დაიწყე `OFFLINE_ISTA_PSDZ_INTEGRATION_PROMPT.md`-ის ფაზა 1“** — ამოიღებს მონაცემებს `D:` დისკიდან და შექმნის ოფლაინ ბაზებს.
- **„შეასრულე `OFFLINE_ISTA_PSDZ_INTEGRATION_PROMPT.md` სრულად და ააწყვე ახალი APK“** — შეასრულებს ოთხივე ფაზას თავიდან ბოლომდე და დააგენერირებს მზა ოფლაინ APK-ს.
