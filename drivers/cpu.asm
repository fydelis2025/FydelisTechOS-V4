; ==========================================
; 🧠 CPU.ASM — DETECÇÃO E CARACTERÍSTICAS DO PROCESSADOR
; x86_64 · Família · Recursos · VT-x/AMD-V · NX · AVX
; FydelisTech OS v2.2 · Salvador • Bahia 🇧🇷
; ==========================================
BITS 64
%include "fydelterm.inc"

; ========== FLAGS E MÁSCARAS — CPUID ==========
; Função 1 — EDX
CPU1_EDX_FPU     equ 1<<0    ; Coprocessador na chip
CPU1_EDX_VME     equ 1<<1
CPU1_EDX_DE      equ 1<<2
CPU1_EDX_PSE     equ 1<<3
CPU1_EDX_TSC     equ 1<<4    ; Contador de tempo
CPU1_EDX_MSR     equ 1<<5    ; Registradores de modelo
CPU1_EDX_PAE     equ 1<<6    ; Endereçamento estendido 36-bit
CPU1_EDX_MCE     equ 1<<7
CPU1_EDX_CX8     equ 1<<8    ; Compare-and-swap 8 bytes
CPU1_EDX_APIC    equ 1<<9
CPU1_EDX_SEP     equ 1<<11
CPU1_EDX_MTRR    equ 1<<12
CPU1_EDX_PGE     equ 1<<13   ; Global Pages
CPU1_EDX_MCA     equ 1<<14
CPU1_EDX_CMOV    equ 1<<15   ; Instruções condicionais
CPU1_EDX_PAT     equ 1<<16
CPU1_EDX_PSE36   equ 1<<17
CPU1_EDX_PSN     equ 1<<18
CPU1_EDX_CLFSH   equ 1<<19
CPU1_EDX_DS      equ 1<<21
CPU1_EDX_ACPI    equ 1<<22
CPU1_EDX_MMX     equ 1<<23   ; MMX
CPU1_EDX_FXSR    equ 1<<24   ; Salvar/restaurar FPU rápido
CPU1_EDX_SSE     equ 1<<25   ; SSE
CPU1_EDX_SSE2    equ 1<<26   ; SSE2
CPU1_EDX_SS      equ 1<<27
CPU1_EDX_HTT     equ 1<<28   ; Hyper-Threading

; Função 1 — ECX
CPU1_ECX_SSE3    equ 1<<0
CPU1_ECX_PCLMUL  equ 1<<1
CPU1_ECX_DTES64  equ 1<<2
CPU1_ECX_MONITOR equ 1<<3
CPU1_ECX_DSCPL   equ 1<<4
CPU1_ECX_VMX     equ 1<<5    ; Intel VT-x ✅
CPU1_ECX_SMX     equ 1<<6
CPU1_ECX_EST     equ 1<<7
CPU1_ECX_TM2     equ 1<<8
CPU1_ECX_SSSE3   equ 1<<9
CPU1_ECX_CID     equ 1<<10
CPU1_ECX_FMA     equ 1<<12
CPU1_ECX_CX16    equ 1<<13   ; Compare-and-swap 16 bytes
CPU1_ECX_XTPR    equ 1<<14
CPU1_ECX_PDCM    equ 1<<15
CPU1_ECX_PCID    equ 1<<17
CPU1_ECX_DCA     equ 1<<18
CPU1_ECX_SSE4_1  equ 1<<19
CPU1_ECX_SSE4_2  equ 1<<20
CPU1_ECX_x2APIC  equ 1<<21
CPU1_ECX_MOVBE   equ 1<<22
CPU1_ECX_POPCNT  equ 1<<23   ; Contagem de bits
CPU1_ECX_AES     equ 1<<25   ; AES acelerado ✅
CPU1_ECX_XSAVE   equ 1<<26   ; XSAVE/XRSTOR
CPU1_ECX_OSXSAVE equ 1<<27   ; XSAVE ativado pelo SO
CPU1_ECX_AVX     equ 1<<28   ; AVX ✅
CPU1_ECX_RDRND   equ 1<<30   ; Número aleatório de hardware ✅

