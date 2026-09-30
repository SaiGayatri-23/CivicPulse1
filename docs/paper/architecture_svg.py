"""Vector architecture diagram for the CivicPulse paper.

Writes fig_architecture.svg, then renders it with headless Chrome to fig_architecture.pdf (vector, for LaTeX)
and fig_architecture.png (for Word).
"""
import subprocess
from pathlib import Path

OUT = Path(__file__).parent
W, H = 1600, 980

INK, MUTED = "#0f172a", "#475569"
LANES = {
    "users": dict(x=20, w=220, stroke="#64748b", fill="#f8fafc", head="#334155"),
    "client": dict(x=265, w=530, stroke="#2563eb", fill="#f5f9ff", head="#1d4ed8"),
    "supa": dict(x=820, w=530, stroke="#059669", fill="#f3fbf7", head="#047857"),
    "ext": dict(x=1375, w=205, stroke="#d97706", fill="#fffaf0", head="#b45309"),
}
TOP, BOT = 60, 800

svg = []


def add(s):
    svg.append(s)


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, t, size=14, weight=400, fill=INK, anchor="start", italic=False):
    style = ' font-style="italic"' if italic else ""
    add(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{style}>{esc(t)}</text>')


def box(x, y, w, h, lines, fill="#fff", stroke="#cbd5e1", size=13, weight=500, r=8, color=INK, sub=None):
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')
    lines = lines if isinstance(lines, list) else [lines]
    total = len(lines) + (1 if sub else 0)
    lh = size + 4
    cy = y + h / 2 - (total - 1) * lh / 2 + size * 0.35
    for i, ln in enumerate(lines):
        text(x + w / 2, cy + i * lh, ln, size, weight, color, "middle")
    if sub:
        text(x + w / 2, cy + len(lines) * lh, sub, size - 2, 400, MUTED, "middle")


def lane(key, title, subtitle):
    L = LANES[key]
    add(f'<rect x="{L["x"]}" y="{TOP}" width="{L["w"]}" height="{BOT - TOP}" rx="16" fill="{L["fill"]}" stroke="{L["stroke"]}" stroke-width="2"/>')
    add(f'<rect x="{L["x"]}" y="{TOP}" width="{L["w"]}" height="6" rx="3" fill="{L["stroke"]}"/>')
    text(L["x"] + 16, TOP + 32, title, 17, 700, L["head"])
    if subtitle:
        text(L["x"] + 16, TOP + 52, subtitle, 12, 400, MUTED)


def group(x, y, w, h, title, stroke):
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="#ffffff" fill-opacity="0.7" stroke="{stroke}" stroke-width="1.2" stroke-dasharray="5 4"/>')
    text(x + 10, y + 18, title.upper(), 10.5, 700, stroke)


STYLES = {
    "sync": ' stroke="#334155" stroke-width="2"',
    "async": ' stroke="#334155" stroke-width="2" stroke-dasharray="7 5"',
    "direct": ' stroke="#b45309" stroke-width="2" stroke-dasharray="2 4"',
}


def path(points, kind="sync", arrow=True):
    d = "M " + " L ".join(f"{x} {y}" for x, y in points)
    marker = f' marker-end="url(#arr-{kind})"' if arrow else ""
    add(f'<path d="{d}" fill="none"{STYLES[kind]}{marker}/>')


def badge(x, y, n):
    add(f'<circle cx="{x}" cy="{y}" r="11" fill="#dc2626" stroke="#fff" stroke-width="2"/>')
    text(x, y + 4.5, str(n), 12, 700, "#fff", "middle")


def label(x, y, t, size=11.5):
    w = len(t) * size * 0.52 + 10
    add(f'<rect x="{x - w / 2}" y="{y - size}" width="{w}" height="{size + 7}" rx="4" fill="#ffffff"/>')
    text(x, y + 1, t, size, 500, MUTED, "middle")


# ---- icons (simple, monochrome)
def icon_user(cx, cy, c):
    add(f'<circle cx="{cx}" cy="{cy - 7}" r="7" fill="none" stroke="{c}" stroke-width="2"/>'
        f'<path d="M {cx - 12} {cy + 13} Q {cx} {cy - 3} {cx + 12} {cy + 13}" fill="none" stroke="{c}" stroke-width="2"/>')


def icon_org(cx, cy, c):
    add(f'<rect x="{cx - 11}" y="{cy - 12}" width="22" height="24" fill="none" stroke="{c}" stroke-width="2"/>'
        + "".join(f'<rect x="{cx - 7 + dx}" y="{cy - 8 + dy}" width="4" height="4" fill="{c}"/>' for dx in (0, 10) for dy in (0, 8)))


def icon_shield(cx, cy, c):
    add(f'<path d="M {cx} {cy - 13} L {cx + 11} {cy - 8} L {cx + 11} {cy + 1} Q {cx + 11} {cy + 10} {cx} {cy + 14} '
        f'Q {cx - 11} {cy + 10} {cx - 11} {cy + 1} L {cx - 11} {cy - 8} Z" fill="none" stroke="{c}" stroke-width="2"/>'
        f'<path d="M {cx - 5} {cy} L {cx - 1} {cy + 4} L {cx + 6} {cy - 4}" fill="none" stroke="{c}" stroke-width="2"/>')


def icon_mega(cx, cy, c):
    add(f'<path d="M {cx - 12} {cy - 4} L {cx - 4} {cy - 4} L {cx + 10} {cy - 12} L {cx + 10} {cy + 12} L {cx - 4} {cy + 4} '
        f'L {cx - 12} {cy + 4} Z" fill="none" stroke="{c}" stroke-width="2"/>'
        f'<path d="M {cx - 6} {cy + 4} L {cx - 3} {cy + 13}" stroke="{c}" stroke-width="2"/>')


# ======================================================================
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H - 45}" viewBox="0 45 {W} {H - 45}" '
    'font-family="Segoe UI, Helvetica, Arial, sans-serif">')
