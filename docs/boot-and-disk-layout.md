# Layout de Disco e Boot

Este documento descreve a organização de setores e endereçamento lógico (LBA) adotada na imagem híbrida de referência (`build/img/fydelterm.img`) para testes em UEFI e Legacy BIOS.

## Mapa de LBAs (Setores de 512 Bytes)

| Região / Componente | Offset / LBA | Deslocamento em Bytes | Descrição |
| :--- | :--- | :--- | :--- |
| **MBR (Legacy BIOS)** | `LBA 0` | `0x000000` (`0`) | Setor inicial de 512 bytes contendo código de boot Legacy, tabela de partição e assinatura `0x55AA` nos bytes `510–511`. |
| **Kernel Binário** | `LBA 4096` | `0x200000` (`4096 * 512`) | Posição fixa de `kernel.bin` na imagem para leitura direta e previsível durante o boot. |
| **Área / Partição EFI** | `LBA 8192+` | `0x400000` (`8192 * 512`) | Início da região reservada à partição/estrutura EFI (`BOOTX64.EFI` assinado e arquivos de boot UEFI). |

## Fluxo Legacy BIOS vs. UEFI

- **Legacy BIOS:** o BIOS lê o `LBA 0`, valida os bytes `0x55` e `0xAA` no fim do setor e transfere o controle para o código de boot Legacy (`boot_legacy.asm` / `bootloader.asm`), que carrega os estágios seguintes e o kernel.
- **UEFI:** o firmware carrega `EFI\BOOT\BOOTX64.EFI` a partir da estrutura/partição EFI, obtém informações de vídeo (GOP) e lê `kernel.bin` a partir do `LBA 4096` antes de transferir a execução ao kernel.

## Verificação Rápida da Imagem

Após gerar a imagem (por exemplo, via `tools/montar_imagem.py`), valide três pontos antes de abrir no QEMU ou VirtualBox:

1. **Assinatura MBR:** os bytes `510` e `511` do arquivo `.img` devem ser `55` e `AA`.
2. **Kernel no LBA 4096:** o conteúdo gravado a partir do offset `4096 * 512` deve corresponder ao `kernel.bin` compilado.
3. **Binário UEFI:** o `BOOTX64.EFI` deve estar assinado e presente no caminho esperado da partição/estrutura EFI.
