# Arquitetura do Sistema — FydelisTechOS / FydelTerm

Sistema operacional bare-metal x86_64 desenvolvido em Assembly (NASM) e C, projetado para inicialização direta em UEFI e Legacy BIOS, com organização modular por camadas, aceleração gráfica com fallback seguro e suporte a virtualização.

## Visão em Camadas

- **Boot (`boot/`):** inicialização em modo Legacy BIOS (`boot_legacy.asm` / `bootloader.asm`) e UEFI x64 (`boot_uefi.asm` / `efi_stub.asm`), leitura de informações de boot (`bootinfo.inc`), configuração (`fyd_boot.cfg`) e mapa de ligação (`linker.ld`).
- **Núcleo (`kernel/`):** configuração de CPU e interrupções (`gdt.asm`, `idt.asm`, `apic.asm`, `exceptions.asm`, `context.asm`), gerenciamento de memória (`pmm.asm`, `heap.asm`, `memmap.asm`, `paging.asm`), processos/escalonador/syscalls (`pcb.asm`, `scheduler.asm`, `syscall_handler.asm`, `exec.c`), sistema de arquivos (`fs.asm`, `particao.asm`, `fyd_formatos.c`), terminal/comandos (`kernel.asm`, `commands.asm`, `buffer.asm`, `parse_line.asm`, `reset_buffer.asm`) e diagnóstico/segurança (`panic.c`, `cve_guard.asm`, `estrutura.asm`, `energia.asm`, `boot_config.c`, `stubs_kernel.asm`).
- **Drivers (`drivers/`):** barramentos e periféricos (`pci.asm`, `usb.asm`, `ata.asm`, `disco.asm`, `particao.asm`, `keyboard.asm`, `mouse.asm`, `timer.asm`, `cpu.asm`, `video.asm`, `texto.asm`, `audio.asm`, `bluetooth.asm`, `impressora.asm`, `energia.asm`) e pilha de rede (`net_core.asm`, `rede.asm`, `rede_bridge.asm`, `dhcp_servidor.asm`, `wifi.asm`).
- **Gráfico (`grafico/`):** seletor central `gpu_dispatch.asm` integrado a `virtio_gpu.asm` (clipping, blit com tratamento de sobreposição e fila 2D `TRANSFER_TO_HOST` / `RESOURCE_FLUSH`), ganchos/stubs para Intel e AMD (`intel_gpu.asm`, `amd_gpu.asm`, `pci_gpu.asm`) e suporte a framebuffer/GOP/VESA (`fb_generico.asm`, `fb_server.asm`, `gop.asm`, `vesafb.asm`).
- **Espaço de Usuário e Serviços (`user/`, `system/`, `idioma/`, `modulos/`):** rotinas de espaço de usuário e clientes (`entry.asm`, `init.asm`, `terminal.asm`, `fs_client.asm`, `net_client.asm`, `security_client.asm`, `vm_client.asm`, `syscall_stub.asm`), utilitários de sistema (`fydlog.asm`, `hosts_mgr.asm`, `compat_stubs.asm`), idiomas (`pt_br.asm`, `en_us.asm`, `idioma.asm`) e módulos (`net/tcp.c`, `net/http.c`, `multimidia/*`).
- **Virtualização, Segurança e Ferramentas (`virtual/`, `pentest/`, `tools/`):** experimentos e rotinas de hipervisor/VM (`vmx_init.asm`, `svm_init.asm`, `ept_npt.asm`, `vm_core.asm`, `vmexit_handler.asm`, `svm_exit_handler.asm`), auditoria/testes (`pentest.asm`) e scripts de empacotamento/conversão de recursos (`tools/*.py`).

## Fluxo de Inicialização e Gráficos

1. **Boot e transição:** o firmware (BIOS Legacy via setor de boot ou UEFI via `BOOTX64.EFI`) carrega o kernel e repassa o contexto inicial (`BootInfo` / framebuffer).
2. **Núcleo e drivers:** o kernel inicializa GDT, IDT, paginação, alocadores e barramentos (`PCI`, armazenamento, entrada, rede).
3. **Seleção gráfica (`gpu_dispatch`):** `gpu_inicializar` verifica a disponibilidade do framebuffer e tenta detectar/inicializar aceleradores (como `virtio_gpu`); caso não haja aceleração ativa ou inicializada, mantém o fallback para `fb_preencher_retangulo` no framebuffer linear.

## Princípios de Organização

- **Saída isolada de compilação:** objetos (`.o`), dependências (`.d`), binários (`.bin`, `.efi`) e imagens (`.img`, `.iso`) ficam fora das pastas de código-fonte (em `build/` / `kernel/build/` e ignorados no `.gitignore`).
- **Desacoplamento progressivo:** redução de dependências externas pesadas de UI em favor de rotinas próprias e previsíveis no sistema.
