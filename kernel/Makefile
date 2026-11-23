# ==========================================
# FYDELIS TECH OS — FydelTerm Kernel Makefile
# v2.5: Boot Hibrido (Legacy MBR + UEFI + Secure Boot) & Rede Real e1000
# Padrao de inclusao: src/include/syscalls
# De Salvador • Bahia
# ==========================================

# FERRAMENTAS
ASM       = nasm
ASFLAGS   = -f elf64 \
            -I ../include/ \
            -I ../include/syscalls/ \
            -I ../kernel/ \
            -I ../drivers/ \
            -I ../grafico/ \
            -I ../virtual/ \
            -I ../user/ \
            -I ../system/ \
            -I ../idioma/ \
            -I ../boot/ \
            -I ../seguranca/ \
            -I ../ \
            -Wall

LD        = ld
LDFLAGS   = -T ../boot/linker.ld --oformat binary

CC        = gcc
CFLAGS    = -m64 \
            -ffreestanding \
            -fno-pie \
            -fno-pic \
            -fno-stack-protector \
            -fno-builtin \
            -nostdlib \
            -mcmodel=kernel \
            -mno-red-zone \
            -mno-mmx \
            -mno-sse \
            -mno-sse2 \
            -I../include/ \
            -I../include/syscalls/ \
            -I../kernel/ \
            -I../drivers/ \
            -I../grafico/ \
            -I../virtual/ \
            -I../user/ \
            -I../system/ \
            -I../idioma/ \
            -I../boot/ \
            -I../seguranca/ \
            -I../ \
            -Wall \
            -MMD -MP

PYTHON    = python3
SBSIGN    ?= sbsign
SBVERIFY  ?= sbverify
ROOT_DIR  = ..
TOOLS_DIR = $(ROOT_DIR)/tools
ASSETS_DIR= $(ROOT_DIR)/assets
INC_DIR   = ../include
BUILD_DIR ?= build

# Chaves UEFI em ../boot/keys/ (com fallback para ~/.fydelis_keys/ ou ../boot/keys/DB.*)
KEYS_DIR  ?= ../boot/keys
UEFI_KEY  ?= $(if $(wildcard $(KEYS_DIR)/fydelis_db.key),$(KEYS_DIR)/fydelis_db.key,$(if $(wildcard $(HOME)/.fydelis_keys/fydelis_db.key),$(HOME)/.fydelis_keys/fydelis_db.key,$(if $(wildcard ../boot/keys/DB.key),../boot/keys/DB.key,)))
UEFI_CRT  ?= $(if $(wildcard $(KEYS_DIR)/fydelis_db.crt),$(KEYS_DIR)/fydelis_db.crt,$(if $(wildcard $(HOME)/.fydelis_keys/fydelis_db.crt),$(HOME)/.fydelis_keys/fydelis_db.crt,$(if $(wildcard ../boot/keys/DB.crt),../boot/keys/DB.crt,)))
UEFI_CER  ?= $(if $(wildcard $(KEYS_DIR)/fydelis_db.cer),$(KEYS_DIR)/fydelis_db.cer,$(if $(wildcard $(HOME)/.fydelis_keys/fydelis_db.cer),$(HOME)/.fydelis_keys/fydelis_db.cer,))

# Caminhos padrao OVMF (Debian/Ubuntu)
OVMF_CODE    ?= /usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS    ?= /usr/share/OVMF/OVMF_VARS_4M.fd
OVMF_SB_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.ms.fd
OVMF_SB_VARS ?= /usr/share/OVMF/OVMF_VARS_4M.ms.fd

# ==========================================
# ASSETS GRAFICOS GERADOS VIA tools/
# ==========================================
HEADERS_ASSETS = \
    $(INC_DIR)/icones.h \
    $(INC_DIR)/fontes_ui.h \
    $(INC_DIR)/wallpaper.h

