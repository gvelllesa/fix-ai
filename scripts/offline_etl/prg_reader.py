"""Minimal, read-only parser for EDIABAS SGBD (.prg) table sections.

Format verified against the open-source EdiabasLib reference
(EdiabasNet.cs: ReadAllTables / ReadTable / IndexTable / ReadAndDecryptBytes):
  * int32 LE at file offset 0x84  -> offset of the table directory
  * table directory: int32 table count (XOR 0xF7), then `count` records of 0x50 bytes
      0x00..0x3F  table name (cp1252, NUL padded)
      0x40        uint32 offset of column data
      0x48        uint32 column count
      0x4C        uint32 row count
  * table data: (rows + 1) * columns NUL-terminated strings, XOR 0xF7
    (row 0 is the header row with column names)
Nothing here is guessed: if a table or column is missing, callers get None.
"""
import struct

XOR_KEY = 0xF7
ENC = "cp1252"


def _dec(buf: bytes) -> bytes:
    return bytes(b ^ XOR_KEY for b in buf)


class PrgFile:
    def __init__(self, path: str):
        self.path = path
        with open(path, "rb") as f:
            self.data = f.read()
        self._tables = None

    def _read_directory(self):
        d = self.data
        tbl_off = struct.unpack_from("<i", d, 0x84)[0]
        if tbl_off < 0 or tbl_off + 4 > len(d):
            return {}
        count = struct.unpack("<i", _dec(d[tbl_off:tbl_off + 4]))[0]
        tables = {}
        pos = tbl_off + 4
        for _ in range(count):
            rec = _dec(d[pos:pos + 0x50])
            name = rec[:0x40].split(b"\0", 1)[0].decode(ENC)
            col_off, = struct.unpack_from("<I", rec, 0x40)
            cols, = struct.unpack_from("<I", rec, 0x48)
            rows, = struct.unpack_from("<I", rec, 0x4C)
            tables[name.upper()] = (name, col_off, cols, rows)
            pos += 0x50
        return tables

    def table_names(self):
        if self._tables is None:
            self._tables = self._read_directory()
        return [v[0] for v in self._tables.values()]

    def table(self, name: str):
        """Return (header, rows) or None. rows are lists of str."""
        if self._tables is None:
            self._tables = self._read_directory()
        ent = self._tables.get(name.upper())
        if ent is None:
            return None
        _, off, cols, rows = ent
        d = self.data
        pos = off
        out = []
        for _r in range(rows + 1):
            row = []
            for _c in range(cols):
                # NUL terminator is stored XOR-ed, i.e. as 0xF7 in the raw file
                end = d.index(bytes([XOR_KEY]), pos)
                row.append(_decode_text(_dec(d[pos:end])))
                pos = end + 1
            out.append(row)
        return out[0], out[1:]


def _decode_text(raw: bytes) -> str:
    """cp1252 (as EdiabasLib does). Some SGBDs store umlauts as OEM cp437 bytes
    (e.g. 0x81 = u-umlaut) which are undefined in cp1252; for those strings only,
    fall back to cp437 instead of emitting replacement characters."""
    try:
        return raw.decode(ENC)
    except UnicodeDecodeError:
        return raw.decode("cp437", errors="replace")
