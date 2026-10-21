import os
import glob
import json
import xml.etree.ElementTree as ET

def parse_ecu_functions(ecu_functions_dir):
    xml_files = glob.glob(os.path.join(ecu_functions_dir, "*.xml"))
    print(f"Parsing {len(xml_files)} EcuFunctions XML files...")
    
    jobs = {}
    total_results = 0

    for xf in xml_files:
        try:
            tree = ET.parse(xf)
            root = tree.getroot()
            for job in root.findall(".//XEP_ECUJOBSEX"):
                job_id = job.findtext("Id", "").strip()
                job_name = job.findtext("Name", "").strip()
                job_func_name = job.findtext("FunctionNameJob", "").strip()
                
                results_list = []
                for res in job.findall(".//XEP_ECURESULTSEX"):
                    res_name = res.findtext("Name", "").strip()
                    title_en = res.findtext("Title_engb", "").strip() or res_name
                    title_de = res.findtext("Title_dede", "").strip()
                    fmt = res.findtext("Format", "").strip()
                    adapter_path = res.findtext("AdapterPath", "").strip()
                    
                    states = {}
                    for sv in res.findall(".//XEP_STATEVALUES"):
                        sval = sv.findtext("Statevalue", "").strip()
                        stitle = sv.findtext("Title_engb", "").strip() or sv.findtext("Title_dede", "").strip()
                        if sval:
                            states[sval] = stitle

                    results_list.append({
                        "name": res_name,
                        "title_en": title_en,
                        "title_de": title_de,
                        "format": fmt,
                        "adapter_path": adapter_path,
                        "states": states
                    })
                    total_results += 1

                if job_name and results_list:
                    jobs[job_name] = {
                        "job_id": job_id,
                        "func_name": job_func_name,
                        "results": results_list
                    }
        except Exception as e:
            continue

    print(f"Extracted {len(jobs)} ECU diagnostic jobs with {total_results} telemetry results.")
    return jobs

def extract_abl_retrofits(testmodule_dir):
    abl_files = glob.glob(os.path.join(testmodule_dir, "ABL_*.dll"))
    print(f"Scanning sample from {len(abl_files)} ISTA Testmodule DLLs...")
    
    retrofits = []
    # Scan up to 500 ABL DLLs for user strings containing Change_FA or faElements
    for dll_path in abl_files[:600]:
        try:
            with open(dll_path, "rb") as f:
                data = f.read()
            # Fast scan for UTF-16 strings in #US heap
            us_pos = data.find(b"faElementsToAdd")
            if us_pos != -1:
                dll_name = os.path.basename(dll_path)
                # Look for + or - codes near faElements
                window = data[max(0, us_pos - 100): min(len(data), us_pos + 400)]
                # extract printable ascii/utf16
                text = window.decode("latin-1", errors="ignore")
                fa_codes = []
                for word in text.split("\x00"):
                    w = word.strip("+ \t\r\n")
                    if len(w) >= 3 and len(w) <= 6 and w.isalnum() and word.startswith("+"):
                        fa_codes.append("+" + w)
                
                retrofits.append({
                    "module": dll_name.replace(".dll", ""),
                    "fa_elements": list(set(fa_codes))
                })
        except Exception:
            continue
            
    print(f"Found {len(retrofits)} service modules with FA / HO-Wort retrofit actions.")
    return retrofits

