import os
import glob
import json
import xml.etree.ElementTree as ET

def parse_mask(mask_str):
    if not mask_str:
        return 0xFF
    m = mask_str.strip()
    if m.endswith('b'):
        try:
            return int(m[:-1], 2)
        except ValueError:
            pass
    if m.startswith('0x'):
        try:
            return int(m, 16)
        except ValueError:
            pass
    try:
        return int(m, 16)
    except ValueError:
        return 0xFF

def main():
    fdl_dir = r"D:\D\bmw diagnostic\esys\esys\E-Sys\LauncherPRO-3.7.0 OEM-Coding - NoInstaller\LauncherPRO\FDLCodes"
    output_path = r"c:\Users\User\Desktop\ტესტ\fix-ai\assets\offline_db\fdl_cheat_codes.json"
    
    xml_files = sorted(glob.glob(os.path.join(fdl_dir, "*.xml")))
    print(f"Found {len(xml_files)} FDL cheat code files in {fdl_dir}")
    
    all_cheat_codes = []
    cafd_summary = {}
    total_functions_count = 0

    for xf in xml_files:
        filename = os.path.basename(xf)
        try:
            with open(xf, "r", encoding="utf-8-sig", errors="replace") as f:
                content = f.read()
            root = ET.fromstring(content)
        except Exception as e:
            print(f"Error parsing {filename}: {e}")
            continue

        file_codes_count = 0
        for cafd in root.findall(".//cafd"):
            cafd_id = cafd.attrib.get("id", "").strip().upper()
            cafd_name = cafd.attrib.get("name", "").strip()
            author = cafd.attrib.get("author", filename).strip()
            default_series = cafd.attrib.get("series", "").strip()

            if cafd_id not in cafd_summary:
                cafd_summary[cafd_id] = {
                    "names": set(),
                    "series": set(),
                    "code_count": 0
                }
            if cafd_name:
                cafd_summary[cafd_id]["names"].add(cafd_name)
            if default_series:
                cafd_summary[cafd_id]["series"].add(default_series)

            for code in cafd.findall(".//code"):
                desc = code.attrib.get("description", "").strip()
                code_series = code.attrib.get("series", default_series).strip()
                author_override = code.attrib.get("author", author).strip()

                groups_data = []
                for grp in code.findall(".//group"):
                    grp_id = grp.attrib.get("id", "").strip()
                    functions_data = []
                    for fn in grp.findall(".//function"):
                        start_str = fn.attrib.get("start", "0").strip()
                        end_str = fn.attrib.get("end", start_str).strip()
                        mask_raw = fn.attrib.get("mask", "").strip()
                        comment = fn.attrib.get("comment", "").strip()
                        val_str = (fn.text or "").strip()

                        try:
                            start_byte = int(start_str)
                        except ValueError:
                            start_byte = 0
                        try:
                            end_byte = int(end_str)
                        except ValueError:
                            end_byte = start_byte

                        mask_val = parse_mask(mask_raw)

                        functions_data.append({
                            "start": start_byte,
                            "end": end_byte,
                            "mask": mask_val,
                            "mask_raw": mask_raw,
                            "param_name": comment or "PARAM",
                            "target_value": val_str
                        })
                        total_functions_count += 1

                    if functions_data:
                        groups_data.append({
                            "group_id": grp_id,
                            "functions": functions_data
                        })

                if groups_data:
                    file_codes_count += 1
                    cafd_summary[cafd_id]["code_count"] += 1
                    all_cheat_codes.append({
                        "cafd_id": cafd_id,
                        "cafd_name": cafd_name,
                        "description": desc,
                        "series": code_series,
                        "author": author_override,
                        "source_file": filename,
                        "groups": groups_data
                    })

        print(f"  {filename:25s}: {file_codes_count:4d} cheat codes extracted")

    serializable_summary = {
        cid: {
            "names": list(data["names"]),
            "series": list(data["series"]),
            "code_count": data["code_count"]
        } for cid, data in cafd_summary.items()
    }

    payload = {
        "metadata": {
            "version": "1.0.0",
            "source": "E-Sys LauncherPRO 3.7.0 FDLCodes",
            "total_codes": len(all_cheat_codes),
            "total_functions": total_functions_count,
            "unique_cafds": len(cafd_summary)
        },
        "cafd_summary": serializable_summary,
        "codes": all_cheat_codes
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as out:
        json.dump(payload, out, indent=2, ensure_ascii=False)

    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"\nSuccessfully wrote {len(all_cheat_codes)} codes ({size_mb:.2f} MB)")
    print(f"Covering {len(cafd_summary)} unique CAFD storage entities and {total_functions_count} function modifications.")

if __name__ == "__main__":
    main()
