#!/usr/bin/env python3
import struct
import sys
import os

FYD_EXEC_MAGIC = 0x31445946  # "FYD1"
FYD_PKG_MAGIC  = 0x474B5046  # "FPKG"

def criar_fyd(bin_path, out_path, nome_app, tipo_app=1, entry_offset=0, bss_size=0):
    with open(bin_path, "rb") as f:
        codigo = f.read()

    nome_bytes = nome_app.encode("utf-8")[:31].ljust(32, b"\x00")
    header = struct.pack(
        "<IHHQQQI32s",
        FYD_EXEC_MAGIC,
        0x0402,        # FydelisTech OS v4.2
        tipo_app,      # 0 = CLI, 1 = GUI
        entry_offset,
        len(codigo),
        bss_size,
        0,             # CRC32 reservado
        nome_bytes
    )

    with open(out_path, "wb") as f:
        f.write(header + codigo)
    print(f"[OK] Executavel nativo criado: {out_path} ({len(header) + len(codigo)} bytes)")

def criar_fpkg(out_path, pacote_id, categoria, arquivos_destino):
    """arquivos_destino: lista de tuplas (arquivo_local, caminho_no_fyd_os)"""
    payload = b""
    for local_path, destino_os in arquivos_destino:
        with open(local_path, "rb") as f:
            dados = f.read()
        dest_bytes = destino_os.encode("utf-8")[:63].ljust(64, b"\x00")
        entry_hdr = struct.pack("<64sII", dest_bytes, len(dados), 0x05)
        payload += entry_hdr + dados

    pkg_id_bytes = pacote_id.encode("utf-8")[:31].ljust(32, b"\x00")
    cat_bytes    = categoria.encode("utf-8")[:15].ljust(16, b"\x00")

    header = struct.pack(
        "<IHHI32s16s",
        FYD_PKG_MAGIC,
        100,                      # v1.0.0
        len(arquivos_destino),
        len(payload),
        pkg_id_bytes,
        cat_bytes
    )

    with open(out_path, "wb") as f:
        f.write(header + payload)
    print(f"[OK] Pacote criado: {out_path} ({len(arquivos_destino)} arquivo(s))")

def criar_fcfg_padrao(out_path):
    conteudo = (
        "#!FYDCFG v1\n"
        "# Configuracao nativa FydelisTech OS (/fyd/config/sistema.fcfg)\n"
        "os_nome=FydelisTech OS\n"
        "versao=4.2\n"
        "tema=roxo_neon\n"
        "timezone=-3\n"
        "usuario_padrao=admin\n"
        "rede_dhcp=1\n"
    )
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(conteudo)
    print(f"[OK] Configuracao criada: {out_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso:")
        print("  python3 empacotar_fyd.py cfg <saida.fcfg>")
        print("  python3 empacotar_fyd.py exec <binario_flat.bin> <saida.fyd> <NomeApp>")
        print("  python3 empacotar_fyd.py pkg <saida.fpkg> <id_pacote> <categoria> <arq_local>:<destino_os>")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "cfg":
        criar_fcfg_padrao(sys.argv[2])
    elif cmd == "exec":
        criar_fyd(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "pkg":
        pares = [item.split(":", 1) for item in sys.argv[5:]]
        criar_fpkg(sys.argv[2], sys.argv[3], sys.argv[4], pares)