add('<defs>')
for k, col in (("sync", "#334155"), ("async", "#334155"), ("direct", "#b45309")):
    add(f'<marker id="arr-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{col}"/></marker>')
add('</defs>')
add(f'<rect y="0" width="{W}" height="{H}" fill="#ffffff"/>')

lane("users", "Users", "Browser or installed app")
lane("client", "Client  ·  React 19 progressive web app", "TypeScript  ·  Tailwind CSS  ·  Vite")
lane("supa", "Backend  ·  Supabase", "Managed PostgreSQL with auth, API and storage")
lane("ext", "External services", "Free-tier APIs")

# ---- Users
users = [("Citizen / guest", icon_user), ("Verified organisation", icon_org), ("Administrator", icon_shield), ("Advertiser", icon_mega)]
uy = [140, 300, 470, 600]
for (name, ic), y in zip(users, uy):
    add(f'<rect x="38" y="{y}" width="184" height="86" rx="10" fill="#fff" stroke="#cbd5e1" stroke-width="1.4"/>')
    ic(130, y + 30, "#334155")
    text(130, y + 70, name, 13.5, 600, INK, "middle")

# ---- Client
CX = 280
group(CX, 128, 500, 250, "Citizen experience", "#2563eb")
mods = [["Feed, map", "and search"], ["Report", "+ AI assist"], ["Report detail,", "timeline, replies"],
        ["Events and", "petitions"], ["Utilities", "and buses"], ["Profile and", "verification"],
        ["SOS and", "child alerts"], ["Missions", "and points"], ["Help and", "feedback"]]
