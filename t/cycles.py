#!/usr/bin/env python3
"""Sucht Aufrufzyklen zwischen Subs, die NICHT ueber einen Timer laufen.

Ein Zyklus A -> B -> A ohne InternalTimer dazwischen ist eine Rekursion ohne
Abbruch durch die Ereignisschleife: sie laeuft in derselben Sekunde durch,
bis der Stack voll ist. Genau das war der Fehler vom 22.08.2026
(NextValve -> FillBarrel -> NextValve)."""
import re, sys, collections

src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
prefix = sys.argv[2] if len(sys.argv) > 2 else "Gartenbewaesserung"

# Subs mit Zeilenbereich einsammeln (Klammern zaehlen, Strings/Kommentare grob raus)
subs, order = {}, []
for m in re.finditer(r'^sub\s+(%s_\w+)\s*\{' % prefix, src, re.M):
    name, i, depth = m.group(1), m.end() - 1, 0
    while i < len(src):
        c = src[i]
        if c == '#':                       # Kommentar bis Zeilenende
            i = src.find('\n', i);  i = len(src) if i < 0 else i;  continue
        if c in '"\'':                     # String ueberspringen
            q, i = c, i + 1
            while i < len(src) and src[i] != q:
                i += 2 if src[i] == '\\' else 1
        elif c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: break
        i += 1
    subs[name] = src[m.end():i]
    order.append(name)

# Aufrufkanten, aber nur ausserhalb von InternalTimer(...)-Argumenten
TIMER = re.compile(r'InternalTimer\s*\(')
def outside_timer(body):
    """Body ohne die Argumentlisten von InternalTimer(...)."""
    out, pos = [], 0
    for m in TIMER.finditer(body):
        out.append(body[pos:m.start()])
        i, depth = m.end() - 1, 0
        while i < len(body):
            if body[i] == '(': depth += 1
            elif body[i] == ')':
                depth -= 1
                if depth == 0: break
            i += 1
        pos = i + 1
    out.append(body[pos:])
    return "".join(out)

graph = collections.defaultdict(set)
for name, body in subs.items():
    for m in re.finditer(r'\b(%s_\w+)\s*\(' % prefix, outside_timer(body)):
        if m.group(1) in subs:
            graph[name].add(m.group(1))

# Zyklen suchen (Tarjan waere schoener, DFS reicht hier)
found, stack, onstack, seen = [], [], set(), set()
def dfs(n):
    stack.append(n); onstack.add(n); seen.add(n)
    for m in sorted(graph[n]):
        if m in onstack:
            found.append(stack[stack.index(m):] + [m])
        elif m not in seen:
            dfs(m)
    stack.pop(); onstack.discard(n)

sys.setrecursionlimit(10000)
for n in order:
    if n not in seen: dfs(n)

uniq = {tuple(c): c for c in found}
short = lambda s: s[len(prefix) + 1:]
if not uniq:
    print("keine timerlosen Aufrufzyklen gefunden")
else:
    print("%d timerloser Aufrufzyklus/-zyklen:" % len(uniq))
    for c in uniq.values():
        print("  " + " -> ".join(short(x) for x in c))
sys.exit(1 if uniq else 0)
