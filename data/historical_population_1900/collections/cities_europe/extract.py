"""Extract the fields used by this collection from the publishers' original tables."""
import csv
import io
import struct
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent
SGF = "https://www.insee.fr/fr/statistiques/fichier/2653233/"
FILES = {
    "chandlerV2.csv": "https://ndownloader.figstatic.com/files/5407640",
    **{f"REC_T{n}.dbf": f"{SGF}REC_T{n}.dbf" for n in (24, 214, 256)},
}


def read_original(name):
    cached = ROOT / ".download" / name
    if cached.exists():
        return cached.read_bytes()
    with urlopen(FILES[name], timeout=90) as stream:
        return stream.read()


def dbf_rows(data):
    count, header_size, record_size = struct.unpack_from("<IHH", data, 4)
    fields = []
    for offset in range(32, header_size - 1, 32):
        name = data[offset:offset + 11].rstrip(b"\0").decode("ascii")
        fields.append((name, data[offset + 16]))
    for i in range(count):
        pos = header_size + i * record_size
        if data[pos:pos + 1] == b"*":
            continue
        pos += 1
        row = {}
        for name, width in fields:
            row[name] = data[pos:pos + width].decode("cp850").strip()
            pos += width
        yield i + 1, row


def extract():
    with (ROOT / "chandler_1900.csv").open("w", newline="", encoding="utf-8") as out:
        rows = csv.DictReader(io.StringIO(read_original("chandlerV2.csv").decode("cp1252")))
        columns = ["record", "City", "OtherName", "Country", "Latitude", "Longitude", "Certainty", "AD_1900"]
        writer = csv.DictWriter(out, columns, extrasaction="ignore")
        writer.writeheader()
        for index, row in enumerate(rows, 1):
            if row["AD_1900"].strip() and int(row["AD_1900"]) >= 50000:
                writer.writerow(dict(row, record=index))
    with (ROOT / "french_census.csv").open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["table", "record", "V1", "V3", "V4", "V6", "field", "value"])
        for n, level, columns in [(256, {"0", "1"}, ["V21", "V22"]),
                                  (24, {"2"}, ["V132"]), (214, {"2"}, ["V89"])]:
            for rec, row in dbf_rows(read_original(f"REC_T{n}.dbf")):
                if row["V1"] not in level:
                    continue
                for col in columns:
                    if row[col] and int(row[col]) > 0:
                        writer.writerow([n, rec, row["V1"], row["V3"], row["V4"], row["V6"], col, row[col]])


if __name__ == "__main__":
    extract()