for i, m in enumerate(mods):
    x = CX + 12 + (i % 3) * 161
    y = 156 + (i // 3) * 72
    box(x, y, 152, 62, m, fill="#ffffff", stroke="#bfdbfe", size=13)
group(CX, 392, 500, 96, "Staff and partners", "#2563eb")
box(CX + 12, 418, 232, 58, "Admin console", fill="#fff", stroke="#bfdbfe", sub="work, safety, content, money, oversight")
box(CX + 256, 418, 232, 58, "Advertiser campaigns", fill="#fff", stroke="#bfdbfe", sub="draft, review, stats, spend")
group(CX, 502, 500, 284, "In-browser platform", "#2563eb")
chips = ["TanStack Query cache", "React Router", "i18n: 23 languages, RTL", "Leaflet maps, exifr GPS",
         "Workbox service worker", "IndexedDB offline outbox", "Web Push subscription", "Turnstile CAPTCHA widget"]
for i, c in enumerate(chips):
    x = CX + 12 + (i % 2) * 244
    y = 530 + (i // 2) * 62
    box(x, y, 232, 50, c, fill="#eff6ff", stroke="#bfdbfe", size=13)

# ---- Backend: platform services (left sub-column)
SX, SW = 836, 170
svc = [(138, ["Auth"], "email, guest, Google"), (262, ["REST API"], "PostgREST: tables + RPC"), (386, ["Storage"], "photos, videos, ads, docs")]
for y, t, s in svc:
    box(SX, y, SW, 96, t, fill="#ffffff", stroke="#6ee7b7", size=15, weight=700, sub=s)
# PostgreSQL (right sub-column)
PX, PW = 1024, 312
add(f'<rect x="{PX}" y="128" width="{PW}" height="658" rx="12" fill="#ffffff" stroke="#059669" stroke-width="1.8"/>')
text(PX + 14, 152, "PostgreSQL", 16, 700, "#047857")
text(PX + 14, 170, "44 tables · 109 functions · 53 triggers · 124 policies", 11.5, 400, MUTED)
clusters = [
    ("Security", 184, ["Row-level security", "Column grants", "pgcrypto encryption", "Vault secrets"]),
    ("Business logic", 336, ["Lifecycle triggers", "Dedupe and limits", "RPC: AI, admin", "Points, notify"]),
    ("Integrations", 488, ["http  (sync)", "pg_net  (async)"]),
    ("Operations", 592, ["pg_cron purge", "pg_trgm search", "Audit log", "Error log"]),
]
chip_pos = {}
for title, y, items in clusters:
    rows = (len(items) + 1) // 2
    h = 30 + rows * 50
    group(PX + 10, y, PW - 20, h, title, "#059669")
    for i, it in enumerate(items):
        x = PX + 20 + (i % 2) * 142
        yy = y + 26 + (i // 2) * 50
        box(x, yy, 134, 40, it, fill="#ecfdf5", stroke="#a7f3d0", size=12.5)
        chip_pos[it] = (x, yy)
text(PX + PW / 2, 758, "Rules run inside the database, so they hold", 11.5, 400, MUTED, "middle", italic=True)
text(PX + PW / 2, 774, "even if the client is bypassed.", 11.5, 400, MUTED, "middle", italic=True)

# ---- External services
EX, EW = 1390, 175
ext = [(128, "Resend", "email alerts"), (228, "Web Push", "browser push services"), (328, "Google Gemini", "AI suggestions"),
       (470, "OpenStreetMap", "tiles, Nominatim, Overpass"), (570, "Open-Meteo", "weather and air quality"), (670, "Cloudflare Turnstile", "bot protection")]
for y, t, s in ext:
    box(EX, y, EW, 80, t, fill="#ffffff", stroke="#fcd34d", size=14, weight=700, sub=s)

# ================= connectors
# Users -> client
path([(222, 183), (292, 183)])
path([(222, 343), (250, 343), (250, 250), (292, 250)])
path([(222, 513), (250, 513), (250, 447), (292, 447)])
path([(222, 643), (256, 643), (256, 460), (292, 460)])
badge(257, 183, 1)
# Client -> platform services (all synchronous HTTPS)
path([(780, 186), (836, 186)])
badge(808, 186, 2)
path([(780, 300), (836, 300)])
badge(808, 300, 4)
path([(780, 424), (836, 424)])
badge(808, 424, 3)
# Services -> Postgres
path([(1006, 186), (1024, 186)])
path([(1006, 310), (1024, 310)])
badge(1015, 350, 5)
path([(1006, 434), (1024, 434)])
# Integrations -> external
hx, hy = chip_pos["http  (sync)"]
nx, ny = chip_pos["pg_net  (async)"]
# pg_net (right chip) -> email and push on the inner bus; http (left chip) -> AI on the outer bus. No crossings.
path([(nx + 134, ny + 20), (1350, ny + 20), (1350, 168), (EX, 168)], "async")
path([(1350, 268), (EX, 268)], "async")
badge(1350, 410, 7)
path([(hx + 67, hy + 40), (hx + 67, 578), (1366, 578), (1366, 368), (EX, 368)], "sync")
badge(1366, 470, 6)
# Browser -> map, weather, CAPTCHA (direct, not through backend)
path([(CX + 250, 786), (CX + 250, 814), (1372, 814), (1372, 510), (EX, 510)], "direct", arrow=True)
path([(1372, 610), (EX, 610)], "direct")
path([(1372, 710), (EX, 710)], "direct")
label(820, 814, "direct from the browser: maps, weather, CAPTCHA")

# ================= legend
LY = 850
add(f'<rect x="20" y="{LY}" width="1560" height="112" rx="12" fill="#f8fafc" stroke="#e2e8f0"/>')
text(40, LY + 26, "Legend", 13, 700)
for i, (k, t) in enumerate((("sync", "Synchronous request"), ("async", "Background (asynchronous)"), ("direct", "Direct from the browser"))):
    y = LY + 50 + i * 22
    path([(40, y - 4), (95, y - 4)], k)
    text(106, y, t, 12, 400, MUTED)
text(360, LY + 26, "Reporting a problem, step by step", 13, 700)
steps = ["Citizen or guest fills in the report in the app", "Signs in, or a guest session is created",
         "Photos and video upload to storage", "Report is inserted through the REST API",
         "Triggers check access, duplicates, limits and priority", "AI suggestions: auto-fill, duplicate check, routing",
         "Followers are notified by email and web push"]
for i, s in enumerate(steps):
    col, row = (0, i) if i < 3 else ((1, i - 3) if i < 5 else (2, i - 5))
    x = 360 + col * 410
    y = LY + 50 + row * 22
    add(f'<circle cx="{x + 8}" cy="{y - 4}" r="8" fill="#dc2626"/>')
    text(x + 8, y, str(i + 1), 10.5, 700, "#fff", "middle")
    text(x + 24, y, s, 12, 400, MUTED)
add("</svg>")

svg_path = OUT / "fig_architecture.svg"
svg_path.write_text("\n".join(svg), encoding="utf-8")

import os, subprocess
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
VH = H - 45
html = OUT / "_arch_render.html"
html.write_text(f'<!doctype html><html><head><style>@page {{ size: {W}px {VH}px; margin: 0; }} html,body{{margin:0}} img{{display:block}}</style></head>'
                f'<body><img src="fig_architecture.svg" width="{W}" height="{VH}"></body></html>', encoding="utf-8")
prof = os.path.join(os.environ.get("TEMP", str(OUT)), "cp_chrome_prof")
base = [CHROME, "--headless=new", "--disable-gpu", f"--user-data-dir={prof}"]
url = html.resolve().as_uri()
subprocess.run(base + ["--no-pdf-header-footer", f"--print-to-pdf={OUT / 'fig_architecture.pdf'}", url], check=True, capture_output=True)
subprocess.run(base + ["--hide-scrollbars", "--force-device-scale-factor=2", f"--window-size={W},{VH}", f"--screenshot={OUT / 'fig_architecture.png'}", url], check=True, capture_output=True)
html.unlink()
print("wrote fig_architecture.svg/.pdf/.png")
