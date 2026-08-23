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
