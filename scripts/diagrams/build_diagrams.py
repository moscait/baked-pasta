"""Build the README architecture diagrams as light and dark SVGs.

The README shows them with <picture>/prefers-color-scheme, the same way as the logo, so
GitHub picks the variant that matches the viewer's theme. The SVGs are self-contained (no
web fonts, scripts or external references), which GitHub's image proxy requires.
Usage, from the repo root:

    python3 scripts/diagrams/build_diagrams.py
"""
from html import escape
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent.parent / "assets" / "diagrams"

SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, monospace"

# Brand palette from scripts/logo/build_logo.py (green, tomato, gold, cream).
THEMES = {
    "light": dict(
        bg="#FFFDF9", zone="#F6ECDC", zone_line="#E3D3B8", inner="#FBF5EA", inner_line="#D9C7A6",
        card="#FFFFFF", card_line="#CDBFA6", ink="#14302B", muted="#5E6E69",
        http="#3E5A54", overlay="#D9481C", badge="#FBE3A6", badge_ink="#14302B",
        accent_card="#FFF4E8", accent_line="#E9A27F",
    ),
    "dark": dict(
        bg="#0F1A18", zone="#15241F", zone_line="#2A3F39", inner="#1A2C27", inner_line="#35504A",
        card="#1E322C", card_line="#3D5A53", ink="#F6ECDC", muted="#A8B8B2",
        http="#9FC2B8", overlay="#FF7A4D", badge="#3B3220", badge_ink="#FBE3A6",
        accent_card="#2A211B", accent_line="#9A4A2C",
    ),
}


class Svg:
    def __init__(self, w, h, t, title, desc):
        self.w, self.h, self.t = w, h, t
        self.parts = []
        self.head = (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
            f'role="img" aria-labelledby="t d" font-family="{SANS}">\n'
            f'<title id="t">{escape(title)}</title>\n<desc id="d">{escape(desc)}</desc>\n'
            "<defs>\n"
            + "".join(
                f'<marker id="arr-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                f'orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="{t[k]}"/></marker>\n'
                for k in ("http", "overlay")
            )
            + "</defs>\n"
            f'<rect width="{w}" height="{h}" rx="14" fill="{t["bg"]}"/>\n'
        )

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=13, color="ink", weight=400, anchor="start", mono=False, spacing=None):
        fam = f' font-family="{MONO}"' if mono else ""
        ls = f' letter-spacing="{spacing}"' if spacing else ""
        self.add(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{self.t[color]}" '
                 f'text-anchor="{anchor}"{fam}{ls}>{escape(s)}</text>')

    def zone(self, x, y, w, h, label, fill="zone", line="zone_line", dashed=False, label_x=20):
        dash = ' stroke-dasharray="6 5"' if dashed else ""
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" fill="{self.t[fill]}" '
                 f'stroke="{self.t[line]}" stroke-width="1.5"{dash}/>')
        self.text(x + label_x, y + 26, label, size=11.5, color="muted", weight=700, spacing="0.08em")

    def card(self, x, y, w, h, title, lines=(), badges=(), accent=False, mono_title=True):
        fill, line = ("accent_card", "accent_line") if accent else ("card", "card_line")
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{self.t[fill]}" '
                 f'stroke="{self.t[line]}" stroke-width="1.5"/>')
        self.text(x + 16, y + 26, title, size=15, weight=650, mono=mono_title)
        for i, ln in enumerate(lines):
            self.text(x + 16, y + 47 + i * 18, ln, size=12.5, color="muted")
        bx = x + 16
        by = y + h - 30
        for b in badges:
            bw = round(len(b) * 7.0 + 16)
            self.add(f'<rect x="{bx}" y="{by}" width="{bw}" height="20" rx="10" fill="{self.t["badge"]}"/>')
            self.text(bx + bw / 2, by + 14, b, size=11.5, color="badge_ink", weight=600, anchor="middle", mono=True)
            bx += bw + 6

    def arrow(self, pts, kind="http", label=None, at=None, both=False, dashed=False):
        d = "M" + " L".join(f"{x} {y}" for x, y in pts)
        start = f' marker-start="url(#arr-{kind})"' if both else ""
        dash = ' stroke-dasharray="5 4"' if dashed else ""
        self.add(f'<path d="{d}" fill="none" stroke="{self.t[kind]}" stroke-width="2" stroke-linejoin="round"'
                 f'{dash} marker-end="url(#arr-{kind})"{start}/>')
        if label:
            lx, ly = at
            lw = round(len(label) * 6.6 + 14)
            self.add(f'<rect x="{lx - lw / 2}" y="{ly - 11}" width="{lw}" height="20" rx="10" fill="{self.t["bg"]}" '
                     f'stroke="{self.t[kind]}" stroke-width="1"/>')
            self.text(lx, ly + 3.5, label, size=11.5, color=kind, weight=600, anchor="middle")

    def legend(self, x, y):
        for i, (kind, label) in enumerate((("http", "HTTP(S)"), ("overlay", "OpenZiti mTLS overlay"))):
            ox = x + i * 110
            self.add(f'<line x1="{ox}" y1="{y}" x2="{ox + 26}" y2="{y}" stroke="{self.t[kind]}" stroke-width="2.5"/>')
            self.text(ox + 34, y + 4, label, size=12, color="muted", weight=600)

    def save(self, path):
        path.write_text(self.head + "\n".join(self.parts) + "\n</svg>\n", encoding="utf-8")