; Função 7 — EBX (extensões)
CPU7_EBX_AVX2    equ 1<<5
CPU7_EBX_SMEP    equ 1<<7
CPU7_EBX_RDSEED  equ 1<<18
CPU7_EBX_ADX     equ 1<<19
CPU7_EBX_SMAP    equ 1<<20

; Função 0x80000001 — EDX (extensões AMD)
CPUX_EDX_NX      equ 1<<20   ; Bit de Não-Execução ✅
CPUX_EDX_PDPE1GB equ 1<<26   ; Páginas de 1GB
CPUX_EDX_RDTSCP  equ 1<<27
CPUX_EDX_EMBED   equ 1<<29
CPUX_EDX_INVTSC  equ 1<<30

; Função 0x80000001 — ECX
CPUX_ECX_AMD_VMX equ 1<<2    ; AMD-V ✅

; ========== ESTRUTURA DE INFORMAÇÃO ==========
struc CPUInfo
    .presente:       resb 1
    .fabricante:     resb 13   ; "GenuineIntel" / "AuthenticAMD"
    .familia:        resd 1
    .modelo:         resd 1
    .passo:          resd 1
    .numero_nucleos: resd 1
    .frequencia_mhz: resd 1

    ; Recursos — flags
    .tem_fpu:        resb 1
    .tem_tsc:        resb 1
    .tem_pae:        resb 1
    .tem_sse:        resb 1
    .tem_sse2:       resb 1
    .tem_avx:        resb 1
    .tem_avx2:       resb 1
    .tem_aes:        resb 1
    .tem_nx:         resb 1    ; Proteção de memória
    .tem_vmx:        resb 1    ; VT-x / AMD-V
    .tem_pcid:       resb 1    ; Cache de endereços
    .tem_1gb_pag:    resb 1    ; Páginas grandes
    .tem_rdrand:     resb 1
    .tem_rdseed:     resb 1
    .tem_adx:        resb 1
endstruc

section .bss
align 8
cpu_info:         resb CPUInfo_size
cpu_max_funcao:   resd 1
cpu_max_ext_fun:  resd 1

section .text
global cpu_detectar
global cpu_obter_info
global cpu_verificar_recursos
global cpu_tem_vmx
global cpu_tem_nx
global cpu_ativar_recursos
global cpu_imprimir_resumo

extern print_string
extern print_newline
extern print_hex    ; 👈 Adicionar esta linha

