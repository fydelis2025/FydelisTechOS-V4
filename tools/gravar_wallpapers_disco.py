#!/usr/bin/env python3
import sys, os, struct
from PIL import Image

BG_W, BG_H = 640, 512
SETOR_TAM = 512
WALLPAPERS = [
    ("splash",  8192),
    ("login",   10752),
    ("desktop", 13312),
]

def converter_imagem(caminho):
    img = Image.open(caminho).convert("RGBA").resize((BG_W, BG_H), Image.Resampling.LANCZOS)
    dados = bytearray(BG_W * BG_H * 4)
    pixels = img.load()
    idx = 0
    for y in range(BG_H):
        for x in range(BG_W):
            r, g, b, a = pixels[x, y]
            dados[idx:idx+4] = struct.pack("<I", (a << 24) | (r << 16) | (g << 8) | b)
            idx += 4
    return dados

def main():
    disco = sys.argv[1]
    pasta_imgs = sys.argv[2] if len(sys.argv) > 2 else "../assets/images"
    tam_minimo = (13312 + 2560) * SETOR_TAM
    if os.path.getsize(disco) < tam_minimo:
        with open(disco, "r+b") as f:
            f.truncate(tam_minimo)

    with open(disco, "r+b") as f:
        for nome, lba in WALLPAPERS:
            arq = os.path.join(pasta_imgs, nome + ".png")
            if not os.path.exists(arq):
                print(f"[ERRO] Nao encontrado: {arq}")
                sys.exit(1)
            raw = converter_imagem(arq)
            f.seek(lba * SETOR_TAM)
            f.write(raw)
            print(f"[OK] {arq} -> LBA {lba}")

if __name__ == "__main__":
    main()