def sandbox(t):
    s = Svg(960, 640, t, "Configuration 1: all-local containerized sandbox",
            "A browser and the OpenZiti Desktop Edge client on the workstation reach containers over 127.0.0.1. "
            "The menu nginx container serves the portal and Admin Console and proxies to the app and controller. "
            "zt-app binds a dark service through the controller's edge router; ziti-setup provisions services, "
            "policies and identities.")
    s.text(32, 42, "Configuration 1 · All-local sandbox", size=19, weight=700)
    s.text(32, 63, "Everything runs in local containers. Every published port is bound to 127.0.0.1.",
           size=12.5, color="muted")
    s.legend(624, 46)

    s.zone(24, 84, 912, 532, "YOUR WORKSTATION")
    s.card(48, 120, 300, 74, "Web browser", ["menu.local · app.local · zt.local via /etc/hosts"], mono_title=False)
    s.card(612, 120, 300, 74, "OpenZiti Desktop Edge", ["Enrolled with zt-host-client.jwt"], mono_title=False)

    s.zone(44, 228, 872, 368, "DOCKER / PODMAN COMPOSE NETWORK", fill="inner", line="inner_line", dashed=True, label_x=178)
    s.card(68, 268, 260, 90, "menu", ["nginx: portal, ZAC, proxy"], [":8080", ":8443"])
    s.card(350, 268, 260, 90, "app", ["Spring Boot + Vaadin (plain HTTP)"], [":8082"])
    s.card(632, 268, 260, 90, "dns-server", ["Local DNS proxy"], [":5300/udp"])
    s.card(68, 400, 260, 90, "ziti-controller", ["Controller + edge router"], [":1280", ":8444"])
    s.card(350, 400, 260, 90, "ziti-setup", ["One-shot: services, policies,", "identities, TLS certificate"])
    s.card(632, 400, 260, 90, "zt-app", ["OpenZiti Java SDK"], ["no open port"], accent=True)

    s.add(f'<rect x="68" y="530" width="824" height="44" rx="10" fill="none" stroke="{t["inner_line"]}" '
          f'stroke-width="1.5" stroke-dasharray="4 4"/>')
    s.text(88, 557, "Shared volumes: controller PKI · app identity · enrollment token · self-signed TLS cert · setup log",
           size=12.5, color="muted")

    s.arrow([(198, 194), (198, 268)], "http", "HTTP / HTTPS", (198, 210))
    s.arrow([(328, 313), (350, 313)], "http")
    s.arrow([(198, 358), (198, 400)], "http", "/edge API", (198, 379))
    s.arrow([(350, 445), (328, 445)], "http")
    s.arrow([(640, 194), (640, 252), (621, 252), (621, 379), (290, 379), (290, 400)], "overlay",
            "dials zt-app-secure-ui", (470, 379))
    s.arrow([(762, 490), (762, 510), (250, 510), (250, 490)], "overlay", "binds the service (outbound)", (506, 510))
    return s


