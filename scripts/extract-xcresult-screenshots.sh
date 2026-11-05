#!/bin/bash
# Pull PNG attachments out of an xcresult. The UI tests do not write files themselves.
set -euo pipefail

XCRESULT="${1:?xcresult path}"
OUT="${2:?output directory}"
mkdir -p "$OUT/png"
rm -rf "$OUT/exported" "$OUT/png"
mkdir -p "$OUT/exported" "$OUT/png"

if [[ ! -d "$XCRESULT" ]]; then
  mkdir -p "$OUT/png"
  echo "No xcresult bundle at $XCRESULT"
  echo "PNG_COUNT=0"
  exit 0
fi

echo "xcresulttool version:"
xcrun xcresulttool version || true
echo "export help (first lines):"
xcrun xcresulttool help export >"$OUT/export-help.txt" 2>&1 || xcrun xcresulttool --help >"$OUT/export-help.txt" 2>&1 || true
head -n 30 "$OUT/export-help.txt" || true

set +e
rm -rf "$OUT/exported"
xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$OUT/exported" >"$OUT/export.log" 2>&1
export_status=$?
if [[ $export_status -ne 0 ]]; then
  rm -rf "$OUT/exported"
  xcrun xcresulttool export attachments --xcresult-path "$XCRESULT" --output-path "$OUT/exported" >"$OUT/export.log" 2>&1
  export_status=$?
fi
set -e
echo "xcresulttool export attachments status: $export_status"
# The tool prints: File: <uuid>.png, suggested name: "hook-01-start_0_<uuid>.png"
sed -n 's/^File: //p' "$OUT/export.log" | head -n 40 || true

python3 - "$XCRESULT" "$OUT" "$OUT/export.log" <<'PY'
import pathlib, re, sys
xcresult = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
export_log = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else out / "export.log"
exported = out / "exported"
png_dir = out / "png"
png_dir.mkdir(parents=True, exist_ok=True)

suggested = {}
if export_log.exists():
    for line in export_log.read_text(errors="ignore").splitlines():
        match = re.search(r'File:\s*([^,\s]+\.png),\s*suggested name:\s*"([^"]+)"', line)
        if not match:
            continue
        source_name, raw_name = match.group(1), match.group(2)
        clean = re.sub(r"_0_[0-9A-Fa-f-]{36}(?=\.png$)", "", raw_name)
        suggested[source_name] = clean
        suggested[pathlib.Path(source_name).stem] = clean

def attachment_name(path: pathlib.Path):
    if path.stem.startswith("hook-") or path.stem.startswith("sim-"):
        return path.stem
    for parent in path.parents:
        if parent.stem.startswith("hook-") or parent.stem.startswith("sim-"):
            return parent.stem
    return None

blobs = []
for path in list(xcresult.rglob("database.sqlite3")) + list(xcresult.rglob("*")):
    if path.is_file() and path.stat().st_size < 80_000_000 and path.suffix.lower() not in {".png"}:
        try:
            blobs.append(path.read_bytes().decode("latin1", errors="ignore"))
        except OSError:
            pass
catalog = "\n".join(blobs)

def name_for_uuid(uuid):
    start = 0
    while True:
        index = catalog.find(uuid, start)
        if index < 0:
            return None
        window = catalog[max(0, index - 120):index]
        match = re.search(r"((?:hook|sim)-[A-Za-z0-9-]+)$", window)
        if match:
            return match.group(1)
        start = index + len(uuid)

named = {}
unnamed = []
roots = [exported, xcresult]
seen = set()
for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() != ".png":
            continue
        if "carved-" in path.name:
            continue
        key = path.stat().st_size, path.read_bytes()[:64]
        label = (
            suggested.get(path.name)
            or suggested.get(path.stem)
            or attachment_name(path)
            or name_for_uuid(path.stem.upper())
            or name_for_uuid(path.stem)
        )
        if isinstance(label, str) and label.endswith(".png"):
            label = label[:-4]
        if label is None:
            unnamed.append(path.name)
            continue
        if label in named:
            continue
        named[label] = path.read_bytes()
        seen.add(key)

for label, data in sorted(named.items()):
    filename = label if label.endswith(".png") else f"{label}.png"
    (png_dir / filename).write_bytes(data)

lines = []
for path in sorted(png_dir.glob("*.png")):
    lines.append(f"{path.stat().st_size:8d}  {path.name}")
(png_dir / "MANIFEST.txt").write_text("\n".join(lines) + ("\n" if lines else ""))
print(f"PNG_COUNT={len(lines)}")
print(f"UNNAMED_SKIPPED={len(unnamed)}")
print("---- PNG files ----")
print("\n".join(lines) if lines else "(none)")
if unnamed:
    print("skipped unnamed pngs:", ", ".join(unnamed[:12]))
PY
