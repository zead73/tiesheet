#!/bin/sh
# Prints what LibreOffice Calc computes for each line of formulas.txt, to settle how a function
# should behave (LibreOffice is the reference: it is what the user uses for anything complex).
# Needs the LibreOffice AppImage in ~/Apps.  The formulas use ; between arguments, as in
# OpenFormula; data sits in F1:G6 (see gen.py).  Uses a throw-away profile under build/.
set -e
cd "$(dirname "$0")/../.."
L=$(ls "$HOME"/Apps/LibreOffice-latest*.AppImage | head -1)
W=$PWD/build/oracle
P=$PWD/build/oracle-profile      # kept between runs: a brand-new profile needs a first start
rm -rf "$W"; mkdir -p "$W/out"
python3 tests/oracle/gen.py "${1:-tests/oracle/formulas.txt}" > "$W/in.csv"
for attempt in 1 2; do
"$L" -env:UserInstallation=file://"$P" --headless \
  --infilter='Text - txt - csv (StarCalc):44,34,76,1,,0,false,true,false,false,false,-1,true' \
  --convert-to 'csv:Text - txt - csv (StarCalc):44,34,76,1,,0,false,false,false,false,false,-1' \
  --outdir "$W/out" "$W/in.csv" >/dev/null 2>&1 || true
[ -f "$W/out/in-in.csv" ] && break
done
[ -f "$W/out/in-in.csv" ] || { echo "LibreOffice produced no output" >&2; exit 1; }
python3 - "${1:-tests/oracle/formulas.txt}" "$W/out/in-in.csv" <<'PY'
import csv, sys
f = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
r = list(csv.reader(open(sys.argv[2], encoding="utf-8")))
for a, b in zip(f, r):
    print("%-40s %s" % (a, b[0]))
PY