def routable(t):
    s = Svg(1000, 770, t, "Configuration 2: routable OpenZiti infrastructure",
            "Administrators reach the Admin Console through Cloudflare Access and an outbound Cloudflare Tunnel; "
            "no inbound web port is open on the Linux host. Ziti endpoints and application workloads connect "
            "directly to the controller and edge router over mTLS on ports 1280 and 8444, found through a "
            "DNS-only record. The management API on 1281 is reachable only inside the container network.")
    s.text(32, 42, "Configuration 2 · Routable infrastructure", size=19, weight=700)
    s.text(32, 63, "No inbound web ports: the console comes in through an outbound tunnel; only OpenZiti mTLS is open.",
           size=12.5, color="muted")
    s.legend(664, 46)

    s.card(40, 96, 300, 76, "Administrator browser", ["https://zt.example.com"], mono_title=False)
    s.card(660, 96, 300, 76, "Ziti endpoints", ["iPhone, Android, laptops with Ziti Edge"], mono_title=False)

    s.card(40, 212, 420, 96, "Cloudflare edge", ["Access policy: SSO or email one-time PIN", "Tunnel ingress for zt.example.com"],
           mono_title=False)
    s.card(540, 212, 300, 96, "Public DNS (DNS-only record)", ["ziti.example.com → host public IP",
                                                              "kept current by openziti-ddns"], mono_title=False)

    s.zone(24, 352, 952, 262, "LINUX HOST (FEDORA / UBUNTU) · INBOUND: 22, 1280, 8444 ONLY", label_x=264)
    s.card(56, 400, 200, 92, "cloudflared", ["Outbound QUIC/TLS tunnel"])
    s.card(288, 400, 220, 92, "openziti-console", ["nginx + Admin Console"], ["127.0.0.1:8080"])
    s.card(540, 400, 404, 100, "ziti-controller", ["Controller + edge router (quickstart, automatic PKI)"],
           [":1280 client", ":8444 router", ":1281 mgmt (internal)"])
    s.card(56, 524, 200, 72, "openziti-ddns", ["Optional · updates the A record"])
    s.text(288, 548, "The management API (1281) is never", size=12.5, color="muted")
    s.text(288, 566, "published on the host; only the", size=12.5, color="muted")
    s.text(288, 584, "console reaches it.", size=12.5, color="muted")

    s.card(40, 662, 920, 84, "Application workloads", [
        "Containers on your workstation, servers in other clouds, edge devices",
        "Embedded OpenZiti SDK or tunneler · no inbound ports needed"], mono_title=False)

    s.arrow([(190, 172), (190, 212)], "http", "HTTPS", (190, 192))
    s.arrow([(156, 400), (156, 308)], "http", "outbound tunnel", (156, 352), both=True)
    s.arrow([(256, 446), (288, 446)], "http")
    s.arrow([(508, 446), (540, 446)], "http")
    s.arrow([(720, 172), (720, 212)], "http", "resolve", (720, 192), dashed=True)
    s.arrow([(900, 172), (900, 400)], "overlay", "mTLS :1280 / :8444", (888, 330))
    s.arrow([(740, 662), (740, 500)], "overlay", "outbound mTLS :8444", (740, 640))
    return s


