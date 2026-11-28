"""Build the 'Why Use OpenZiti?' explanatory diagrams as light and dark SVGs.

Each diagram is self-contained (system sans/mono fonts, no external refs, no scripts)
so it renders natively in GitHub Markdown (via <picture>/prefers-color-scheme) and in
the standalone browser slideshow.

Usage, from the repo root:

    python3 scripts/diagrams/build_why_openziti_diagrams.py
"""
from html import escape
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent.parent / "assets" / "diagrams"

SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, monospace"

# Brand palette aligned with scripts/diagrams/build_diagrams.py
THEMES = {
    "light": dict(
        bg="#FFFDF9",
        zone="#F6ECDC",
        zone_line="#E3D3B8",
        inner="#FBF5EA",
        inner_line="#D9C7A6",
        card="#FFFFFF",
        card_line="#CDBFA6",
        ink="#14302B",
        muted="#5E6E69",
        http="#3E5A54",
        overlay="#D9481C",
        good="#1E6B52",
        good_bg="#E8F5EF",
        good_line="#8CC8B0",
        bad="#B83227",
        bad_bg="#FDECEB",
        bad_line="#E6A19B",
        warn="#9A6700",
        warn_bg="#FFF6DC",
        warn_line="#E4C46B",
        badge="#FBE3A6",
        badge_ink="#14302B",
        accent_card="#FFF4E8",
        accent_line="#E9A27F",
    ),
    "dark": dict(
        bg="#0F1A18",
        zone="#15241F",
        zone_line="#2A3F39",
        inner="#1A2C27",
        inner_line="#35504A",
        card="#1E322C",
        card_line="#3D5A53",
        ink="#F6ECDC",
        muted="#A8B8B2",
        http="#9FC2B8",
        overlay="#FF7A4D",
        good="#5FD3A8",
        good_bg="#143026",
        good_line="#2E755C",
        bad="#FF7E75",
        bad_bg="#331A19",
        bad_line="#8E3B35",
        warn="#F2C864",
        warn_bg="#332914",
        warn_line="#876A28",
        badge="#3B3220",
        badge_ink="#FBE3A6",
        accent_card="#2A211B",
        accent_line="#9A4A2C",
    ),
}


