import os
import glob
import json
import xml.etree.ElementTree as ET

def main():
    map_dir = r"D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES\BMW\ISPI\TRIC\ISTA\PSdZ\data\psdzdata\mapping"
    kis_json_path = r"assets/offline_db/kis_compatibility.json"
    
    xml_files = glob.glob(os.path.join(map_dir, "*.xml"))
    print(f"Found {len(xml_files)} mapping XML files")

    with open(kis_json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    zb_to_sgbm = {}
    total_mappings = 0

    for xf in xml_files:
        try:
            tree = ET.parse(xf)
            root = tree.getroot()
            for row in root.findall(".//row"):
                zbnr = row.findtext("zbnr", "").strip()
                diagad = row.findtext("diagad", "").strip()
                if not zbnr:
                    continue

                for child in row:
                    tag = child.tag
                    if tag.endswith("-sgbmid"):
                        pclass = child.findtext("processClass", "").strip()
                        sgbmid = child.findtext("id", "").strip()
                        if pclass and sgbmid:
                            if zbnr not in zb_to_sgbm:
                                zb_to_sgbm[zbnr] = {
                                    "diag_addr": diagad,
                                    "sgbm": {}
                                }
                            zb_to_sgbm[zbnr]["sgbm"][pclass] = sgbmid
                            total_mappings += 1
        except Exception as e:
            continue

    print(f"Parsed {len(zb_to_sgbm)} unique ZB numbers with {total_mappings} SGBM associations")
    data["zb_mappings"] = zb_to_sgbm
    data["metadata"]["total_zb_mappings"] = len(zb_to_sgbm)

    with open(kis_json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    size_mb = os.path.getsize(kis_json_path) / (1024 * 1024)
    print(f"Updated {kis_json_path} successfully ({size_mb:.2f} MB)")

if __name__ == "__main__":
    main()