def get_standard_service_routines():
    return [
        {
            "id": "cbs_reset",
            "name": "CBS Condition Based Service Reset",
            "description": "Resets Engine Oil, Brake Pads, Brake Fluid, and Vehicle Inspection intervals",
            "ecu_target": "KOMBI / DME",
            "diag_address": "0x60",
            "routine_type": "standard_cbs",
            "items": ["Engine Oil", "Front Brake Pads", "Rear Brake Pads", "Brake Fluid", "Vehicle Check"],
            "uds_routine_id": "0x02B0",
            "safety_level": "safe"
        },
        {
            "id": "battery_register",
            "name": "Battery Registration & Capacity Encoding",
            "description": "Registers new 12V AGM/Lead-Acid battery in DME/DDE and updates power management histogram",
            "ecu_target": "DME / DDE",
            "diag_address": "0x12",
            "routine_type": "battery_histogram_reset",
            "supported_types": ["80Ah AGM", "90Ah AGM", "92Ah AGM", "95Ah AGM", "105Ah AGM", "80Ah Lead-Acid", "90Ah Lead-Acid"],
            "uds_job": "STEUERN_BATTERIETAUSCH_REGISTRIEREN",
            "safety_level": "safe"
        },
        {
            "id": "dpf_regeneration",
            "name": "DPF Diesel Particulate Filter Regeneration",
            "description": "Triggers forced exhaust particulate filter regeneration cycle during drive",
            "ecu_target": "DDE",
            "diag_address": "0x12",
            "routine_type": "exhaust_treatment",
            "preconditions": ["Coolant temp >= 75 C", "Exhaust temp >= 240 C", "Fuel level >= 10 Liters", "Vehicle speed > 60 km/h"],
            "uds_routine_id": "0x0340",
            "safety_level": "safe"
        },
        {
            "id": "egs_adaptations_reset",
            "name": "ZF 8HP Transmission Adaptations Reset",
            "description": "Clears clutch fill pressures and rapid filling times in EGS transmission control module",
            "ecu_target": "EGS",
            "diag_address": "0x18",
            "routine_type": "transmission_calibration",
            "preconditions": ["Engine OFF", "Ignition ON", "Transmission in P", "Transmission oil temp 30C - 60C"],
            "uds_routine_id": "0x0285",
            "safety_level": "moderate"
        },
        {
            "id": "vtg_oil_reset_calibration",
            "name": "xDrive Transfer Case (VTG) Oil Reset & Clutch Calibration",
            "description": "Resets oil wear index and executes mechanical clutch lock calibration cycle",
            "ecu_target": "VTG",
            "diag_address": "0x19",
            "routine_type": "all_wheel_drive_calibration",
            "preconditions": ["Vehicle stationary on level ground", "Parking brake engaged", "Ignition ON"],
            "uds_routine_id": "0x0290",
            "safety_level": "safe"
        },
        {
            "id": "valvetronic_learn",
            "name": "Valvetronic Mechanical Limit Positions Learn",
            "description": "Drives Valvetronic servomotor to minimum and maximum mechanical stops to calibrate eccentric shaft sensor",
            "ecu_target": "DME",
            "diag_address": "0x12",
            "routine_type": "engine_actuator_learn",
            "preconditions": ["Engine OFF", "Ignition ON", "Battery voltage >= 12.5V"],
            "uds_routine_id": "0x0295",
            "safety_level": "moderate"
        },
        {
            "id": "epb_workshop_mode",
            "name": "Electronic Parking Brake (EPB) Workshop Mode",
            "description": "Retracts rear brake calipers into service position for brake pad and rotor replacement",
            "ecu_target": "DSC / EMF",
            "diag_address": "0x29",
            "routine_type": "brake_service",
            "preconditions": ["Vehicle on lift or secure chocks", "Parking brake disengaged"],
            "uds_routine_id": "0x0310",
            "safety_level": "safe"
        },
        {
            "id": "steering_angle_calibration",
            "name": "Steering Angle Sensor (LWS/SAS) Zero-Point Calibration",
            "description": "Calibrates electronic power steering (EPS/ICM) straight-ahead zero position",
            "ecu_target": "ICM / EPS",
            "diag_address": "0x1C",
            "routine_type": "chassis_calibration",
            "preconditions": ["Steering wheel positioned straight ahead", "Wheels pointing forward", "Vehicle stationary"],
            "uds_routine_id": "0x02A0",
            "safety_level": "safe"
        },
        {
            "id": "brake_bleed_routine",
            "name": "DSC / ABS Hydraulic Brake Bleeding Routine",
            "description": "Activates ABS return pump and solenoid valves sequentially to expel trapped air from hydraulic unit",
            "ecu_target": "DSC",
            "diag_address": "0x29",
            "routine_type": "hydraulic_bleeding",
            "preconditions": ["Brake pressure bleeder connected at 2.0 bar", "Bleeder screw open on target caliper"],
            "uds_routine_id": "0x0320",
            "safety_level": "moderate"
        },
        {
            "id": "injector_coding",
            "name": "Diesel / Gasoline Injector Compensation (IMA/ISA) Coding",
            "description": "Reads and programs individual 6-7 digit cylinder injector tolerance calibration values",
            "ecu_target": "DME / DDE",
            "diag_address": "0x12",
            "routine_type": "fuel_system_calibration",
            "preconditions": ["Engine OFF", "Ignition ON"],
            "uds_did": "0xF120",
            "safety_level": "moderate"
        }
    ]

def main():
    ecu_functions_dir = r"D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\EcuFunctions"
    testmodule_dir = r"D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\Testmodule"
    output_path = r"assets/offline_db/ista_service_functions.json"

    ecu_jobs = parse_ecu_functions(ecu_functions_dir)
    retrofits = extract_abl_retrofits(testmodule_dir)
    standard_routines = get_standard_service_routines()

    payload = {
        "metadata": {
            "version": "1.0.0",
            "source": "BMW ISTA+ 4.59.30 EcuFunctions & Testmodule",
            "total_ecu_jobs": len(ecu_jobs),
            "total_service_routines": len(standard_routines),
            "total_retrofit_modules": len(retrofits)
        },
        "service_routines": standard_routines,
        "ecu_diagnostic_jobs": ecu_jobs,
        "sample_abl_retrofits": retrofits
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"Successfully generated {output_path} ({size_kb:.2f} KB)")

if __name__ == "__main__":
    main()
