; ==================================================
; FydelisTechOS — VM Mínima / VMCS v2.2
; Executa código convidado no modo de virtualização
; ==================================================
bits 64
align 4096

; ========== Estruturas e Offsets VMCS ==========
VMCS_VOID               equ 0
VMCS_GUEST_RIP          equ 0x00006818
VMCS_GUEST_RSP          equ 0x0000681c
VMCS_GUEST_CR3          equ 0x0000680c
VMCS_GUEST_CR0          equ 0x00006804
VMCS_GUEST_CR4          equ 0x00006824
VMCS_CTRL_EXEC          equ 0x00004000
VMCS_CTRL_EXEC_HI       equ 0x00004001
VMCS_CTRL_PIN           equ 0x00004002
VMCS_CTRL_PROC          equ 0x00004004
VMCS_CTRL_ENTRY         equ 0x0000400e
VMCS_EXIT_REASON        equ 0x00004402
VMCS_EXIT_QUALIFICATION equ 0x00006400

CR0_MUST_ON  equ 0x80000000  
CR4_MUST_ON  equ 0x00000200  

extern pml4_table

section .bss
align 4096
global vmcs_region
global vm_guest_rip
global vm_guest_rsp

vmcs_region:        resb 4096   
vm_guest_stack:     resb 8192   
vm_guest_rip:       resq 1      
vm_guest_rsp:       resq 1      
vm_guest_cr3:       resq 1      

section .text

global vmcs_init
vmcs_init:
    ; VMCLEAR e VMPTRLD exigem um registrador contendo o ponteiro de 64 bits
    lea  rax, [rel vmcs_region]
    mov  [rel rbx_temp_ptr_save_if_needed], rax  ; Alternativa limpa usando registrador direto:
    
    ; Passando via registrador de 64 bits apontando para a memória
    push rax
    vmclear [rsp]
    pop  rax
    jc   .vmcs_erro

    lea  rax, [rel vmcs_region]
    push rax
    vmptrld [rsp]
    pop  rax
    jc   .vmcs_erro

    mov  rax, CR0_MUST_ON
    bts  rax, 0                  
    mov  rcx, VMCS_GUEST_CR0
    vmwrite rcx, rax

    mov  rax, CR4_MUST_ON
    mov  rcx, VMCS_GUEST_CR4
    vmwrite rcx, rax

    mov  rax, [rel vm_guest_cr3]
    test rax, rax
    jnz  .usar_cr3_proprio
    lea  rax, [rel pml4_table]   
.usar_cr3_proprio:
    mov  rcx, VMCS_GUEST_CR3
    vmwrite rcx, rax

    mov  rax, 0x1                
    mov  rcx, VMCS_CTRL_EXEC
    vmwrite rcx, rax

    mov  rax, 0x11               
    mov  rcx, VMCS_CTRL_ENTRY
    vmwrite rcx, rax

    mov  rax, [rel vm_guest_rip]
    mov  rcx, VMCS_GUEST_RIP
    vmwrite rcx, rax

    lea  rax, [rel vm_guest_stack + 8192]
    mov  [rel vm_guest_rsp], rax
    mov  rcx, VMCS_GUEST_RSP
    vmwrite rcx, rax

    mov  rax, 1                  
    ret

.vmcs_erro:
    xor  rax, rax
    ret

global vm_launch
vm_launch:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    vmlaunch

    jc   .falha_vmlaunch

    mov  rax, 1
    jmp  .fim

.falha_vmlaunch:
    mov  rcx, VMCS_EXIT_REASON
    vmread rax, rcx
    mov  rdx, rax                
    xor  rax, rax                

.fim:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    ret

global vm_load_guest
vm_load_guest:
    mov  r8, rdi                 
    rep movsb                    

    lea  rax, [rel vm_guest_rip]
    mov  [rax], r8
    ret

section .rodata
align 16
global vm_test_guest_code
global vm_test_guest_len

vm_test_guest_code:
    bits 64
    mov  al, 'V'
    mov  ah, 0x0F                
    mov  [0xB8000], ax           

    ud2                          
vm_test_guest_len equ $ - vm_test_guest_code

section .bss
rbx_temp_ptr_save_if_needed: resq 1
