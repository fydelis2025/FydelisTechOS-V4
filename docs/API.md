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

## 📝 Licença

Distribuído sob a licença MIT — veja [LICENCA.md](docs/LICENCA.md) para detalhes.

**FydelisTechOS** | 2024–2026