def cloudflare(t):
    s = Svg(1000, 560, t, "Cloudflare routing: two hostnames, two paths",
            "zt.example.com is a proxied record: the administrator's browser passes Cloudflare Access, then the "
            "tunnel that cloudflared dials outbound, to nginx on 127.0.0.1:8080, which serves the Admin Console at / "
            "and proxies /edge/ to the internal management API on 1281. ziti.example.com is a DNS-only record: "
            "Ziti endpoints connect straight to the host over mTLS, TCP 1280 for the controller and 8444 for the "
            "edge router.")
    s.text(32, 42, "Cloudflare routing · two hostnames, two paths", size=19, weight=700)
    s.text(32, 63, "The console hostname goes through Cloudflare Access; the overlay hostname is DNS-only.",
           size=12.5, color="muted")
    s.legend(664, 46)

    s.zone(24, 84, 952, 204, "ADMIN CONSOLE · zt.example.com (PROXIED CNAME)")
    s.card(48, 124, 180, 140, "Admin browser", ["HTTPS to", "zt.example.com"], mono_title=False)
    s.card(260, 124, 200, 140, "Cloudflare edge", ["Access: SSO or", "email one-time PIN", "Tunnel ingress"],
           mono_title=False)
    s.card(492, 124, 180, 140, "cloudflared", ["Host network", "Dials Cloudflare", "outbound (QUIC/TLS)"])
    s.card(704, 124, 248, 140, "openziti-console", ["nginx on 127.0.0.1:8080", "/        → Admin Console UI",
                                                    "/edge/  → controller :1281", "(internal management API)"])
    s.arrow([(228, 194), (260, 194)], "http")
    s.arrow([(492, 194), (460, 194)], "http", both=True)
    s.arrow([(672, 194), (704, 194)], "http")

    s.zone(24, 308, 952, 228, "OPENZITI OVERLAY · ziti.example.com (DNS-ONLY A RECORD)")
    s.card(48, 348, 210, 164, "iPhone / remote app", ["Ziti Edge app or", "embedded SDK"], mono_title=False)
    s.card(290, 348, 220, 164, "ziti.example.com", ["DNS-only (grey cloud)", "A record → host public IP",
                                                    "Not proxied by Cloudflare"])
    s.card(582, 348, 370, 76, "ziti-controller :1280", ["Edge client API, OIDC, control plane only"])
    s.card(582, 436, 370, 76, "edge router :8444", ["Router integrated with the controller"])
    s.arrow([(258, 430), (290, 430)], "overlay")
    s.arrow([(510, 386), (582, 386)], "overlay", "TCP 1280", (546, 386))
    s.arrow([(510, 474), (582, 474)], "overlay", "TCP 8444", (546, 474))
    return s


def oracle(t):
    s = Svg(1000, 520, t, "Oracle Cloud host",
            "An Always Free Oracle Cloud instance with a reserved public IP. The VCN security list admits SSH only "
            "from your IP and OpenZiti mTLS on 1280 and 8444 from anywhere. The administrator reaches the console "
            "through Cloudflare Access and a tunnel the instance dials outbound. deploy-ziti.sh installs the host "
            "firewall, container engine and OpenZiti.")
    s.text(32, 42, "Oracle Cloud host", size=19, weight=700)
    s.text(32, 63, "Always Free instance; the security list admits only SSH from your IP and OpenZiti mTLS.",
           size=12.5, color="muted")
    s.legend(664, 46)

    s.card(40, 96, 240, 64, "Admin browser", ["HTTPS to the console"], mono_title=False)
    s.card(330, 96, 300, 64, "Cloudflare Access + Tunnel", ["SSO or email one-time PIN"], mono_title=False)
    s.card(40, 250, 220, 72, "Ziti clients", ["Phones, laptops, workloads"], mono_title=False)
    s.card(40, 370, 220, 72, "You", ["Operator workstation"], mono_title=False)

    s.zone(330, 190, 646, 306, "ORACLE CLOUD · VCN")
    s.card(356, 232, 210, 236, "Security list", ["22/tcp ← your IP /32", "1280/tcp ← anywhere",
                                                 "8444/tcp ← anywhere", "ICMP (path MTU)", "Everything else denied"],
           mono_title=False)
    s.card(600, 232, 352, 236, "Linux instance", ["Ubuntu or Oracle Linux · reserved public IP", "",
                                                  "deploy-ziti.sh installs:", "· host firewall (ufw / firewalld)",
                                                  "· Docker or Podman", "· OpenZiti controller, router, console",
                                                  "· cloudflared"], mono_title=False, accent=True)

    s.arrow([(280, 128), (330, 128)], "http")
    s.arrow([(790, 232), (790, 128), (630, 128)], "http", "outbound tunnel", (790, 172), both=True)
    s.arrow([(260, 286), (356, 286)], "overlay", "1280 / 8444", (308, 286))
    s.arrow([(566, 286), (600, 286)], "overlay")
    s.arrow([(260, 406), (356, 406)], "http", "SSH 22", (308, 406))
    s.arrow([(566, 406), (600, 406)], "http")
    return s


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in (("sandbox", sandbox), ("routable", routable), ("cloudflare-routing", cloudflare),
                        ("oracle-cloud", oracle)):
        for theme, t in THEMES.items():
            suffix = "" if theme == "light" else "-on-dark"
            build(t).save(OUT / f"{name}{suffix}.svg")
    print(f"Wrote diagrams to {OUT}")


if __name__ == "__main__":
    main()
