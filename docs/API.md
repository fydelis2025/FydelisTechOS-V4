# 🚀 API FydelisTechOS-V4

> **Sistema Operacional Bare-Metal — Interface de Programação de Aplicativos (C, C++ e Assembly)**

![Versão](https://img.shields.io/badge/vers%C3%A3o-V4-blue)
![Estado](https://img.shields.io/badge/desenvolvimento-ativo-green)
![C](https://img.shields.io/badge/C-dispon%C3%ADvel-orange)
![C++](https://img.shields.io/badge/C++-em--implanta%C3%A7%C3%A3o-purple)
![Licença](https://img.shields.io/badge/licen%C3%A7a-MIT-yellow)

---

## 📌 Sobre

A **API FydelisTechOS-V4** fornece acesso nativo e de baixo nível aos serviços do sistema operacional **FydelisTechOS**, projetada para operação **bare-metal** sem dependência de bibliotecas padrão externas.

* **Disponível em C:** implementação estável e pronta para uso.
* **Em implantação para C++:** suporte gradual a wrappers e abstrações C++ em desenvolvimento.
* **Suporte a Assembly (x86_64):** acesso direto via convenção de chamada documentada e arquivos `.inc`.
* **Foco em segurança:** módulos de criptografia, permissões, auditoria e proteção integrados.

---

## 📂 Estrutura da API

```text
include/
├── syscalls/                  # Tabela de chamadas de sistema
│   ├── fydelis_core.h         # Base — números, status e definições da API
│   ├── security_syscalls.h    # Segurança, permissões e auditoria
│   ├── rede_syscalls.h        # Rede, sockets e hosts
│   ├── user_syscalls.h        # Gestão de usuários e sessões
│   ├── partition_syscalls.h   # Discos e sistemas de arquivos
│   ├── virtual_syscalls.h     # Memória virtual
│   ├── input_syscalls.h       # Teclado e mouse
│   ├── graphics_syscalls.h    # Renderização e interface gráfica
│   └── device_syscalls.h      # USB, Bluetooth e conectividade
├── fycrypto.h                 # Primitivas criptográficas
├── fydcipher.h                # Cifras e codificação
├── fyd_auth.h                 # Autenticação (incluindo 2FA/TOTP)
├── fydlog.h                   # Logs e auditoria
├── fydperm.h                  # Controle de permissões
├── cve_guard.h                # Proteção contra vulnerabilidades
└── fydb.h                     # Persistência e banco de dados leve
```

---

## 🚀 Começando — C

```c
#include "fydelis_core.h"
#include "security_syscalls.h"
#include "fydlog.h"

int main(void) {
    if (fy_security_init() != FY_OK) {
        return -1;
    }

    fy_log_event(FY_LOG_INFO, "Aplicativo inicializado");
    return 0;
}
```

> **Nota sobre C++:** A API nativa em C++ está em fase de implantação. Enquanto os cabeçalhos `.hpp` são concluídos, os cabeçalhos `.h` já podem ser incluídos em código C++ com `extern "C"`.

---

## 📚 Documentação

* [Arquitetura da API →](docs/ARQUITETURA.md)
* [Referência de Funções →](docs/REFERENCIA.md)
* [Guia de Migração C → C++ →](docs/CPP_MIGRACAO.md)
* [Contribuindo →](docs/CONTRIBUIR.md)

---

## 🛠️ Estado do Projeto

| Camada / Linguagem | Status |
| :--- | :--- |
| **C (C99/C11)** | ✅ Disponível e estável |
| **Assembly (x86_64)** | ✅ Camada de baixo nível e constantes `.inc` |
| **C++ (C++17+)** | 🔄 Em implantação — compatibilidade via `extern "C"` |

---

# 📘 Exemplos de Uso — API FydelisTechOS-V4

Exemplos práticos em **C** e **C++** para os módulos principais da API do **FydelisTechOS**: criptografia (`fycrypto.h` e `fydelis_cipher.h`), gráficos (`graphics.h`), rede/Wi-Fi (`rede_syscalls.h`) e disco/partições (`disktools_syscalls.h` e `particao_syscalls.inc`).

> [!NOTE]
> Como `graphics.h`, `rede_syscalls.h` e `disktools_syscalls.h` são cabeçalhos em C, envolver o `#include` em `extern "C" { ... }` no código C++ garante a ligação correta com os símbolos compilados em C.

---

## Sumário

- [1. Criptografia (`fycrypto.h` e `fydelis_cipher.h`)](#1-criptografia-fycryptoh-e-fydelis_cipherh)
- [2. Gráficos & Framebuffer (`graphics.h`)](#2-gráficos--framebuffer-graphicsh)
- [3. Rede & Wi-Fi (`rede_syscalls.h`)](#3-rede--wi-fi-rede_syscallsh)
- [4. Ferramentas de Disco & Partições (`disktools_syscalls.h` e `particao_syscalls.inc`)](#4-ferramentas-de-disco--partições-disktools_syscallsh-e-particao_syscallsinc)

---

## 1. Criptografia (`fycrypto.h` e `fydelis_cipher.h`)

### Exemplo em C

```c
#include <stdio.h>
#include <string.h>
#include "fycrypto.h"
#include "fydelis_cipher.h"

int main(void) {
    const char *senha = "minha_senha_local";
    const char *sal   = "fydelis_salt_01";
    const char *msg   = "Configuracao protegida do FydelisTechOS";
    const char *aad   = "v4:perfil";

    uint8_t digest[32];
    sha256(digest, msg, strlen(msg));

    /* Derivar chave de 32 bytes (256 bits) com PBKDF2-HMAC-SHA256 */
    uint8_t chave[32];
    pbkdf2_sha256(chave, senha, strlen(senha), sal, strlen(sal), 100000ULL, sizeof(chave));

    /* Cifrar com AES-256-GCM (IV de 12 bytes + tag de 16 bytes) */
    uint8_t iv[12] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
    uint8_t cifrado[128] = {0};
    uint8_t tag[16] = {0};

    AES256_GCM_CTX gcm;
    aes256_gcm_inicia(&gcm, chave, iv);
    aes256_gcm_ad(&gcm, aad, strlen(aad));
    long n_cifrado = aes256_gcm_criptografa(&gcm, msg, cifrado, strlen(msg), tag);

    /* Uso do FydelisCipherCtx em bloco de 16 bytes */
    FydelisCipherCtx fyd_ctx;
    fydcipher_inicia(&fyd_ctx, chave);

    uint8_t bloco_in[FYCIPHER_BLOCO_TAM] = {0};
    uint8_t bloco_out[FYCIPHER_BLOCO_TAM] = {0};
    memcpy(bloco_in, "FYDELISTECH_1234", 16);
    fydcipher_criptografa(&fyd_ctx, bloco_in, bloco_out);

    printf("GCM bytes cifrados: %ld | Bloco cifrado[0]: 0x%02X\n", n_cifrado, bloco_out[0]);

    /* Limpar material sensível da memória */
    crypto_limpa_memoria(chave, sizeof(chave));
    crypto_limpa_memoria(&fyd_ctx, sizeof(fyd_ctx));
    return 0;
}
```

### Exemplo em C++

```cpp
#include <array>
#include <cstdint>
#include <iostream>
#include <string>

extern "C" {
#include "fycrypto.h"
#include "fydelis_cipher.h"
}

namespace fyd {

template <size_t N>
struct SecretBuffer {
    std::array<uint8_t, N> data{};
    ~SecretBuffer() { crypto_limpa_memoria(data.data(), data.size()); }
};

} // namespace fyd

int main() {
    const std::string senha = "minha_senha_local";
    const std::string sal   = "fydelis_salt_01";
    const std::string plano = "Dados da sessao do usuario";

    fyd::SecretBuffer<32> chave;
    pbkdf2_sha256(chave.data.data(), senha.data(), senha.size(),
                  sal.data(), sal.size(), 100000ULL, chave.data.size());

    std::array<uint8_t, 12> iv{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
    std::array<uint8_t, 64> cifrado{};
    std::array<uint8_t, 16> tag{};

    AES256_GCM_CTX ctx;
    aes256_gcm_inicia(&ctx, chave.data.data(), iv.data());
    long len = aes256_gcm_criptografa(&ctx, plano.data(), cifrado.data(),
                                      plano.size(), tag.data());

    std::cout << "Cifrado com sucesso (" << len << " bytes)\n";
    return 0;
}
```

---

## 2. Gráficos & Framebuffer (`graphics.h`)

### Exemplo em C

```c
#include "graphics.h"

int main(void) {
    if (vesa_detectar() != 0) {
        return -1;
    }

    if (vesa_inicializar(1024, 768, 32) != 0) {
        return -1;
    }

    if (framebuffer_mapear() != 0) {
        return -1;
    }

    ModoVideo *modo = obter_modo_atual();
    if (!modo) {
        return -1;
    }

    preencher_retangulo(0, 0, modo->largura, modo->altura, 0xFF10141D);
    preencher_retangulo(40, 40, 420, 140, 0xFF1E2638);
    desenhar_texto(60, 70, "FydelisTechOS - Framebuffer Ativo", 0xFFFFFFFF, 0xFF1E2638);
    definir_cursor(120, 120);

    return 0;
}
```

### Exemplo em C++

```cpp
#include <cstdint>
#include <iostream>

extern "C" {
#include "graphics.h"
}

namespace fyd {

class Display {
public:
    bool init(int w, int h, int bpp) {
        if (vesa_detectar() != 0) return false;
        if (vesa_inicializar(w, h, bpp) != 0) return false;
        if (framebuffer_mapear() != 0) return false;
        mode_ = obter_modo_atual();
        return mode_ != nullptr;
    }

    void clear(uint32_t argb) {
        if (!mode_) return;
        preencher_retangulo(0, 0, mode_->largura, mode_->altura, argb);
    }

    void panel(int x, int y, int w, int h, uint32_t bg, const char* label, uint32_t fg) {
        preencher_retangulo(x, y, w, h, bg);
        if (label) {
            desenhar_texto(x + 16, y + 16, label, fg, bg);
        }
    }

private:
    ModoVideo* mode_ = nullptr;
};

} // namespace fyd

int main() {
    fyd::Display display;
    if (!display.init(1024, 768, 32)) {
        std::cerr << "Falha ao inicializar video\n";
        return 1;
    }

    display.clear(0xFF0B0F17);
    display.panel(50, 50, 380, 100, 0xFF1A2234, "App C++ no FydelisTechOS", 0xFF00E5FF);
    return 0;
}
```

---

## 3. Rede & Wi-Fi (`rede_syscalls.h`)

### Exemplo em C

```c
#include <stdio.h>
#include "rede_syscalls.h"

int main(void) {
    if (rede_inicializar() != 0) {
        printf("Erro ao inicializar rede\n");
        return -1;
    }

    printf("Interface: %s | Link: %d\n", rede_ler_iface_nome(), rede_ler_status_link());

    if (wifi_detectar_placa() == 0 && wifi_inicializar() == 0) {
        WifiRede *rede = sys_wifi_scan();
        while (rede != NULL) {
            printf("SSID: %s | Sinal: %d dBm | Seg: %s\n",
                   rede->ssid, rede->sinal, rede->seguranca);
            rede = (WifiRede *)rede->proximo;
        }
    }

    rede_exec_ping("192.168.1.1");
    return 0;
}
```

### Exemplo em C++

```cpp
#include <iostream>

extern "C" {
#include "rede_syscalls.h"
}

int main() {
    if (rede_inicializar() != 0) {
        std::cerr << "Falha ao iniciar pilha de rede\n";
        return 1;
    }

    const char* iface = rede_ler_iface_nome();
    std::cout << "Interface: " << (iface ? iface : "desconhecida")
              << " | Link: " << rede_ler_status_link() << "\n";

    if (wifi_detectar_placa() == 0 && wifi_inicializar() == 0) {
        for (WifiRede* r = sys_wifi_scan(); r != nullptr; r = static_cast<WifiRede*>(r->proximo)) {
            std::cout << "Wi-Fi: " << r->ssid << " (" << r->sinal << " dBm)\n";
        }
    }

    rede_exec_ping("192.168.1.1");
    return 0;
}
```

---

## 4. Ferramentas de Disco & Partições (`disktools_syscalls.h` e `particao_syscalls.inc`)

### Exemplo em C

```c
#include <inttypes.h>
#include <stdio.h>
#include "disktools_syscalls.h"

/* Constantes alinhadas a particao_syscalls.inc */
enum {
    FY_SYS_DISCO_LER      = 100,
    FY_SYS_DISCO_ESCREVER = 101,
    FY_SYS_TAMANHO_DISCO  = 106
};

extern long fy_syscall_disco(long num, long a1, long a2, long a3);

int main(void) {
    const char *disco = "/dev/sda";
    const char *unidade = "/mnt/root";

    uint64_t livre = calcular_espaco_livre(unidade);
    int status_fs = verificar_sistema_arquivos(unidade);

    char id_disco[64] = {0};
    obter_identificador_disco(disco, id_disco, (int)sizeof(id_disco));

    printf("Disco: %s | ID: %s | Livre: %" PRIu64 " bytes | FS: %d\n",
           disco, id_disco, livre, status_fs);

    uint8_t setor[512] = {0};
    long rc = fy_syscall_disco(FY_SYS_DISCO_LER, (long)disco, 0, (long)setor);
    printf("Leitura setor 0 rc: %ld\n", rc);
    return 0;
}
```

### Exemplo em C++

```cpp
#include <array>
#include <cstdint>
#include <iostream>
#include <string>

extern "C" {
#include "disktools_syscalls.h"
}

int main() {
    const std::string disco = "/dev/sda";
    const std::string ponto_montagem = "/mnt/root";

    std::array<char, 64> id{};
    obter_identificador_disco(disco.c_str(), id.data(), static_cast<int>(id.size()));

    uint64_t espaco_livre = calcular_espaco_livre(ponto_montagem.c_str());
    int fs_ok = verificar_sistema_arquivos(ponto_montagem.c_str());

    std::cout << "Disco: " << disco
              << " | ID: " << id.data()
              << " | Espaco livre: " << espaco_livre
              << " | Verificacao FS: " << fs_ok << "\n";
    return 0;
}
```

# 📖 Referência Completa da API — FydelisTechOS-V4

Documentação de referência para os cabeçalhos **C** (`extern "C"` compatível com **C++**) e definições **Assembly** (`particao_syscalls.inc`) do **FydelisTechOS-V4**.

> [!NOTE]
> Todos os símbolos listados abaixo podem ser consumidos em C diretamente e em C++ por meio de `extern "C" { ... }` até a conclusão dos wrappers nativos `.hpp`.

---

## Sumário

- [1. Criptografia — `fycrypto.h`](#1-criptografia--fycryptoh)
- [2. Cifra Nativa — `fydelis_cipher.h`](#2-cifra-nativa--fydelis_cipherh)
- [3. Gráficos & Framebuffer — `graphics.h`](#3-gráficos--framebuffer--graphicsh)
- [4. Rede & Wi-Fi — `rede_syscalls.h`](#4-rede--wi-fi--rede_syscallsh)
- [5. Ferramentas de Disco & Partições — `disktools_syscalls.h` e `particao_syscalls.inc`](#5-ferramentas-de-disco--partições--disktools_syscallsh-e-particao_syscallsinc)

---

## 1. Criptografia — `fycrypto.h`

### Estruturas de Contexto

| Estrutura | Tamanho Fixo | Descrição |
| :--- | :--- | :--- |
| `SHA256_CTX` | `128` bytes | Estado interno para hashing SHA-256 incremental (`opaque[128]`). |
| `HMAC_SHA256_CTX` | `384` bytes | Estado interno para HMAC-SHA256 incremental (`opaque[384]`). |
| `AES256_CTX` | `240` bytes | Chaves expandidas e estado para AES-256 (`opaque[240]`). |
| `AES256_GCM_CTX` | `352` bytes | Estado autenticado para cifragem/decifragem AES-256-GCM (`opaque[352]`). |

### Funções — SHA-256

| Assinatura | Descrição |
| :--- | :--- |
| `void sha256_inicia(SHA256_CTX *ctx)` | Inicializa o contexto SHA-256. |
| `void sha256_adiciona(SHA256_CTX *ctx, const void *dados, size_t tam)` | Alimenta `tam` bytes de `dados` ao hash em andamento. |
| `void sha256_finaliza(SHA256_CTX *ctx, uint8_t digest[32])` | Finaliza o cálculo e grava o digest de 32 bytes em `digest`. |
| `void sha256(void *saida, const void *dados, size_t tam)` | Calcula o SHA-256 de `dados` (`tam` bytes) em uma chamada única gravando em `saida`. |

### Funções — HMAC-SHA256

| Assinatura | Descrição |
| :--- | :--- |
| `void hmac_sha256_inicia(HMAC_SHA256_CTX *ctx, const void *chave, size_t tam_chave)` | Inicializa o contexto HMAC-SHA256 com `chave` de `tam_chave` bytes. |
| `void hmac_sha256_adiciona(HMAC_SHA256_CTX *ctx, const void *dados, size_t tam)` | Incorpora `tam` bytes de `dados` na autenticação HMAC. |
| `void hmac_sha256_finaliza(HMAC_SHA256_CTX *ctx, uint8_t tag[32])` | Finaliza e escreve a tag de autenticação de 32 bytes em `tag`. |
| `void hmac_sha256(uint8_t tag[32], const void *chave, size_t tam_chave, const void *dados, size_t tam)` | Computa o HMAC-SHA256 em uma chamada direta e grava em `tag`. |

### Funções — AES-256 (Bloco e CBC)

| Assinatura | Descrição |
| :--- | :--- |
| `void aes256_inicia(AES256_CTX *ctx, const uint8_t chave[32])` | Expande a chave de 256 bits (32 bytes) no contexto `ctx`. |
| `void aes256_criptografa_bloco(AES256_CTX *ctx, const uint8_t in[16], uint8_t out[16])` | Cifra um bloco único de 16 bytes (`in` -> `out`). |
| `void aes256_descriptografa_bloco(AES256_CTX *ctx, const uint8_t in[16], uint8_t out[16])` | Decifra um bloco único de 16 bytes (`in` -> `out`). |
| `long aes256_cbc_criptografa(AES256_CTX *ctx, const uint8_t iv[16], const void *in, void *out, size_t tam)` | Cifra buffer de `tam` bytes em modo CBC usando vetor de inicialização `iv` (16 bytes). |
| `long aes256_cbc_descriptografa(AES256_CTX *ctx, const uint8_t iv[16], const void *in, void *out, size_t tam)` | Decifra buffer de `tam` bytes em modo CBC usando `iv` (16 bytes). |

### Funções — AES-256-GCM

| Assinatura | Descrição |
| :--- | :--- |
| `void aes256_gcm_inicia(AES256_GCM_CTX *ctx, const uint8_t chave[32], const uint8_t iv[12])` | Inicializa o contexto GCM com `chave` (32 bytes) e nonce/IV (12 bytes). |
| `void aes256_gcm_ad(AES256_GCM_CTX *ctx, const void *dados_associados, size_t tam)` | Adiciona dados autenticados adicionais (AAD) não cifrados ao cálculo da tag. |
| `long aes256_gcm_criptografa(AES256_GCM_CTX *ctx, const void *plano, void *cifrado, size_t tam, uint8_t tag[16])` | Cifra `plano` (`tam` bytes) para `cifrado` e gera a `tag` de integridade de 16 bytes. |
| `long aes256_gcm_descriptografa(AES256_GCM_CTX *ctx, const void *cifrado, void *plano, size_t tam, const uint8_t tag[16])` | Valida a `tag` de 16 bytes e decifra `cifrado` (`tam` bytes) para `plano`. |

### Derivação de Chave e Utilitários

| Assinatura | Descrição |
| :--- | :--- |
| `void pbkdf2_sha256(uint8_t *dk, const void *senha, size_t tam_senha, const void *sal, size_t tam_sal, uint64_t iteracoes, size_t dk_len)` | Deriva chave `dk` de `dk_len` bytes a partir de `senha` e `sal` após `iteracoes` rodadas de PBKDF2-HMAC-SHA256. |
| `void crypto_limpa_memoria(void *ptr, size_t tam)` | Zera `tam` bytes de memória sensível evitando otimizações de remoção pelo compilador. |
| `int crypto_compara_constante_tempo(const void *a, const void *b, size_t tam)` | Compara `tam` bytes entre `a` e `b` em tempo constante para mitigar ataques de temporização. |

---

## 2. Cifra Nativa — `fydelis_cipher.h`

### Constantes e Estruturas

| Constante / Tipo | Valor / Tamanho | Descrição |
| :--- | :--- | :--- |
| `FYCIPHER_BLOCO_TAM` | `16` | Tamanho do bloco em bytes (128 bits). |
| `FYCIPHER_CHAVE_TAM` | `32` | Tamanho da chave principal em bytes (256 bits). |
| `FYCIPHER_RODADAS` | `24` | Quantidade de rodadas Feistel de 4 ramos + ARX. |
| `FydelisCipherCtx` | `208` bytes | Contexto com `whitening[4]` (16 bytes) e `subchaves[24][2]` (192 bytes). |

### Funções Públicas

| Assinatura | Descrição |
| :--- | :--- |
| `void fydcipher_inicia(FydelisCipherCtx *ctx, const uint8_t chave[FYCIPHER_CHAVE_TAM])` | Expande a chave de 256 bits nas palavras de `whitening` e nas 48 subchaves das 24 rodadas. |
| `void fydcipher_criptografa(const FydelisCipherCtx *ctx, const uint8_t entrada[FYCIPHER_BLOCO_TAM], uint8_t saida[FYCIPHER_BLOCO_TAM])` | Cifra um bloco de 16 bytes (`entrada` -> `saida`). |
| `void fydcipher_descriptografa(const FydelisCipherCtx *ctx, const uint8_t entrada[FYCIPHER_BLOCO_TAM], uint8_t saida[FYCIPHER_BLOCO_TAM])` | Decifra um bloco de 16 bytes (`entrada` -> `saida`). |
| `long fydcipher_xts_criptografa(const FydelisCipherCtx *ctx, uint64_t numero_setor, void *dados, size_t tam)` | Cifra `dados` *in-place* no modo XTS com *tweak* por `numero_setor` (`tam` múltiplo de 16; `0` = ok, `-1` = tamanho inválido). |
| `long fydcipher_xts_descriptografa(const FydelisCipherCtx *ctx, uint64_t numero_setor, void *dados, size_t tam)` | Decifra `dados` *in-place* no modo XTS com *tweak* por `numero_setor` (`tam` múltiplo de 16; `0` = ok, `-1` = tamanho inválido). |

---

## 3. Gráficos & Framebuffer — `graphics.h`

### Estrutura `ModoVideo`

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `largura` | `int` | Largura ativa do modo de vídeo em pixels. |
| `altura` | `int` | Altura ativa do modo de vídeo em pixels. |
| `bits_por_pixel` | `int` | Profundidade de cor (ex.: `32` para ARGB/XRGB). |
| `pitch` | `int` | Largura de uma linha completa em bytes (*stride*). |
| `endereco_framebuffer` | `uint64_t` | Endereço linear base do *framebuffer*. |
| `tamanho_framebuffer` | `uint64_t` | Tamanho total mapeado do *framebuffer* em bytes. |
| `e_linear` | `int` | Indica se o modo linear de vídeo está ativo. |
| `vesa_versao` | `int` | Versão VESA detectada (quando aplicável). |

### Funções — Inicialização e Informação

| Assinatura | Descrição |
| :--- | :--- |
| `int vesa_detectar(void)` | Detecta suporte e modos VESA disponíveis. |
| `int vesa_inicializar(int largura, int altura, int bpp)` | Configura o modo VESA solicitado (`largura x altura @ bpp`). |
| `int gop_inicializar(void)` | Inicializa o vídeo via protocolo UEFI GOP. |
| `int framebuffer_mapear(void)` | Mapeia a memória do *framebuffer* para acesso gráfico. |
| `ModoVideo* obter_modo_atual(void)` | Retorna ponteiro para a estrutura `ModoVideo` ativa. |
| `int obter_resolucao_nativa(int* largura, int* altura)` | Preenche `largura` e `altura` nativas reportadas pelo vídeo/monitor. |

### Funções — Desenho e Cursor

| Assinatura | Descrição |
| :--- | :--- |
| `void desenhar_pixel(int x, int y, uint32_t cor)` | Escreve um pixel na coordenada `(x, y)` com a `cor` informada. |
| `void preencher_retangulo(int x, int y, int w, int h, uint32_t cor)` | Preenche uma área retangular `(x, y, w, h)` com `cor`. |
| `void desenhar_texto(int x, int y, const char* texto, uint32_t cor_texto, uint32_t cor_fundo)` | Renderiza `texto` em `(x, y)` com `cor_texto` e `cor_fundo`. |
| `void copiar_area(int dx, int dy, int sx, int sy, int w, int h)` | Copia região `(sx, sy, w, h)` para destino `(dx, dy)` (*blit* interno). |
| `void definir_cursor(int x, int y)` | Posiciona o cursor na tela em `(x, y)`. |
| `void definir_tamanho_cursor(int largura, int altura)` | Ajusta as dimensões do cursor (`largura x altura`). |
| `void atualizar_resolucao(int nova_largura, int nova_altura)` | Atualiza a resolução ativa da interface/framebuffer. |

---

## 4. Rede & Wi-Fi — `rede_syscalls.h`

### Constantes e Estrutura `WifiRede`

| Constante / Campo | Tipo / Valor | Descrição |
| :--- | :--- | :--- |
| `WIFI_SSID_MAX` | `33` | Tamanho máximo do buffer de SSID (32 caracteres + `\0`). |
| `WIFI_BSSID_LEN` | `6` | Tamanho do endereço MAC/BSSID em bytes. |
| `WifiRede.ssid` | `char[33]` | Nome da rede sem fio. |
| `WifiRede.bssid` | `uint8_t[6]` | Endereço BSSID do ponto de acesso. |
| `WifiRede.sinal` | `int32_t` | Intensidade de sinal (ex.: dBm). |
| `WifiRede.seguranca` | `char[16]` | Tipo de segurança reportado (ex.: WPA2/WPA3/Open). |
| `WifiRede.proximo` | `void*` | Ponteiro para o próximo nó da lista encadeada de redes. |

### Funções — Rede Geral e Diagnóstico

| Assinatura | Descrição |
| :--- | :--- |
| `int rede_inicializar(void)` | Inicializa a pilha e os drivers de rede. |
| `int rede_status(void)` | Retorna o estado geral do subsistema de rede. |
| `const char* rede_ler_iface_nome(void)` | Retorna o nome da interface de rede ativa. |
| `const uint8_t* rede_ler_mac(void)` | Retorna ponteiro para os 6 bytes do endereço MAC local. |
| `uint32_t rede_ler_ip(void)` | Retorna o endereço IPv4 configurado. |
| `uint32_t rede_ler_mascara(void)` | Retorna a máscara de sub-rede IPv4. |
| `uint32_t rede_ler_gateway(void)` | Retorna o endereço IPv4 do gateway padrão. |
| `uint32_t rede_ler_dns(void)` | Retorna o endereço IPv4 do servidor DNS. |
| `int rede_ler_status_link(void)` | Informa se há link físico/lógico ativo na interface. |
| `uint64_t rede_ler_bytes_rx(void)` | Retorna o total acumulado de bytes recebidos. |
| `uint64_t rede_ler_bytes_tx(void)` | Retorna o total acumulado de bytes transmitidos. |
| `int rede_exec_ping(const char* ip)` | Executa diagnóstico ICMP/ping para o `ip` alvo. |
| `int rede_exec_traceroute(const char* ip)` | Executa rastreamento de rota até o `ip` alvo. |
| `void rede_ler_tabela_arp(void)` | Consulta/exibe a tabela ARP atual. |

### Funções — Wi-Fi, DHCP e Ponte UI → Assembly

| Assinatura | Descrição |
| :--- | :--- |
| `int wifi_detectar_placa(void)` | Detecta hardware Wi-Fi disponível. |
| `int wifi_inicializar(void)` | Inicializa o driver e o estado da interface Wi-Fi. |
| `WifiRede* sys_wifi_scan(void)` | Executa varredura e retorna lista ligada de `WifiRede`. |
| `int sys_wifi_conectar(const char* ssid)` | Inicia conexão com a rede identificada por `ssid`. |
| `int sys_wifi_desconectar(void)` | Encerra a conexão Wi-Fi ativa. |
| `int wifi_ler_status(void)` | Retorna o status atual da conexão Wi-Fi. |
| `int dhcp_cliente_iniciar(void)` | Inicia o cliente DHCP na interface de rede. |
| `int dhcp_exec(void)` | Executa/avança o processo de negociação DHCP. |
| `uint32_t dhcp_ler_ip(void)` | Retorna o IP obtido via DHCP. |
| `int dhcp_servidor_iniciar(void)` | Inicia o serviço de servidor DHCP local. |
| `int dhcp_servidor_parar(void)` | Interrompe o servidor DHCP local. |
| `int dhcp_servidor_status(void)` | Retorna o estado atual do servidor DHCP. |
| `int bridge_wifi_scan(void)` | Ponte direta da interface gráfica/UI para varredura Wi-Fi em Assembly. |
| `int bridge_wifi_conectar(const char* ssid)` | Ponte direta da interface gráfica/UI para conectar ao `ssid` via Assembly. |
| `int bridge_wifi_desconectar(void)` | Ponte direta da interface gráfica/UI para desconectar via Assembly. |

---

## 5. Ferramentas de Disco & Partições — `disktools_syscalls.h` e `particao_syscalls.inc`

### Syscalls em Assembly (`particao_syscalls.inc`)

| Constante (`equ`) | Número | Descrição |
| :--- | :--- | :--- |
| `SYS_DISCO_LER` | `100` | Lê setores/blocos do disco. |
| `SYS_DISCO_ESCREVER` | `101` | Escreve setores/blocos no disco. |
| `SYS_LISTAR_PARTICOES` | `102` | Lista partições encontradas no dispositivo. |
| `SYS_CRIAR_PARTICAO` | `103` | Cria nova partição no disco. |
| `SYS_EXCLUIR_PARTICAO` | `104` | Remove uma partição existente. |
| `SYS_FORMATAR_PARTICAO` | `105` | Formata uma partição com sistema de arquivos. |
| `SYS_TAMANHO_DISCO` | `106` | Consulta a capacidade total do disco. |

### Estrutura Assembly `struc Particao` (`particao_syscalls.inc`)

| Campo | Reserva | Tamanho | Descrição |
| :--- | :--- | :--- | :--- |
| `.dispositivo` | `resb 16` | 16 bytes | Identificador/caminho do dispositivo (ex.: `/dev/sda`). |
| `.nome` | `resb 32` | 32 bytes | Rótulo ou nome da partição. |
| `.sistemaArq` | `resb 16` | 16 bytes | Tipo de sistema de arquivos. |
| `.tamanhoTotal` | `resq 1` | 8 bytes | Tamanho total da partição. |
| `.tamanhoUsado` | `resq 1` | 8 bytes | Espaço utilizado na partição. |
| `.montagem` | `resb 32` | 32 bytes | Ponto de montagem associado. |
| `.ativo` | `resb 1` | 1 byte | Flag de partição ativa/bootável. |
| `.align` | `resb 7` | 7 bytes | Preenchimento de alinhamento (total da estrutura: 120 bytes). |

### Funções — `disktools_syscalls.h`

| Assinatura | Descrição |
| :--- | :--- |
| `int escanear_particoes_perdidas(const char* disco)` | Varre `disco` em busca de partições removidas ou com tabela corrompida. |
| `int recuperar_particao(const char* disco, int numero, const char* caminho_saida)` | Tenta recuperar a partição `numero` de `disco` para `caminho_saida`. |
| `int recuperar_arquivos(const char* particao, const char* filtro, const char* destino)` | Recupera arquivos de `particao` filtrados por `filtro` para `destino`. |
| `int clonar_disco(const char* origem, const char* destino)` | Clona o conteúdo de `origem` diretamente para `destino`. |
| `int criar_imagem(const char* disco, const char* arquivo_img)` | Gera arquivo de imagem `.img` a partir de `disco`. |
| `int restaurar_imagem(const char* arquivo_img, const char* disco)` | Restaura `arquivo_img` para o dispositivo `disco`. |
| `int verificar_setores_defeituosos(const char* disco)` | Testa leitura de setores em `disco` para identificar falhas físicas/lógicas. |
| `int reparar_tabela_particoes(const char* disco)` | Tenta corrigir inconsistências na tabela de partições de `disco`. |
| `int verificar_sistema_arquivos(const char* unidade)` | Verifica integridade do sistema de arquivos montado em `unidade`. |
| `uint64_t calcular_espaco_livre(const char* caminho)` | Retorna o espaço livre disponível em bytes para `caminho`. |
| `int obter_identificador_disco(const char* disco, char* buffer, int tam)` | Escreve o identificador de `disco` em `buffer` (até `tam` bytes). |

## 📝 Licença

Distribuído sob a licença MIT — veja [LICENCA.md](docs/LICENCA.md) para detalhes.

**FydelisTechOS** | 2024–2026
