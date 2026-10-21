"""Build assets/offline_db/bmw_fault_knowledge_base.json from REAL factory data.

Sources (nothing is invented):
  * ISTA Ecu/*.prg   -> table FORTTEXTE  (ORT = DTC hex, ORTTEXT = official factory text)
  * KIS database     -> assets/offline_db/kis_compatibility.json (ECU name <-> diag address)

Output layout (compact, de-duplicated):
{
  "metadata": {...},
  "texts":   ["official text 0", ...],                      # unique strings
  "families": { "fzd": { "addresses": ["0x56"],
                         "variants": ["fzd_f15", ...],
                         "codes": { "030215": [[textIdx, [variantIdx,...]], ...] } } },
  "address_index": { "0x56": ["fzd"] }
}
A DTC's text may differ between SGBD variants (different chassis generations);
all distinct texts are kept together with the variants they came from, so the app
never has to pick/guess silently.
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prg_reader import PrgFile  # noqa: E402

ECU_DIR = (r"D:\D\BMW ISTA+ 4.59.30 Standalone-SetupFiles\BMW_Group_ISTA-FILES"
           r"\BMW\ISPI\TRIC\ISTA\Ecu")
KIS_JSON = os.path.join("assets", "offline_db", "kis_compatibility.json")
OUT_JSON = os.path.join("assets", "offline_db", "bmw_fault_knowledge_base.json")

# SGBD file stems whose family cannot be derived from a KIS ECU base name.
# These are only prefix aliases (SGBD name prefix -> KIS ECU base name); they do not
# add any diagnostic content.
SGBD_PREFIX_ALIASES = {
    "mevd": "dme", "msd": "dme", "msv": "dme", "dme": "dme", "mevd1": "dme",
    "mevd17": "dme", "bdc": "bdc", "fem": "fem",
}

DTC_RE = re.compile(r"^0x([0-9A-Fa-f]{2,8})$")


def load_kis_bases():
    kis = json.load(open(KIS_JSON, encoding="utf-8"))
    bases = {}
    for s in kis["series"].values():
        for e in s["ecus"]:
            base = e["name"].split("-")[-1].lower()
            bases.setdefault(base, set()).add(e["diag_addr_hex"].lower().replace("0x", "0x").lower())
    return {k: sorted(v) for k, v in bases.items()}


def family_of(stem: str, bases: dict):
    s = stem.lower()
    best = None
    for b in bases:
        if s == b or s.startswith(b) and (len(s) == len(b) or not s[len(b)].isalpha()):
            if best is None or len(b) > len(best):
                best = b
    if best:
        return best
    for pre, alias in SGBD_PREFIX_ALIASES.items():
        if s.startswith(pre):
            return alias if alias in bases else None
    return None


def main():
    bases = load_kis_bases()
    texts, text_idx = [], {}
    families = {}
    skipped, unmatched, failed = 0, [], []

    def tidx(t):
        i = text_idx.get(t)
        if i is None:
            i = len(texts)
            text_idx[t] = i
            texts.append(t)
        return i

    files = sorted(glob.glob(os.path.join(ECU_DIR, "*.prg")))
    for n, path in enumerate(files, 1):
        stem = os.path.splitext(os.path.basename(path))[0].lower()
        try:
            tbl = PrgFile(path).table("FORTTEXTE")
        except Exception as e:  # keep going, report at the end
            failed.append((stem, str(e)))
            continue
        if not tbl:
            skipped += 1
            continue
        fam = family_of(stem, bases) or ("_other:" + stem)
        if fam.startswith("_other:"):
            unmatched.append(stem)
        f = families.setdefault(fam, {"addresses": bases.get(fam, []), "variants": [], "codes": {}})
        f["variants"].append(stem)
        vi = len(f["variants"]) - 1
        header = [h.upper() for h in tbl[0]]
        try:
            ci, ti = header.index("ORT"), header.index("ORTTEXT")
        except ValueError:
            continue
        for row in tbl[1]:
            m = DTC_RE.match(row[ci].strip())
            text = row[ti].strip()
            if not m or not text:
                continue
            code = m.group(1).upper().zfill(6)
            by_text = f["codes"].setdefault(code, {})
            by_text.setdefault(tidx(text), []).append(vi)

    out_fams = {}
    total_codes = 0
    for fam, f in families.items():
        codes = {}
        for code, bt in f["codes"].items():
            codes[code] = [[ti, vs] for ti, vs in bt.items()]
        total_codes += len(codes)
        out_fams[fam] = {"addresses": f["addresses"], "variants": f["variants"], "codes": codes}

    address_index = {}
    for fam, f in out_fams.items():
        for a in f["addresses"]:
            address_index.setdefault(a, []).append(fam)

    payload = {
        "metadata": {
            "version": "1.0.0",
            "source": "BMW ISTA+ 4.59.30 Ecu/*.prg FORTTEXTE + KIS ECU addresses",
            "language": "de/en (official factory strings, unmodified)",
            "prg_files_scanned": len(files),
            "prg_files_failed": len(failed),
            "families": len(out_fams),
            "unique_texts": len(texts),
            "family_code_entries": total_codes,
        },
        "texts": texts,
        "families": out_fams,
        "address_index": address_index,
    }
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
    print("files", len(files), "failed", failed, "no FORTTEXTE", skipped)
    print("families", len(out_fams), "unmatched SGBDs", len(unmatched))
    print("unique texts", len(texts), "family-code entries", total_codes)
    print("size MB", round(os.path.getsize(OUT_JSON) / 1048576, 2))
    print("unmatched sample:", unmatched[:40])


if __name__ == "__main__":
    main()
