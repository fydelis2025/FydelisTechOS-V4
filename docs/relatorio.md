# 📝 FydelisTech OS — Relatório de Evolução e Marcos Recentes de Desenvolvimento

**Projeto:** FydelisTech OS — Sistema Operacional Independente  
**Desenvolvedor:** Adiel Santos Fontes • Salvador, Bahia • Brasil  
**Data:** 22 de novembro de 2026  
**Versão:** 4.2 — Atualização de Componentes Principais  
**Repositório:** [https://github.com/fydelis2025/FydelisTechOS-V2](https://github.com/fydelis2025/FydelisTechOS-V2)

---

## 📌 Resumo

O **FydelisTech OS**, sistema operacional desenvolvido inteiramente do zero em ambiente bare-metal, registra hoje um marco significativo: a conclusão e integração de quatro módulos fundamentais de segurança e persistência, além da expansão de sua interface gráfica nativa. Este documento apresenta cada componente recém-concluído, sua finalidade técnica, características de implementação e como se inserem na arquitetura geral do sistema.

---

## 🎯 Introdução

Desde sua concepção, o FydelisTech OS vem sendo construído segundo princípios de independência — sem herança de código de terceiros, sem dependência de bibliotecas externas e com controle total sobre cada camada do sistema. O projeto evoluiu de um interpretador em modo texto 80×25 para um sistema operacional funcional com interface gráfica, gerenciamento de janelas, pilha de rede, aplicativos nativos e agora um subsistema completo de segurança e armazenamento estruturado.

---

## 🔧 Quatro Módulos de Segurança e Dados Concluídos

### 1️⃣ Fydelis-Cipher — Cifra de Bloco Nativa

**Arquivo:** `segurancafydcipher.asm`

Cifra de bloco projetada especificamente para o FydelisTech OS, concebida, analisada e codificada em Assembly durante o desenvolvimento do sistema.

| Especificação | Valor |
| --- | --- |
| **Estrutura** | Feistel Generalizado, 4 ramos |
| **Tamanho de bloco** | 128 bits |
| **Tamanho de chave** | 256 bits |
| **Rodadas** | 24 |
| **Função interna** | ARX (Adição, Rotação, XOR) |
| **Modo de disco** | XTS com operação em GF(2¹²⁸) |
| **Linguagem de implementação** | Assembly x86-64 |

Opera com estrutura de chave independente, agendamento de subchaves baseado em difusão derivada e modo XTS nativo para criptografia transparente de dispositivos de armazenamento.

---

### 2️⃣ FYDB — Banco de Dados Nativo do Kernel

**Arquivo:** `seguranca/fydb.asm`

Sistema de banco de dados estruturado operando diretamente sobre a camada de arquivos do sistema operacional, sem dependência de SGBDs externos.

| Característica | Detalhe |
| --- | --- |
| **Formato de arquivo** | `.fydb` — cabeçalho de 64 bytes + registros de tamanho fixo |
| **Tamanho máximo de registro** | 512 bytes |
| **Operações implementadas** | inicializar, ler, escrever, inserir, remover, buscar, contar, proteger |
| **Persistência** | Síncrona — cada operação atualiza o disco imediatamente |
| **Integração** | Sistema de permissões FydPerm + campos reservados para criptografia por registro |

Projetado para armazenamento de configurações do sistema, registros de eventos, tabelas de usuários e aplicações nativas com foco em leveza e determinismo.

---

### 3️⃣ Fydelis-Crypto — Biblioteca de Primitivas Criptográficas

**Arquivo:** `kernel/crypto/fycrypto.asm`

Biblioteca de funções criptográficas essenciais implementadas em Assembly puro, disponíveis para todo o núcleo e serviços do sistema.

| Primitiva | Finalidade |
| --- | --- |
| **SHA-256** | Função de hash criptográfica — integridade de dados |
| **HMAC-SHA256** | Código de autenticação — verificação de origem e integridade |
| **AES-256-GCM** | Criptografia autenticada — referência e compatibilidade |
| **PBKDF2-HMAC-SHA256** | Derivação de chave — proteção de senhas |

---

### 4️⃣ FydPerm — Sistema Nativo de Controle de Acesso e Permissões

**Arquivo:** `seguranca/fydperm.asm`

Modelo de permissões projetado para o FydelisTech OS, operando em conjunto com o banco de dados e o sistema de arquivos.

| Aspecto | Funcionamento |
| --- | --- |
| **Escopo** | Níveis de acesso: usuário, sistema, kernel, somente-leitura e bloqueado |
| **Armazenamento** | 16 bytes integrados no cabeçalho `.fydb` e nos atributos de arquivos |
| **Verificação** | `fydperm_verificar()` — validada antes de operações de leitura e escrita |
| **Bloqueio** | `fydperm_bloquear_fydb()` — elevação para acesso restrito ao kernel |

---

## 🖥️ Evolução da Interface Gráfica e Aplicativos Nativos

Em paralelo à camada de segurança, a sessão gráfica do sistema recebeu melhorias diretas de usabilidade e produtividade:

- **FydelNotes (`kernel/app/fydnotes.c`):** Editor de notas nativo integrado ao VFS/FAT32 com múltiplas abas, numeração de linhas, barra de status em tempo real, gravação em `/fyd/usuario/documentos` e área de escrita em alto contraste.
- **Painel de Controle e Gerenciamento de Janelas (`kernel/exec.c`):** Suporte a movimentação livre de janelas na área de trabalho, abertura unificada de configurações e ajuste proporcional do Menu Iniciar.

---

## 🔗 Integração dos Componentes

```text
+----------------------------------------------------+
|         Aplicações e Interface Gráfica             |
|       (FydelNotes, Painel de Controle, VFS)        |
+----------------------------------------------------+
|  +----------+    +------------+    +------------+  |
|  |   FYDB   |<-->|  FydPerm   |<-->| Sistema de |  |
|  | (Banco)  |    |(Permissões)|    |  Arquivos  |  |
|  +----+-----+    +------------+    +------------+  |
|       |                                            |
|  +----v------+      +---------------------------+  |
|  | Fydelis-  |<---->| Fydelis-Crypto            |  |
|  | Cipher    |      | (SHA, AES, PBKDF2)        |  |
|  +-----------+      +---------------------------+  |
+----------------------------------------------------+
|          Núcleo do Sistema Operacional             |
+----------------------------------------------------+
