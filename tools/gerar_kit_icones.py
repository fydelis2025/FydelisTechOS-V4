#!/usr/bin/env python3
"""
FydelisTech OS v4.2 — Gerador do Pacote Completo de Ícones SVG (Cyberpunk Neon)
Gera 16 ícones padronizados 64x64 em assets/icones/ com alto contraste sobre fundo roxo.
"""
import os

PASTA_SAIDA = "assets/icones"

PALETAS = {
    "ciano":  ("#F8FAFC", "#00F5D4", "#00BBF9"),
    "verde":  ("#F8FAFC", "#00FF9C", "#00F5D4"),
    "coral":  ("#F8FAFC", "#FF4D6D", "#FF758F"),
    "branco": ("#F8FAFC", "#CBD5E1", "#00F5D4"),
}

ICONES = {
    "ethernet": ("ciano", """
        <rect x="8" y="12" width="48" height="36" rx="8" stroke="url(#grad)" stroke-width="5"/>
        <line x1="18" y1="22" x2="18" y2="32" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="27" y1="22" x2="27" y2="32" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="37" y1="22" x2="37" y2="32" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="46" y1="22" x2="46" y2="32" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="21" y1="48" x2="21" y2="55" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <line x1="43" y1="48" x2="43" y2="55" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
    """),
    "wifi": ("ciano", """
        <path d="M8 24C21.5 12 42.5 12 56 24" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <path d="M16 34C25 26 39 26 48 34" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <path d="M24 43C28.5 39 35.5 39 40 43" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <circle cx="32" cy="51" r="3.5" fill="url(#grad)"/>
    """),
    "bluetooth": ("ciano", """
        <polyline points="20,20 44,44 32,56 32,8 44,20 20,44" stroke="url(#grad)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    """),
    "terminal": ("verde", """
        <rect x="8" y="12" width="48" height="40" rx="8" stroke="url(#grad)" stroke-width="5"/>
        <polyline points="18,25 27,32 18,39" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
        <line x1="33" y1="39" x2="46" y2="39" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
    """),
    "pasta_fechada": ("ciano", """
        <path d="M8 20C8 15.6 11.6 12 16 12H26L32 18H48C52.4 18 56 21.6 56 26V46C56 50.4 52.4 54 48 54H16C11.6 54 8 50.4 8 46V20Z" stroke="url(#grad)" stroke-width="5" stroke-linejoin="round"/>
        <line x1="16" y1="28" x2="48" y2="28" stroke="url(#grad)" stroke-width="3.5" stroke-linecap="round"/>
    """),
    "pasta_aberta": ("verde", """
        <path d="M8 22C8 17.6 11.6 14 16 14H25L30 19H46C50.4 19 54 22.6 54 27V30" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
        <path d="M8 30H56L51 50C50.3 52.4 48.2 54 45.7 54H14.3C11.8 54 9.7 52.4 9 50L8 30Z" stroke="url(#grad)" stroke-width="5" stroke-linejoin="round"/>
    """),
    "arquivo": ("branco", """
        <path d="M16 8H38L50 20V50C50 53.3 47.3 56 44 56H16C12.7 56 10 53.3 10 50V14C10 10.7 12.7 8 16 8Z" stroke="url(#grad)" stroke-width="4.5" stroke-linejoin="round"/>
        <polyline points="37,8 37,21 50,21" stroke="url(#grad)" stroke-width="4.5" stroke-linejoin="round"/>
        <line x1="20" y1="32" x2="40" y2="32" stroke="url(#grad)" stroke-width="4" stroke-linecap="round"/>
        <line x1="20" y1="42" x2="34" y2="42" stroke="url(#grad)" stroke-width="4" stroke-linecap="round"/>
    """),
    "agenda": ("ciano", """
        <rect x="10" y="14" width="44" height="42" rx="7" stroke="url(#grad)" stroke-width="5"/>
        <line x1="10" y1="26" x2="54" y2="26" stroke="url(#grad)" stroke-width="4.5"/>
        <line x1="22" y1="8" x2="22" y2="18" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <line x1="42" y1="8" x2="42" y2="18" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <circle cx="22" cy="36" r="2.8" fill="url(#grad)"/>
        <circle cx="32" cy="36" r="2.8" fill="url(#grad)"/>
        <circle cx="42" cy="36" r="2.8" fill="url(#grad)"/>
        <circle cx="22" cy="46" r="2.8" fill="url(#grad)"/>
        <circle cx="32" cy="46" r="2.8" fill="url(#grad)"/>
    """),
    "relogio": ("verde", """
        <circle cx="32" cy="32" r="23" stroke="url(#grad)" stroke-width="5"/>
        <polyline points="32,18 32,32 42,38" stroke="url(#grad)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    """),
    "video": ("ciano", """
        <rect x="8" y="16" width="34" height="32" rx="6" stroke="url(#grad)" stroke-width="5"/>
        <polygon points="42,26 56,18 56,46 42,38" stroke="url(#grad)" stroke-width="4.5" stroke-linejoin="round"/>
        <polygon points="22,26 32,32 22,38" fill="url(#grad)"/>
    """),
    "imagem": ("verde", """
        <rect x="8" y="12" width="48" height="40" rx="7" stroke="url(#grad)" stroke-width="5"/>
        <circle cx="21" cy="24" r="4" fill="url(#grad)"/>
        <polyline points="12,46 25,33 34,42 42,35 52,46" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
    """),
    "sistema": ("ciano", """
        <rect x="16" y="16" width="32" height="32" rx="6" stroke="url(#grad)" stroke-width="5"/>
        <rect x="25" y="25" width="14" height="14" rx="2" stroke="url(#grad)" stroke-width="4"/>
        <line x1="24" y1="8" x2="24" y2="15" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="40" y1="8" x2="40" y2="15" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="24" y1="49" x2="24" y2="56" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="40" y1="49" x2="40" y2="56" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="8" y1="24" x2="15" y2="24" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="8" y1="40" x2="15" y2="40" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="49" y1="24" x2="56" y2="24" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
        <line x1="49" y1="40" x2="56" y2="40" stroke="url(#grad)" stroke-width="4.5" stroke-linecap="round"/>
    """),
    "config": ("branco", """
        <circle cx="32" cy="32" r="10" stroke="url(#grad)" stroke-width="5"/>
        <path d="M32 8V14M32 50V56M8 32H14M50 32H56M15 15L19 19M45 45L49 49M49 15L45 19M19 45L15 49" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
    """),
    "iniciar": ("ciano", """
        <rect x="10" y="10" width="18" height="18" rx="4" stroke="url(#grad)" stroke-width="4.5"/>
        <rect x="36" y="10" width="18" height="18" rx="4" stroke="url(#grad)" stroke-width="4.5"/>
        <rect x="10" y="36" width="18" height="18" rx="4" stroke="url(#grad)" stroke-width="4.5"/>
        <rect x="36" y="36" width="18" height="18" rx="4" stroke="url(#grad)" stroke-width="4.5"/>
    """),
    "bloquear": ("branco", """
        <rect x="14" y="28" width="36" height="26" rx="7" stroke="url(#grad)" stroke-width="5"/>
        <path d="M22 28V20C22 14.5 26.5 10 32 10C37.5 10 42 14.5 42 20V28" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <circle cx="32" cy="39" r="3" fill="url(#grad)"/>
        <line x1="32" y1="42" x2="32" y2="47" stroke="url(#grad)" stroke-width="4" stroke-linecap="round"/>
    """),
    "desligar": ("coral", """
        <line x1="32" y1="10" x2="32" y2="30" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
        <path d="M20 17C14 21 11 28 12 36C14 46 22 54 32 54C42 54 50 46 52 36C53 28 50 21 44 17" stroke="url(#grad)" stroke-width="5" stroke-linecap="round"/>
    """),
}

TEMPLATE = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="none">
  <defs>
    <linearGradient id="grad" x1="8" y1="8" x2="56" y2="56" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="{c0}"/>
      <stop offset="50%" stop-color="{c1}"/>
      <stop offset="100%" stop-color="{c2}"/>
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="2.0" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  <g filter="url(#glow)">{corpo}
  </g>
</svg>
"""

def main():
    os.makedirs(PASTA_SAIDA, exist_ok=True)
    for nome, (paleta, corpo) in ICONES.items():
        c0, c1, c2 = PALETAS[paleta]
        svg_final = TEMPLATE.format(c0=c0, c1=c1, c2=c2, corpo=corpo)
        caminho = os.path.join(PASTA_SAIDA, f"{nome}.svg")
        with open(caminho, "w", encoding="utf-8") as f:
            f.write(svg_final)
    print(f"[OK] {len(ICONES)} ícones SVG gerados em {PASTA_SAIDA}/")

if __name__ == "__main__":
    main()
