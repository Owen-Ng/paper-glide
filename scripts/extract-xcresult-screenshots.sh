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
xcrun xcresulttool export attachments --path "$XCRESULT" --output-path "$OUT/exported"
export_status=$?
if [[ $export_status -ne 0 ]]; then
  rm -rf "$OUT/exported"
  xcrun xcresulttool export attachments --xcresult-path "$XCRESULT" --output-path "$OUT/exported"
  export_status=$?
fi
set -e
echo "xcresulttool export attachments status: $export_status"

python3 - "$XCRESULT" "$OUT" <<'PY'
import pathlib, sys
xcresult = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
exported = out / "exported"
png_dir = out / "png"
png_dir.mkdir(parents=True, exist_ok=True)

def preferred_name(path: pathlib.Path) -> str:
    if "hook-" in path.name or "sim-" in path.name:
        return path.name
    for parent in path.parents:
        if "hook-" in parent.name or "sim-" in parent.name:
            suffix = path.suffix if path.suffix else ".png"
            base = parent.name
            return base if base.endswith(suffix) else f"{base}{suffix}"
    return path.name

def flatten(root: pathlib.Path):
    copied = []
    if not root.exists():
        return copied
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() == ".png":
            dest = png_dir / preferred_name(path)
            if dest.exists():
                dest = png_dir / f"{path.parent.name}-{path.name}"
            dest.write_bytes(path.read_bytes())
            copied.append(dest)
    return copied

found = flatten(exported)
interesting = [p for p in found if "hook-" in p.name or "sim-" in p.name]
if not interesting:
    magic = b"\x89PNG\r\n\x1a\n"
    end = b"IEND\xaeB`\x82"
    for path in xcresult.rglob("*"):
        if not path.is_file() or path.stat().st_size > 30_000_000:
            continue
        data = path.read_bytes()
        start = 0
        index = 0
        while True:
            begin = data.find(magic, start)
            if begin < 0:
                break
            finish = data.find(end, begin)
            if finish < 0:
                break
            blob = data[begin:finish + len(end)]
            dest = png_dir / f"carved-{path.name}-{index}.png"
            dest.write_bytes(blob)
            index += 1
            start = finish + len(end)
    found = list(png_dir.glob("*.png"))

lines = []
for path in sorted(png_dir.glob("*.png")):
    lines.append(f"{path.stat().st_size:8d}  {path.name}")
manifest = png_dir / "MANIFEST.txt"
manifest.write_text("\n".join(lines) + ("\n" if lines else ""))
print(f"PNG_COUNT={len(lines)}")
print("---- PNG files ----")
print("\n".join(lines) if lines else "(none)")
PY
