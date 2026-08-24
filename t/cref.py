#!/usr/bin/env python3
"""Vergleicht die Set-/Get-Liste im Quelltext mit den commandref-Ankern."""
import io, re, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8", errors="replace").read()
typ = re.search(r'sub (\w+)_Initialize', s).group(1)

# Set-Liste: alle Stringliterale in der Zuweisung an $list / $setList sammeln
def cmdlist(var):
    m = re.search(r'my \$%s\s*=\s*((?:"[^"]*"\s*\.?\s*)+);' % var, s, re.S)
    if not m: return []
    raw = " ".join(re.findall(r'"([^"]*)"', m.group(1)))
    return sorted({t.split(":")[0] for t in raw.split() if re.match(r'^[A-Za-z]', t)})

for var, kind in (("list", "set"), ("setList", "set"), ("getList", "get")):
    cmds = cmdlist(var)
    if not cmds: continue
    anch = set(re.findall(r'a id="%s-%s-(\w+)"' % (typ, kind), s))
    missing = [c for c in cmds if c not in anch]
    extra   = sorted(a for a in anch if a not in cmds)
    print("%-14s %s: %d Befehle, %d Anker" % (typ, kind, len(cmds), len(anch)))
    print("   ohne Anker : %s" % (", ".join(missing) if missing else "-"))
    print("   Anker ohne Befehl: %s" % (", ".join(extra) if extra else "-"))

# --- Version: der Rueckfallwert muss zur Aenderungsliste passen -------------
#
# Die laufende Version liest das Modul zur Laufzeit aus dem obersten Eintrag der
# Aenderungsliste. Der fest verdrahtete $FALLBACK greift nur, wenn das misslingt
# - und ist damit genau die Art Zahl, die unbemerkt veraltet. Hier festgenagelt.
neueste = re.search(r'^#\s*(\d+\.\d+\.\d+)\s+-\s+\d{4}-\d{2}-\d{2}', s, re.M)
fallback = re.search(r'my \$FALLBACK\s*=\s*[\'"](\d+\.\d+\.\d+)[\'"]', s)
print()
if not neueste:
    print("Version: kein Eintrag der Form '# X.Y.Z - JJJJ-MM-TT' gefunden")
    sys.exit(1)
if not fallback:
    print("Version: %s laut Aenderungsliste, kein $FALLBACK vorhanden" % neueste.group(1))
elif fallback.group(1) != neueste.group(1):
    print("Version: Aenderungsliste sagt %s, $FALLBACK sagt %s - nachziehen"
          % (neueste.group(1), fallback.group(1)))
    sys.exit(1)
else:
    print("Version: %s, Aenderungsliste und $FALLBACK einig" % neueste.group(1))

# Eine fest verdrahtete Version darf es sonst nirgends mehr geben.
hart = [m for m in re.findall(r'\{VERSION\}\s*=\s*[\'"]([^\'"]+)[\'"]', s)]
if hart:
    print("Version: noch fest verdrahtet in $hash->{VERSION}: %s" % ", ".join(hart))
    sys.exit(1)