class Svg:
    def __init__(self, w, h, t, title, desc):
        self.w, self.h, self.t = w, h, t
        self.parts = []
        markers = "".join(
            f'<marker id="arr-{k}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M0 0.8 L9.5 5 L0 9.2 z" fill="{t[k]}"/></marker>\n'
            for k in ("http", "overlay", "good", "bad", "muted")
        )
        self.head = (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
            f'role="img" aria-labelledby="t d" font-family="{SANS}">\n'
            f'<title id="t">{escape(title)}</title>\n'
            f'<desc id="d">{escape(desc)}</desc>\n'
            f"<defs>\n{markers}</defs>\n"
            f'<rect width="{w}" height="{h}" rx="16" fill="{t["bg"]}"/>\n'
        )

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=13, color="ink", weight=400, anchor="start", mono=False, spacing=None):
        fam = f' font-family="{MONO}"' if mono else ""
        ls = f' letter-spacing="{spacing}"' if spacing else ""
        self.add(
            f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{self.t[color]}" '
            f'text-anchor="{anchor}"{fam}{ls}>{escape(s)}</text>'
        )

    def header(self, title, subtitle):
        self.text(36, 44, title, size=20, weight=750)
        self.text(36, 67, subtitle, size=13, color="muted")

    def zone(self, x, y, w, h, label, fill="zone", line="zone_line", label_color="muted", dashed=False, label_x=18):
        dash = ' stroke-dasharray="6 5"' if dashed else ""
        self.add(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" fill="{self.t[fill]}" '
            f'stroke="{self.t[line]}" stroke-width="1.5"{dash}/>'
        )
        if label:
            self.text(x + label_x, y + 26, label, size=11.5, color=label_color, weight=700, spacing="0.08em")

    def card(self, x, y, w, h, title, lines=(), tone="default", title_size=14.5, center=False):
        fills = {
            "default": ("card", "card_line"),
            "good": ("good_bg", "good_line"),
            "bad": ("bad_bg", "bad_line"),
            "warn": ("warn_bg", "warn_line"),
            "accent": ("accent_card", "accent_line"),
        }
        fill, line = fills[tone]
        self.add(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{self.t[fill]}" '
            f'stroke="{self.t[line]}" stroke-width="1.5"/>'
        )
        tx = x + w / 2 if center else x + 16
        anchor = "middle" if center else "start"
        title_color = "bad" if tone == "bad" else "good" if tone == "good" else "ink"
        self.text(tx, y + 26, title, size=title_size, color=title_color, weight=700, anchor=anchor)
        for i, ln in enumerate(lines):
            self.text(tx, y + 46 + i * 17, ln, size=12, color="muted", anchor=anchor)

    def pill(self, cx, cy, label, fill="badge", color="badge_ink", line=None, size=11.5):
        w = max(64, round(len(label) * 6.8 + 20))
        stroke = f' stroke="{self.t[line]}" stroke-width="1.2"' if line else ""
        self.add(f'<rect x="{cx - w / 2}" y="{cy - 11}" width="{w}" height="22" rx="11" fill="{self.t[fill]}"{stroke}/>')
        self.text(cx, cy + 4, label, size=size, color=color, weight=650, anchor="middle")

    def arrow(self, pts, color="http", label=None, at=None, both=False, dashed=False, width=2.2):
        d = "M" + " L".join(f"{x} {y}" for x, y in pts)
        start = f' marker-start="url(#arr-{color})"' if both else ""
        dash = ' stroke-dasharray="6 4"' if dashed else ""
        self.add(
            f'<path d="{d}" fill="none" stroke="{self.t[color]}" stroke-width="{width}" '
            f'stroke-linejoin="round" stroke-linecap="round"{dash} marker-end="url(#arr-{color})"{start}/>'
        )
        if label and at:
            lx, ly = at
            self.pill(lx, ly, label, fill="bg", color=color, line=color, size=11)

    def x_mark(self, cx, cy, r=10):
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{self.t["bad_bg"]}" stroke="{self.t["bad"]}" stroke-width="1.8"/>')
        d = r * 0.45
        self.add(
            f'<path d="M{cx - d} {cy - d} L{cx + d} {cy + d} M{cx + d} {cy - d} L{cx - d} {cy + d}" '
            f'stroke="{self.t["bad"]}" stroke-width="2" stroke-linecap="round"/>'
        )

    def check_mark(self, cx, cy, r=10):
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{self.t["good_bg"]}" stroke="{self.t["good"]}" stroke-width="1.8"/>')
        self.add(
            f'<path d="M{cx - 4.5} {cy + 0.5} L{cx - 1.2} {cy + 3.8} L{cx + 5} {cy - 3.5}" '
            f'fill="none" stroke="{self.t["good"]}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
        )

    def save(self, path):
        path.write_text(self.head + "\n".join(self.parts) + "\n</svg>\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# 1. Castle-and-Moat vs. OpenZiti Zero Trust
# ---------------------------------------------------------------------------
def castle_vs_zero_trust(t):
    s = Svg(
        1040, 560, t,
        "Traditional Network vs. OpenZiti Zero Trust",
        "Side-by-side comparison showing how a traditional network exposes open doors to the internet "
        "and allows intruders to roam inside, while OpenZiti has no open doors and grants private "
        "per-app paths only after verifying identity.",
    )
    s.header(
        "The Old Castle-and-Moat vs. OpenZiti Zero Trust",
        "Stop defending a network perimeter that anyone on the internet can knock on.",
    )

    # Left panel: Traditional Network
    s.zone(28, 92, 480, 440, "TRADITIONAL NETWORK / VPN (CASTLE & MOAT)", fill="bad_bg", line="bad_line", label_color="bad")
    s.card(52, 134, 155, 68, "Bots & Attackers", ["Scan open ports", "24/7 from internet"], tone="bad")
    s.card(248, 134, 236, 68, "Open Front Doors", ["Public IP · VPN · SSH · Web", "Firewall rules to maintain"], tone="warn")

    s.arrow([(207, 168), (248, 168)], color="bad", width=2.4)

    # Inside the flat network
    s.zone(52, 232, 432, 210, "INSIDE THE NETWORK — FLAT ACCESS", fill="card", line="bad_line", label_color="bad", dashed=True, label_x=104)
    s.card(72, 272, 120, 62, "CRM App", ["Sales tool"], center=True)
    s.card(208, 272, 120, 62, "Payroll DB", ["Sensitive HR"], center=True)
    s.card(344, 272, 120, 62, "Prod Servers", ["Core infra"], center=True)

    # Intruder moving laterally (routes left of inner zone label)
    s.arrow([(340, 202), (340, 220), (112, 220), (112, 272)], color="bad", dashed=True)
    s.arrow([(192, 303), (208, 303)], color="bad", both=True, width=2)
    s.arrow([(328, 303), (344, 303)], color="bad", both=True, width=2)

    s.pill(268, 372, "One stolen password = attacker roams the entire building", fill="bad_bg", color="bad", line="bad_line")
    s.text(268, 418, "Exposed to DDoS, port scanning, and lateral movement", size=12, color="bad", weight=600, anchor="middle")

    s.pill(268, 488, "Trusts location (\"you're inside the office / VPN\")", fill="card", color="bad", line="bad_line")

    # Right panel: OpenZiti
    s.zone(532, 92, 480, 440, "OPENZITI ZERO TRUST (INVISIBLE BY DEFAULT)", fill="good_bg", line="good_line", label_color="good")
    s.card(556, 134, 155, 68, "Bots & Attackers", ["Scan public IP...", "Nothing answers!"], tone="default")
    s.card(752, 134, 236, 68, "Verified Identity", ["Strong device + user key", "Checked before connecting"], tone="good")

    # Blocked scan
    s.arrow([(633, 202), (633, 240)], color="muted", dashed=True)
    s.x_mark(633, 244, r=12)
    s.text(633, 274, "No open app ports", size=11.5, color="bad", weight=700, anchor="middle")
    s.text(633, 290, "Servers stay invisible", size=11, color="muted", anchor="middle")

    # Isolated dark services
    s.zone(556, 326, 432, 116, "YOUR APPS — NO OPEN INBOUND PORTS", fill="card", line="good_line", label_color="good", dashed=True, label_x=118)
    s.card(576, 362, 120, 62, "CRM App", ["Allowed"], tone="good", center=True)
    s.card(712, 362, 120, 62, "Payroll DB", ["Hidden"], center=True)
    s.card(848, 362, 120, 62, "Prod Servers", ["Hidden"], center=True)

    # Direct encrypted tunnel to CRM only (clean route, zero text overlap)
    s.arrow([(870, 202), (870, 308), (612, 308), (612, 362)], color="overlay", width=2.8)
    s.pill(855, 256, "Encrypted tunnel (CRM only)", fill="accent_card", color="overlay", line="accent_line")

    s.pill(772, 488, "Trusts verified identity + least-privilege policy", fill="card", color="good", line="good_line")

    return s


# ---------------------------------------------------------------------------
# 2. How "Dark" Services Stay Invisible (Outbound-Only)
# ---------------------------------------------------------------------------
def dark_services(t):
    s = Svg(
        1040, 480, t,
        "How Dark Services Stay Invisible with Outbound-Only Connections",
        "Your application never opens an inbound firewall port. Both the authorized user and the "
        "protected server dial outbound into the OpenZiti overlay, which stitches a private "
        "end-to-end encrypted connection between them.",
    )
    s.header(
        "How \"Dark\" Services Stay Invisible",
        "Your servers never open a public door. Both sides dial out to meet in the middle.",
    )

    # Left: Authorized user + Attacker
    s.card(36, 114, 238, 108, "Authorized Employee", [
        "Laptop or phone with",
        "verified OpenZiti identity",
        "(cryptographic key, not just a password)",
    ], tone="good")

    s.card(36, 304, 238, 104, "Internet Scanner / Attacker", [
        "Knocks on your server's IP",
        "Looking for open ports",
        "to attack or exploit",
    ], tone="bad")

    # Center: OpenZiti Overlay
    s.zone(366, 106, 292, 198, "OPENZITI OVERLAY (HARDENED ENTRY)", fill="accent_card", line="accent_line", label_color="overlay")
    s.card(390, 146, 244, 62, "1. Checks Identity & Policy", ["Only verified devices get past the door"], center=True)
    s.card(390, 224, 244, 62, "2. Stitches Encrypted Tunnel", ["End-to-end encrypted; zero trust"], center=True)

    # Right: Protected Server behind locked firewall
    s.zone(746, 106, 260, 316, "YOUR PRIVATE SERVER / CLOUD", fill="zone", line="zone_line")
    s.pill(876, 152, "Firewall: ALL INBOUND BLOCKED", fill="good_bg", color="good", line="good_line")
    s.card(770, 182, 212, 92, "Your App / Database", [
        "No public IP required",
        "No open listening port",
        "Dials OUTBOUND only",
    ], tone="accent")
    s.card(770, 300, 212, 96, "To the Public Internet:", [
        "Looks completely empty.",
        "Zero ports respond.",
        "Nothing to scan or DDoS.",
    ], tone="default")

    # Arrows
    s.arrow([(274, 168), (366, 168)], color="overlay", label="Dials out", at=(320, 144), width=2.6)
    s.arrow([(770, 228), (658, 228)], color="overlay", label="Dials out", at=(714, 204), width=2.6)

    # End-to-end highlight bar
    s.pill(512, 336, "End-to-end encrypted: even the network cannot read your data", fill="good_bg", color="good", line="good_line")

    # Blocked attacker arrow
    s.arrow([(274, 356), (722, 356)], color="bad", dashed=True, width=2.2)
    s.x_mark(736, 356, r=13)
    s.pill(512, 384, "Blocked at firewall — no open port exists to knock on", fill="bad_bg", color="bad", line="bad_line")

    # Bottom takeaway
    s.text(520, 452, "Analogy: Instead of posting your home address and leaving a lock on the door, you meet verified friends at a private club.",
           size=12.5, color="muted", weight=600, anchor="middle")
    return s


# ---------------------------------------------------------------------------
# 3. Stopping Lateral Movement (Least-Privilege Micro-Segmentation)
# ---------------------------------------------------------------------------
def least_privilege(t):
    s = Svg(
        1040, 500, t,
        "Stopping Lateral Movement with Least-Privilege Access",
        "Each person only sees and reaches the exact apps they need. If Maya's laptop is compromised, "
        "Payroll and Production Servers remain completely hidden and unreachable.",
    )
    s.header(
        "Stopping Lateral Movement (Zero Blast Radius)",
        "Even if one laptop is stolen or infected, the rest of the company stays invisible.",
    )

    # Left column: People
    s.zone(28, 94, 276, 372, "PEOPLE & DEVICES", fill="zone", line="zone_line")
    s.card(48, 134, 236, 90, "Maya · Sales", [
        "Role: #sales",
        "⚠ Laptop clicks phishing link",
    ], tone="warn")
    s.card(48, 244, 236, 90, "Sam · Finance", [
        "Role: #finance",
        "Trusted corporate laptop",
    ], tone="default")
    s.card(48, 354, 236, 90, "Alex · Engineering", [
        "Role: #engineers",
        "Trusted workstation",
    ], tone="default")

    # Middle: Policy Engine
    s.zone(384, 94, 260, 372, "OPENZITI POLICY RULES", fill="accent_card", line="accent_line", label_color="overlay")
    s.card(406, 146, 216, 66, "Rule 1: Sales → CRM", ["Only #sales can dial CRM"], tone="default", center=True)
    s.card(406, 256, 216, 66, "Rule 2: Finance → Payroll", ["Only #finance can dial Payroll"], tone="default", center=True)
    s.card(406, 366, 216, 66, "Rule 3: Eng → Prod", ["Only #engineers can dial Prod"], tone="default", center=True)

    # Right column: Services
    s.zone(724, 94, 288, 372, "PRIVATE SERVICES", fill="zone", line="zone_line")
    s.card(744, 134, 248, 90, "CRM Application", [
        "Reachable by Maya only",
        "Contained to 1 app",
    ], tone="warn")
    s.card(744, 244, 248, 90, "Payroll Database", [
        "Completely invisible to Maya",
        "Protected from breach",
    ], tone="good")
    s.card(744, 354, 248, 90, "Production Servers", [
        "Completely invisible to Maya",
        "Protected from breach",
    ], tone="good")

    # Allowed paths
    s.arrow([(284, 179), (406, 179)], color="overlay", width=2.4)
    s.arrow([(622, 179), (744, 179)], color="overlay", width=2.4)

    s.arrow([(284, 289), (406, 289)], color="good", width=2.4)
    s.arrow([(622, 289), (744, 289)], color="good", width=2.4)

    s.arrow([(284, 399), (406, 399)], color="good", width=2.4)
    s.arrow([(622, 399), (744, 399)], color="good", width=2.4)

    # Blocked lateral attempt from Maya to Payroll
    s.arrow([(284, 204), (346, 246)], color="bad", dashed=True, width=2)
    s.x_mark(354, 252, r=10)
    s.text(354, 224, "Blocked", size=11, color="bad", weight=700, anchor="middle")

    # Check marks on protected services
    s.check_mark(976, 260, r=10)
    s.check_mark(976, 370, r=10)

    return s


# ---------------------------------------------------------------------------
# 4. Works Anywhere Without a VPN Bottleneck
# ---------------------------------------------------------------------------
def everywhere_no_vpn(t):
    s = Svg(
        1040, 500, t,
        "Traditional VPN Hairpin vs. OpenZiti Direct Mesh",
        "A traditional VPN forces all remote traffic through one central office gateway, creating "
        "lag and disconnects. OpenZiti routes each user directly to the nearest overlay router and "
        "straight to any cloud or office resource.",
    )
    s.header(
        "Works Anywhere — Without the VPN Bottleneck",
        "No more \"please connect to the VPN\", dropped video calls, or slow central gateways.",
    )

    # Top row: Traditional VPN
    s.zone(28, 94, 984, 172, "TRADITIONAL VPN: EVERY REQUEST DETOURS THROUGH ONE CHOKE POINT", fill="bad_bg", line="bad_line", label_color="bad")
    s.card(52, 136, 200, 102, "Remote Worker", ["Home, hotel, or coffee shop", "Manual VPN login", "Drops on Wi-Fi switch"], tone="default")
    s.card(390, 136, 240, 102, "Office VPN Gateway", ["Single bottleneck & target", "Slow hairpin routing", "Overloaded at peak hours"], tone="bad")
    s.card(772, 136, 216, 102, "Cloud App (AWS / OCI)", ["Traffic goes to office first,", "then out to the cloud,", "then back again!"], tone="default")

    s.arrow([(252, 187), (390, 187)], color="bad", label="Slow detour", at=(321, 165), both=True)
    s.arrow([(630, 187), (772, 187)], color="bad", label="Hairpin hop", at=(701, 165), both=True)

    # Bottom row: OpenZiti
    s.zone(28, 290, 984, 184, "OPENZITI: ALWAYS-ON, FASTEST PATH TO EVERY CLOUD & OFFICE", fill="good_bg", line="good_line", label_color="good")
    s.card(52, 338, 200, 110, "Remote Worker", ["Always-on in background", "Zero VPN popups", "Survives Wi-Fi ↔ 5G"], tone="good")
    s.card(366, 338, 224, 110, "OpenZiti Mesh", ["Smartest, fastest route", "Multi-cloud & on-prem", "Self-healing paths"], tone="accent")

    s.card(714, 326, 274, 42, "Cloud Apps (AWS / Azure / OCI)", [], tone="default", title_size=13)
    s.card(714, 376, 274, 42, "Office & On-Prem Servers", [], tone="default", title_size=13)
    s.card(714, 426, 274, 42, "Home Lab / Edge Devices", [], tone="default", title_size=13)

    s.arrow([(252, 393), (366, 393)], color="overlay", label="Direct", at=(309, 370), both=True, width=2.6)
    s.arrow([(590, 368), (714, 347)], color="overlay", width=2.2)
    s.arrow([(590, 393), (714, 397)], color="overlay", width=2.2)
    s.arrow([(590, 418), (714, 447)], color="overlay", width=2.2)

    return s


# ---------------------------------------------------------------------------
# 5. Two Easy Ways to Adopt OpenZiti
# ---------------------------------------------------------------------------
def adoption_paths(t):
    s = Svg(
        1040, 460, t,
        "Two Easy Ways to Adopt OpenZiti",
        "Organizations can start today with zero code changes using drop-in OpenZiti tunnelers, "
        "and later embed the OpenZiti SDK directly inside critical applications for the strongest "
        "application-level zero trust.",
    )
    s.header(
        "Adopt at Your Own Pace — No \"Big Bang\" Rewrite",
        "Start protecting existing apps in minutes, then embed zero trust directly into new software.",
    )

    # Step 1
    s.zone(28, 96, 476, 332, "STEP 1 · START TODAY (ZERO CODE CHANGES)", fill="zone", line="zone_line", label_color="ink")
    s.pill(144, 146, "Drop-In Tunnelers", fill="badge", color="badge_ink")
    s.card(52, 174, 180, 96, "User Device", ["OpenZiti Desktop", "or Mobile Edge app", "(just like a normal app)"], tone="good")
    s.card(298, 174, 182, 96, "Existing Server", ["Lightweight tunneler", "sits next to your app", "No code changes"], tone="accent")
    s.arrow([(232, 222), (298, 222)], color="overlay", width=2.6)

    s.card(52, 294, 428, 110, "Best for Immediate Wins", [
        "• Legacy web apps, databases, SSH, RDP, and internal dashboards",
        "• Turn off public inbound ports and retire legacy VPNs right away",
        "• Works across AWS, Azure, OCI, on-prem, and home labs",
    ], tone="default", title_size=13.5)

    # Progression arrow between cards
    s.arrow([(504, 260), (536, 260)], color="overlay", width=2.8)

    # Step 2
    s.zone(536, 96, 476, 332, "STEP 2 · GO FURTHER (EMBEDDED IN YOUR APP)", fill="good_bg", line="good_line", label_color="good")
    s.pill(670, 146, "OpenZiti SDK Inside Code", fill="card", color="good", line="good_line")
    s.card(560, 174, 180, 96, "User or Service", ["Browser, mobile app,", "or microservice with", "OpenZiti identity"], tone="good")
    s.card(806, 174, 182, 96, "Zero-Trust App", ["OpenZiti SDK built in", "(Java, Go, Python, C...)", "Zero open local ports"], tone="good")
    s.arrow([(740, 222), (806, 222)], color="overlay", width=2.6)

    s.card(560, 294, 428, 110, "Best for Crown-Jewel & New Apps", [
        "• The app itself is dark — not even a local port on the server",
        "• App-to-app encryption from the code inside one app to the next",
        "• See it live in Baked Pasta's zt-app Spring Boot demo!",
    ], tone="default", title_size=13.5)

    return s


DIAGRAMS = {
    "why-castle-vs-zero-trust": castle_vs_zero_trust,
    "why-dark-services": dark_services,
    "why-least-privilege": least_privilege,
    "why-everywhere-no-vpn": everywhere_no_vpn,
    "why-adoption-paths": adoption_paths,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in DIAGRAMS.items():
        fn(THEMES["light"]).save(OUT / f"{name}.svg")
        fn(THEMES["dark"]).save(OUT / f"{name}-on-dark.svg")
        print(f"wrote {name}.svg and {name}-on-dark.svg")


if __name__ == "__main__":
    main()
