import os
import sys
import struct
from PIL import Image, ImageDraw

BG_W, BG_H = 640, 512
SETOR_BYTES = 512
SETORES_POR_IMG = (BG_W * BG_H * 4) // SETOR_BYTES  # 2560 setores (1.25 MB)

RAIZ_PROJETO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DIR_IMAGENS  = os.path.join(RAIZ_PROJETO, "assets", "images")

# Caminho padrão da imagem de disco (ou passe via argumento na linha de comando)
IMAGEM_DISCO = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RAIZ_PROJETO, "fydelistech.img")

MAPA_LBA = [
    ("splash.png",  2048),
    ("login.png",   4608),
    ("desktop.png", 7168),
]

def gerar_fallback():
    img = Image.new("RGBA", (BG_W, BG_H), (18, 8, 38, 255))
    draw = ImageDraw.Draw(img)
    for y in range(0, BG_H, 32):
        draw.line([(0, y), (BG_W, y)], fill=(50, 22, 95, 255), width=1)
    for x in range(0, BG_W, 32):
        draw.line([(x, 0), (x, BG_H)], fill=(50, 22, 95, 255), width=1)
    return img

if not os.path.exists(IMAGEM_DISCO):
    print(f"[ERRO] Imagem de disco nao encontrada: {IMAGEM_DISCO}")
    print("Uso: python3 tools/gravar_wallpapers_disco.py caminho/para/seu_disco.img")
    sys.exit(1)

tamanho_minimo = (7168 + SETORES_POR_IMG) * SETOR_BYTES
tamanho_atual = os.path.getsize(IMAGEM_DISCO)
if tamanho_atual < tamanho_minimo:
    print(f"[INFO] Expandindo imagem de disco de {tamanho_atual} para {tamanho_minimo} bytes...")
    with open(IMAGEM_DISCO, "ab") as f:
        f.truncate(tamanho_minimo)

with open(IMAGEM_DISCO, "r+b") as disco:
    for nome_arq, lba_inicial in MAPA_LBA:
        caminho_img = os.path.join(DIR_IMAGENS, nome_arq)
        if os.path.exists(caminho_img):
            img = Image.open(caminho_img).convert("RGBA").resize((BG_W, BG_H), Image.Resampling.LANCZOS)
            print(f"[OK] {nome_arq} -> LBA {lba_inicial} ({SETORES_POR_IMG} setores)")
        else:
            img = gerar_fallback()
            print(f"[AVISO] {nome_arq} nao encontrado -> gravando fallback no LBA {lba_inicial}")

        raw_pixels = bytearray(BG_W * BG_H * 4)
        idx = 0
        for r, g, b, _ in img.getdata():
            pixel = 0xFF000000 | (r << 16) | (g << 8) | b
            struct.pack_into("<I", raw_pixels, idx, pixel)
            idx += 4

        disco.seek(lba_inicial * SETOR_BYTES)
        disco.write(raw_pixels)

print("Wallpapers gravados no disco ATA com sucesso!")