; ==========================================
; 🔍 DETECTAR E PREENCHER TUDO
; ==========================================
cpu_detectar:
    push   rbx
    push   rcx
    push   rdx
    push   rsi

    ; Zerar estrutura
    mov    rdi, cpu_info
    mov    rcx, CPUInfo_size
    xor    rax, rax
    rep    stosb

    mov    byte [cpu_info + CPUInfo.presente], 1

    ; ─── Passo 1: Verificar se CPUID existe ───
    pushf
    pushf
    xor    dword [rsp], 1<<21   ; Alterna bit de ID
    popf
    pushf
    pop    rax
    and    eax, 1<<21
    jz     .sem_cpuid

    ; ─── Passo 2: Ler fabricante ───
    xor    eax, eax
    cpuid
    mov    [cpu_max_funcao], eax
    mov    dword [cpu_info + CPUInfo.fabricante], ebx
    mov    dword [cpu_info + CPUInfo.fabricante+4], edx
    mov    dword [cpu_info + CPUInfo.fabricante+8], ecx
    mov    byte [cpu_info + CPUInfo.fabricante+12], 0  ; Terminar string

    ; ─── Passo 3: Família, Modelo, Passo ───
    mov    eax, 1
    cpuid
    mov    ecx, eax

    ; Familia = bits 8..11
    shr    eax, 8
    and    eax, 0xF
    mov    [cpu_info + CPUInfo.familia], eax

    ; Modelo = bits 4..7
    mov    eax, ecx
    shr    eax, 4
    and    eax, 0xF
    mov    [cpu_info + CPUInfo.modelo], eax

    ; Passo = bits 0..3
    mov    eax, ecx
    and    eax, 0xF
    mov    [cpu_info + CPUInfo.passo], eax

    ; ─── Passo 4: Recursos principais (EDX / ECX) ───
    mov    eax, 1
    cpuid
    mov    r8d, edx
    mov    r9d, ecx

    ; Flags EDX
    mov    eax, r8d
    and    eax, CPU1_EDX_FPU
    setnz  al
    mov    [cpu_info + CPUInfo.tem_fpu], al

    mov    eax, r8d
    and    eax, CPU1_EDX_TSC
    setnz  al
    mov    [cpu_info + CPUInfo.tem_tsc], al

    mov    eax, r8d
    and    eax, CPU1_EDX_PAE
    setnz  al
    mov    [cpu_info + CPUInfo.tem_pae], al

    mov    eax, r8d
    and    eax, CPU1_EDX_SSE
    setnz  al
    mov    [cpu_info + CPUInfo.tem_sse], al

    mov    eax, r8d
    and    eax, CPU1_EDX_SSE2
    setnz  al
    mov    [cpu_info + CPUInfo.tem_sse2], al

    ; Flags ECX
    mov    eax, r9d
    and    eax, CPU1_ECX_AVX
    setnz  al
    mov    [cpu_info + CPUInfo.tem_avx], al

    mov    eax, r9d
    and    eax, CPU1_ECX_AES
    setnz  al
    mov    [cpu_info + CPUInfo.tem_aes], al

    mov    eax, r9d
    and    eax, CPU1_ECX_PCID
    setnz  al
    mov    [cpu_info + CPUInfo.tem_pcid], al

    mov    eax, r9d
    and    eax, CPU1_ECX_RDRND
    setnz  al
    mov    [cpu_info + CPUInfo.tem_rdrand], al

    mov    eax, r9d
    and    eax, CPU1_ECX_VMX
    setnz  al
    mov    [cpu_info + CPUInfo.tem_vmx], al

    ; ─── Passo 5: Recursos estendidos (AVX2, etc) ───
    mov    eax, 7
    xor    ecx, ecx
    cpuid

    mov    eax, ebx
    and    eax, CPU7_EBX_AVX2
    setnz  al
    mov    [cpu_info + CPUInfo.tem_avx2], al

    mov    eax, ebx
    and    eax, CPU7_EBX_RDSEED
    setnz  al
    mov    [cpu_info + CPUInfo.tem_rdseed], al

    mov    eax, ebx
    and    eax, CPU7_EBX_ADX
    setnz  al
    mov    [cpu_info + CPUInfo.tem_adx], al

    ; ─── Passo 6: Recursos estendidos AMD/NX ───
    mov    eax, 0x80000000
    cpuid
    cmp    eax, 0x80000001
    jb     .sem_extended

    mov    [cpu_max_ext_fun], eax
    mov    eax, 0x80000001
    cpuid

    ; EDX: NX, páginas de 1GB
    mov    eax, edx
    and    eax, CPUX_EDX_NX
    setnz  al
    mov    [cpu_info + CPUInfo.tem_nx], al

    mov    eax, edx
    and    eax, CPUX_EDX_PDPE1GB
    setnz  al
    mov    [cpu_info + CPUInfo.tem_1gb_pag], al

    ; ECX: AMD-V
    cmp    byte [cpu_info + CPUInfo.tem_vmx], 0
    jne    .vmx_definido  ; Já detectado Intel VT-x
    mov    eax, ecx
    and    eax, CPUX_ECX_AMD_VMX
    setnz  al
    mov    [cpu_info + CPUInfo.tem_vmx], al
.vmx_definido:

.sem_extended:
    mov    rax, 1  ; Sucesso
    jmp    .fim

.sem_cpuid:
    xor    rax, rax
    mov    byte [cpu_info + CPUInfo.presente], 0

.fim:
    pop    rsi
    pop    rdx
    pop    rcx
    pop    rbx
    ret

; ==========================================
; ✅ ATIVAR RECURSOS — Mudar registradores do sistema
; ==========================================
cpu_ativar_recursos:
    ; Ativar SSE/SSE2 obrigatório para x86_64
    mov    rax, cr0
    and    ax, 0xFFFB       ; Desabilitar coprocessador emulado
    or     ax, 0x2          ; Ativar monitoramento de FPU
    mov    cr0, rax

    mov    rax, cr4
    or     rax, 1<<3        ; OSFXSR — Salvar/restaurar SSE
    or     rax, 1<<9        ; OSXMMEXCPT — Exceções SSE
    cmp    byte [cpu_info + CPUInfo.tem_avx], 1
    jne    .sem_avx
    or     rax, 1<<18       ; OSXSAVE — Ativar XSAVE para AVX