# ==========================================
# ARQUIVOS OBJETO — ORDEM DE CARGA VITAL!
# kernel.o SEMPRE primeiro -> ponto de entrada em 0x8000
# ==========================================
OBJS = \
    kernel.o \
    exec.o \
    boot_config.o \
    pmm.o \
    paging.o \
    apic.o \
    idt.o \
    gdt.o \
    heap.o \
    context.o \
    scheduler.o \
    pcb.o \
    exceptions.o \
    fs.o \
    buffer.o \
    editor.o \
    commands.o \
    memmap.o \
    syscall_handler.o \
    stubs_kernel.o \
    fyd_formatos.o \
    panic.o \
    estrutura.o \
    energia.o \
    cve_guard.o \
    ../pentest/pentest.o \
    ../drivers/pci.o \
    ../drivers/particao.o \
    ../drivers/disco.o \
    ../drivers/timer.o \
    ../drivers/ata.o \
    ../drivers/keyboard.o \
    ../drivers/audio.o \
    ../drivers/video.o \
    ../drivers/rede.o \
    ../drivers/net_core.o \
    ../drivers/dhcp_servidor.o \
    ../drivers/rede_bridge.o \
    ../drivers/wifi.o \
    ../drivers/bluetooth.o \
    ../drivers/cpu.o \
    ../drivers/impressora.o \
    ../drivers/usb.o \
    ../drivers/mouse.o \
    ../drivers/texto.o \
    ../virtual/virt_detect.o \
    ../virtual/plataforma_detect.o \
    ../virtual/vmx_init.o \
    ../virtual/svm_init.o \
    ../virtual/vm_core.o \
    ../virtual/vmexit_handler.o \
    ../virtual/svm_exit_handler.o \
    ../virtual/vm_execucao_loop.o \
    ../virtual/ept_npt.o \
    ../virtual/ept_integracao.o \
    ../virtual/vm_integracao.o \
    ../virtual/vm_disco_interface.o \
    ../virtual/convidado_com_disco.o \
    ../virtual/memvirt.o \
    ../user/entry.o \
    ../user/syscall_stub.o \
    ../user/vm_client.o \
    ../user/fs_client.o \
    ../user/net_client.o \
    ../user/security_client.o \
    ../user/terminal.o \
    ../user/init.o \
    ../grafico/amd_gpu.o \
    ../grafico/fb_server.o \
    ../grafico/fb_generico.o \
    ../grafico/gop.o \
    ../grafico/gpu_dispatch.o \
    ../grafico/intel_gpu.o \
    ../grafico/pci_gpu.o \
    ../grafico/vesafb.o \
    ../grafico/virtio_gpu.o \
    ../system/hosts_mgr.o \
    ../system/compat_stubs.o \
    ../system/fydlog.o \
    ../idioma/en_us.o \
    ../idioma/idioma.o \
    ../idioma/pt_br.o \
    ../seguranca/fycrypto.o \
    ../seguranca/fydcipher.o \
    ../seguranca/fydperm.o \
    ../seguranca/fydb.o \
    ../apps/acessorios/calculadora.o \
    ../apps/acessorios/fydnotes.o \
    ../apps/sistema/visualizador_logs.o \
    ../apps/sistema/explorer.o \
    ../apps/web/browser.o \
    ../modulos/net/http.o \
    ../modulos/net/tcp.o

-include $(OBJS:.o=.d)

# ==========================================
# ALVO PRINCIPAL
# ==========================================
all: assets BOOTX64.EFI fydelterm.img iso $(BUILD_DIR)/fyd_boot.cfg
	@echo "Build hibrido (Legacy + UEFI + Secure Boot) concluido com sucesso!"

$(BUILD_DIR)/fyd_boot.cfg: ../boot/fyd_boot.cfg
	@mkdir -p $(BUILD_DIR)
	@if [ -f $< ]; then \
		cp $< $@; \
		echo "[+] Copiado fyd_boot.cfg para $(BUILD_DIR)"; \
	fi

# ==========================================
# Aplicativos (apps/)
# ==========================================
../apps/acessorios/calculadora.o: ../apps/acessorios/calculadora.c ../apps/apps.h
	@echo "  CC       $<"
	$(CC) $(CFLAGS) -c $< -o $@

