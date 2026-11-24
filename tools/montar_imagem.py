#!/usr/bin/env python3
"""
Monta build/img/fydelterm.img com layout híbrido:
- LBA 0 (bytes 0..511): setor MBR de 512 bytes (preservando partição/assinatura 0x55AA)
- LBA 4096 (offset 4096 * 512): kernel.bin
- LBA 8192 (offset 8192 * 512): início da área/partição de boot UEFI
"""

from pathlib import Path
import argparse

SECTOR_SIZE = 512
LBA_KERNEL = 4096
LBA_EFI = 8192


def montar_imagem(
    out_img: Path,
    kernel_bin: Path,
    mbr_bin: Path | None = None,
    efi_bin: Path | None = None,
    tamanho_mb: int = 32,
) -> None:
    if not kernel_bin.exists():
        raise FileNotFoundError(f"kernel.bin não encontrado: {kernel_bin}")

    kernel_data = kernel_bin.read_bytes()
    total_bytes = tamanho_mb * 1024 * 1024

    out_img.parent.mkdir(parents=True, exist_ok=True)

    # Se já existir, reutiliza como base; caso contrário, cria zerada
    if out_img.exists() and out_img.stat().st_size >= total_bytes:
        img_data = bytearray(out_img.read_bytes())
    else:
        img_data = bytearray(total_bytes)

    # 1. Grava MBR no LBA 0 (primeiros 440 bytes de código + assinatura 0x55AA em 510..511)
    if mbr_bin and mbr_bin.exists():
        mbr_data = mbr_bin.read_bytes()
        codigo_len = min(len(mbr_data), 440)
        img_data[0:codigo_len] = mbr_data[0:codigo_len]

    # Entrada de partição básica (Tipo 0xEF EFI System Partition) começando no LBA 8192
    # Offset 446 (0x1BE), 16 bytes: boot_flag=0x00, type=0xEF, start_lba=8192, sectors=24576 (12 MB)
    part_offset = 446
    start_lba = LBA_EFI
    num_sectors = max(2048, (total_bytes // SECTOR_SIZE) - LBA_EFI - 64)
    entry = bytearray(16)
    entry[0] = 0x00
    entry[4] = 0xEF
    entry[8:12] = start_lba.to_bytes(4, "little")
    entry[12:16] = num_sectors.to_bytes(4, "little")
    img_data[part_offset : part_offset + 16] = entry

    # Assinatura MBR obrigatória 0x55AA nos bytes 510 e 511
    img_data[510] = 0x55
    img_data[511] = 0xAA

    # 2. Grava kernel.bin no LBA 4096
    off_kernel = LBA_KERNEL * SECTOR_SIZE
    end_kernel = off_kernel + len(kernel_data)
    if end_kernel > len(img_data):
        raise ValueError("Imagem pequena demais para acomodar o kernel.bin no LBA 4096.")
    img_data[off_kernel:end_kernel] = kernel_data

    # 3. Grava binário EFI na área LBA 8192 (útil para testes diretos de setor/imagem)
    efi_data: bytes | None = None
    if efi_bin and efi_bin.exists():
        dados_efi = efi_bin.read_bytes()
        off_efi = LBA_EFI * SECTOR_SIZE
        end_efi = off_efi + len(dados_efi)
        if end_efi <= len(img_data):
            img_data[off_efi:end_efi] = dados_efi
            efi_data = dados_efi

    out_img.write_bytes(img_data)
    print(f"[OK] Imagem gerada: {out_img} ({len(img_data)} bytes)")
    print(f"     LBA 0    : MBR signature 0x{img_data[510]:02X}{img_data[511]:02X}")
    print(f"     LBA {LBA_KERNEL}: kernel.bin ({len(kernel_data)} bytes)")
    if efi_bin is not None and efi_data is not None:
        print(f"     LBA {LBA_EFI}: {efi_bin.name} ({len(efi_data)} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Monta imagem híbrida FydelisTechOS.")
    parser.add_argument("--out", default="build/img/fydelterm.img", help="Caminho da imagem de saída")
    parser.add_argument("--kernel", default="kernel/kernel.bin", help="Caminho do kernel.bin")
    parser.add_argument("--mbr", default="boot/mbr_min.bin", help="Caminho opcional do MBR (512B)")
    parser.add_argument("--efi", default="boot/BOOTX64.EFI", help="Caminho opcional do BOOTX64.EFI assinado")
    parser.add_argument("--size-mb", type=int, default=32, help="Tamanho da imagem em MB")
    args = parser.parse_args()

    montar_imagem(
        out_img=Path(args.out),
        kernel_bin=Path(args.kernel),
        mbr_bin=Path(args.mbr),
        efi_bin=Path(args.efi),
        tamanho_mb=args.size_mb,
    )


if __name__ == "__main__":
    main()