.sem_avx:
    mov    cr4, rax

    ; Ativar NX se disponível
    cmp    byte [cpu_info + CPUInfo.tem_nx], 1
    jne    .sem_nx
    mov    ecx, 0xC0000080  ; IA32_EFER
    rdmsr
    or     eax, 1<<11       ; NXE bit
    wrmsr
.sem_nx:

    ; Ativar PCID se disponível (melhora desempenho de troca de processo)
    cmp    byte [cpu_info + CPUInfo.tem_pcid], 1
    jne    .sem_pcid
    mov    rax, cr4
    or     rax, 1<<17
    mov    cr4, rax
.sem_pcid:

    ret

; ==========================================
; 🔍 CONSULTAS RÁPIDAS — para o kernel
; ==========================================
cpu_tem_vmx:
    movzx  rax, byte [cpu_info + CPUInfo.tem_vmx]
    ret

cpu_tem_nx:
    movzx  rax, byte [cpu_info + CPUInfo.tem_nx]
    ret

cpu_obter_info:
    ; rdi → ponteiro para estrutura em C++
    mov    rsi, cpu_info
    mov    rcx, CPUInfo_size
    rep    movsb
    ret

; ==========================================
; 📤 RESUMO PARA DEPURAÇÃO — impressão no terminal
; ==========================================
cpu_imprimir_resumo:
    ; Imprime fabricante
    mov    rsi, msg_cpu
    call   print_string
    mov    rsi, cpu_info + CPUInfo.fabricante
    call   print_string
    call   print_newline

    ; Família e modelo
    mov    rsi, msg_familia
    call   print_string
    movzx  rax, byte [cpu_info + CPUInfo.familia]
    call   print_hex
    mov    rsi, msg_modelo
    call   print_string
    movzx  rax, byte [cpu_info + CPUInfo.modelo]
    call   print_hex
    call   print_newline

    ; Recursos principais
    mov    rsi, msg_recursos
    call   print_string

    ; FPU
    cmp    byte [cpu_info + CPUInfo.tem_fpu], 0
    jne    .p_fpu_sim
    mov    rsi, msg_nao
    jmp    .p_fpu_fim
.p_fpu_sim:
    mov    rsi, msg_sim
.p_fpu_fim:
    call   print_string

    ; SSE2
    cmp    byte [cpu_info + CPUInfo.tem_sse2], 0
    jne    .p_sse_sim
    mov    rsi, msg_nao
    jmp    .p_sse_fim
.p_sse_sim:
    mov    rsi, msg_sim
.p_sse_fim:
    call   print_string

    ; AVX
    cmp    byte [cpu_info + CPUInfo.tem_avx], 0
    jne    .p_avx_sim
    mov    rsi, msg_nao
    jmp    .p_avx_fim
.p_avx_sim:
    mov    rsi, msg_sim
.p_avx_fim:
    call   print_string

    ; NX
    cmp    byte [cpu_info + CPUInfo.tem_nx], 0
    jne    .p_nx_sim
    mov    rsi, msg_nao
    jmp    .p_nx_fim
.p_nx_sim:
    mov    rsi, msg_sim
.p_nx_fim:
    call   print_string

    ; VMX
    cmp    byte [cpu_info + CPUInfo.tem_vmx], 0
    jne    .p_vmx_sim
    mov    rsi, msg_vmx
    jmp    .p_vmx_fim
.p_vmx_sim:
    mov    rsi, msg_sim
.p_vmx_fim:
    call   print_string

    call   print_newline
    ret

; ========== MENSAGENS ==========
msg_cpu:       db "🧠 CPU: ", 0
msg_familia:   db "  Família: 0x", 0
msg_modelo:    db "  Modelo: 0x", 0
msg_recursos:  db "  FPU  SSE2 AVX  NX  VT-x: ", 0
msg_sim:       db "✅ ", 0
msg_nao:       db "❌ ", 0
msg_vmx:       db "— ", 0