../apps/sistema/visualizador_logs.o: ../apps/sistema/visualizador_logs.c ../apps/apps.h
	@echo "  CC       $<"
	$(CC) $(CFLAGS) -c $< -o $@

# ==========================================
# PIPELINE PYTHON (tools/ -> include/)
# ==========================================
$(ASSETS_DIR)/icones/ethernet.svg: $(TOOLS_DIR)/gerar_kit_icones.py
	@echo "  PY       Gerando kit base de icones SVG"
	cd $(ROOT_DIR) && $(PYTHON) tools/gerar_kit_icones.py

$(INC_DIR)/icones.h: $(ASSETS_DIR)/icones/ethernet.svg $(wildcard $(ASSETS_DIR)/icones/*.svg) $(TOOLS_DIR)/svg2c.py
	@echo "  PY       Convertendo SVGs -> icones.h"
	cd $(ROOT_DIR) && $(PYTHON) tools/svg2c.py

$(INC_DIR)/fontes_ui.h: $(wildcard $(ASSETS_DIR)/fontes/*.ttf) $(TOOLS_DIR)/ttf2c.py
	@echo "  PY       Gerando fontes UI -> fontes_ui.h"
	cd $(ROOT_DIR) && $(PYTHON) tools/ttf2c.py

$(INC_DIR)/wallpaper.h: $(wildcard $(ASSETS_DIR)/wallpapers/*) $(TOOLS_DIR)/img2fb.py
	@echo "  PY       Gerando wallpaper -> wallpaper.h"
	cd $(ROOT_DIR) && $(PYTHON) tools/img2fb.py

assets: $(HEADERS_ASSETS)

# ==========================================
# REGRAS DE COMPILACAO
# ==========================================
exec.o: exec.c $(HEADERS_ASSETS)
	@echo "  CC       $< (com assets graficos)"
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.asm
	@echo "  AS       $<"
	$(ASM) $(ASFLAGS) $< -o $@

%.o: %.c
	@echo "  CC       $<"
	$(CC) $(CFLAGS) -c $< -o $@

# ==========================================
# BOOTLOADER LEGACY (MBR) E LOADER UEFI (BOOTX64.EFI)
# ==========================================
boot.bin: ../boot/boot_legacy.asm
	@echo "  AS       Bootloader Legacy (MBR)"
	$(ASM) -f bin -I ../include/ -I ../boot/ $< -o $@
	@sz=$$(stat -c%s $@); \
	if [ $$sz -ne 512 ]; then \
		echo "ERRO: bootloader deve ter exatamente 512 bytes (atual: $$sz bytes)!"; \
		rm -f $@; exit 1; \
	fi

BOOTX64_unsigned.EFI: ../boot/boot_uefi.asm
	@echo "  AS       Loader UEFI PE32+ (nao assinado)"
	$(ASM) -f bin -I ../include/ -I ../boot/ $< -o $@

BOOTX64.EFI: BOOTX64_unsigned.EFI
	@if [ -n "$(UEFI_KEY)" ] && [ -n "$(UEFI_CRT)" ] && [ -f "$(UEFI_KEY)" ] && [ -f "$(UEFI_CRT)" ] && command -v $(SBSIGN) >/dev/null 2>&1; then \
		echo "  SIGN     Assinando BOOTX64.EFI com $(UEFI_KEY)..."; \
		$(SBSIGN) --key "$(UEFI_KEY)" --cert "$(UEFI_CRT)" --output $@ $<; \
		if command -v $(SBVERIFY) >/dev/null 2>&1; then \
			$(SBVERIFY) --cert "$(UEFI_CRT)" $@ || true; \
		fi; \
	else \
		echo "  [!] Aviso: chaves UEFI ou sbsign nao encontrados; copiando BOOTX64_unsigned.EFI para $@"; \
		cp $< $@; \
	fi

# ==========================================
# LINK DO KERNEL
# ==========================================
kernel.bin: $(OBJS)
	@echo "  LD       Kernel — $(words $(OBJS)) modulos"
	$(LD) $(LDFLAGS) $(OBJS) -o $@

# ==========================================
# IMAGEM DE DISCO HIBRIDA (LEGACY MBR + PARTICAO EFI FAT32)
# LBA 0                 = MBR Legacy (446B codigo + Tabela Particoes + 0xAA55)
# LBA 2048..10239 (4MiB)= ESP FAT32 (\EFI\BOOT\BOOTX64.EFI)
# LBA 4096 (offset 2MiB)= kernel.bin
# LBA 8192 / 10752 / 13312 = Wallpapers (640x512 RGBA)
# ==========================================
WALLPAPERS_PNG = \
    $(ASSETS_DIR)/images/splash.png \
    $(ASSETS_DIR)/images/login.png \
    $(ASSETS_DIR)/images/desktop.png

fydelterm.img: boot.bin BOOTX64.EFI kernel.bin $(TOOLS_DIR)/gravar_wallpapers_disco.py $(WALLPAPERS_PNG)
	@echo "  IMG      $@ (Hibrida Legacy BIOS + UEFI)"
	dd if=/dev/zero of=$@ bs=1M count=32 status=none
	@if command -v sfdisk >/dev/null 2>&1; then \
		printf "label: dos\nstart=2048, size=8192, type=ef\nstart=16384, size=49152, type=0c\n" | sfdisk --quiet $@; \
	fi
	dd if=boot.bin of=$@ bs=1 count=446 conv=notrunc status=none
	printf '\125\252' | dd of=$@ bs=1 seek=510 count=2 conv=notrunc status=none
	@if command -v mformat >/dev/null 2>&1 && command -v mcopy >/dev/null 2>&1; then \
		dd if=/dev/zero of=esp.img bs=512 count=8192 status=none; \
		mformat -i esp.img -F -v "FYDEL_EFI" ::; \
		mmd -i esp.img ::/EFI ::/EFI/BOOT; \
		mcopy -i esp.img BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI; \
		if [ -n "$(UEFI_CER)" ] && [ -f "$(UEFI_CER)" ]; then \
			mcopy -i esp.img "$(UEFI_CER)" ::/EFI/BOOT/fydelis_db.cer; \
		fi; \
		dd if=esp.img of=$@ bs=512 seek=2048 conv=notrunc status=none; \
		rm -f esp.img; \
	fi
	dd if=kernel.bin of=$@ conv=notrunc bs=512 seek=4096 status=none
	@echo "  PY       Gravando wallpapers nos LBAs 8192, 10752 e 13312"
	$(PYTHON) $(TOOLS_DIR)/gravar_wallpapers_disco.py $@ $(ASSETS_DIR)/images

# ==========================================
# ISO HIBRIDA (LEGACY EL-TORITO + UEFI BOOTX64.EFI)
# ==========================================
boot_flp.img: boot.bin kernel.bin
	@echo "  FLP      $@"
	dd if=/dev/zero of=$@ bs=1M count=8 status=none
	dd if=boot.bin   of=$@ conv=notrunc bs=512 count=1 status=none
	dd if=kernel.bin of=$@ conv=notrunc bs=512 seek=4096 status=none

iso: boot_flp.img BOOTX64.EFI fydelterm.img
	@echo "  ISO      fydelterm.iso"
	rm -rf iso_root
	mkdir -p iso_root/boot iso_root/EFI/BOOT
	cp boot_flp.img  iso_root/boot/boot.img
	cp fydelterm.img iso_root/boot/fydelterm.img
	cp kernel.bin    iso_root/boot/kernel.bin
	cp BOOTX64.EFI   iso_root/EFI/BOOT/BOOTX64.EFI
	if [ -n "$(UEFI_CER)" ] && [ -f "$(UEFI_CER)" ]; then \
		cp "$(UEFI_CER)" iso_root/EFI/BOOT/fydelis_db.cer; \
	fi
	cp ../boot/fyd_boot.cfg iso_root/boot/fyd_boot.cfg 2>/dev/null || true
	genisoimage -o fydelterm.iso \
		-b boot/boot.img \
		-no-emul-boot \
		-boot-load-size 4 \
		-J -R -l \
		-V "FYDELIS_TECH_OS" \
		iso_root/
	rm -rf iso_root
	@echo "ISO hibrida pronta: fydelterm.iso"

# ==========================================
# EXECUTAR NO QEMU (LEGACY BIOS / UEFI / SECURE BOOT + REDE E1000)
# ==========================================
QEMU_NET = -netdev user,id=net0 -device e1000,netdev=net0

run: fydelterm.img
	@echo "Iniciando FydelisTech OS (Modo Legacy BIOS + Rede e1000)..."
	qemu-system-x86_64 \
		-drive format=raw,file=fydelterm.img,if=ide,index=0,media=disk \
		-boot c \
		$(QEMU_NET) \
		-no-reboot \
		-no-shutdown \
		-m 512M \
		-smp 2 \
		-display gtk \
		-serial stdio

run-uefi: fydelterm.img
	@echo "Iniciando FydelisTech OS (Modo UEFI 64-bit OVMF + Rede e1000)..."
	cp -f $(OVMF_VARS) OVMF_VARS_local.fd 2>/dev/null || true
	qemu-system-x86_64 \
		-drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) \
		-drive if=pflash,format=raw,file=OVMF_VARS_local.fd \
		-drive format=raw,file=fydelterm.img,if=ide,index=0,media=disk \
		$(QEMU_NET) \
		-m 512M \
		-smp 2 \
		-display gtk \
		-serial stdio

run-secboot: fydelterm.img
	@echo "Iniciando FydelisTech OS (Modo UEFI + SECURE BOOT ATIVO)..."
	cp -f $(OVMF_SB_VARS) OVMF_VARS_sb_local.fd 2>/dev/null || true
	qemu-system-x86_64 \
		-machine q35,smm=on \
		-global driver=cfi.pflash01,property=secure,value=on \
		-drive if=pflash,format=raw,readonly=on,file=$(OVMF_SB_CODE) \
		-drive if=pflash,format=raw,file=OVMF_VARS_sb_local.fd \
		-drive format=raw,file=fydelterm.img,if=ide,index=0,media=disk \
		$(QEMU_NET) \
		-m 512M \
		-smp 2 \
		-display gtk \
		-serial stdio

debug: fydelterm.img
	qemu-system-x86_64 \
		-drive format=raw,file=fydelterm.img \
		$(QEMU_NET) \
		-m 512M -smp 2 -serial stdio \
		-s -S

# ==========================================
# LIMPAR
# ==========================================
clean:
	@echo "Limpando..."
	rm -f *.o *.d
	rm -f ../boot/*.o ../boot/*.d
	rm -f ../drivers/*.o ../drivers/*.d
	rm -f ../pentest/*.o ../pentest/*.d
	rm -f ../grafico/*.o ../grafico/*.d
	rm -f ../user/*.o ../user/*.d
	rm -f ../virtual/*.o ../virtual/*.d
	rm -f ../system/*.o ../system/*.d
	rm -f ../idioma/*.o ../idioma/*.d
	rm -f ../seguranca/*.o ../seguranca/*.d
	rm -f ../apps/acessorios/*.o ../apps/acessorios/*.d
	rm -f ../apps/sistema/*.o ../apps/sistema/*.d
	rm -f ../apps/web/*.o ../apps/web/*.d
	rm -f ../modulos/net/*.o ../modulos/net/*.d
	rm -rf $(BUILD_DIR) iso_root
	rm -f *.bin *.EFI esp.img OVMF_VARS_local.fd OVMF_VARS_sb_local.fd fydelterm.img boot_flp.img fydelterm.iso
	@echo "Limpo!"

distclean: clean
	rm -f $(HEADERS_ASSETS)

.PHONY: all assets iso run run-uefi run-secboot debug clean distclean
