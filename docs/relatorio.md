# 📝 FydelisTech OS — Relatório de Evolução e Marcos Recentes de Desenvolvimento

**Projeto:** FydelisTech OS — Sistema Operacional Independente
**Desenvolvedor:** Fydelis • Salvador, Bahia • Brasil
**Data:** 22 de novembro de 2026
**Versão:** 4.2 — Atualização de Componentes Principais
**Repositório:** [https://github.com/fydelis2025/FydelisTechOS-V2](https://github.com/fydelis2025/FydelisTechOS-V2)

---

## 📌 Resumo

O FydelisTech OS, sistema operacional desenvolvido inteiramente do zero em ambiente bare-metal, registra hoje um marco significativo: a conclusão e integração de quatro módulos fundamentais que ampliam sua arquitetura de forma substancial. Este artigo apresenta cada componente recém-concluído, sua finalidade técnica, características de implementação e como se inserem no ecossistema geral do sistema.

---

## 🎯 Introdução

Desde sua concepção, o FydelisTech OS vem sendo construído segundo princípios de independência — sem herança de código de terceiros, sem dependência de bibliotecas externas e com foco total em controle sobre cada camada do sistema. O projeto evoluiu de um simples interpretador de modo texto 80×25 para um sistema operacional funcional com interface gráfica, gerenciamento de janelas, suporte a rede e agora com um subsistema de segurança e armazenamento nativo completo. Os avanços registrados hoje representam a consolidação da camada de confiança do sistema operacional.

---

## 🔧 Quatro Módulos Concluídos e Integrados

### 1️⃣ Fydelis-Cipher — Cifra de Bloco Nativa

**Arquivo:** `grafico/cifra/fydcipher.asm`

A primeira contribuição de hoje é uma cifra de bloco projetada especificamente para o FydelisTech OS. Diferente de implementações de algoritmos conhecidos, esta é uma cifra original, concebida, analisada e codificada no decorrer do desenvolvimento do sistema.

Tabela

| Especificação | Valor |
| --- | --- |
| **Estrutura** | Feistel Generalizado, 4 ramos |
| **Tamanho de bloco** | 128 bits |
| **Tamanho de chave** | 256 bits |
| **Rodadas** | 24 |
| **Função interna** | ARX (Adição, Rotação, XOR) |
| **Modo de disco** | XTS com operação em GF(2¹²⁸) |
| **Idioma de implementação** | Assembly x86-64 |

A cifra opera com estrutura de chave independente, agendamento de subchaves baseado em difusão derivada e modo XTS nativo para criptografia transparente de dispositivos de armazenamento. Representa um passo importante rumo a uma pilha criptográfica totalmente autônoma.

---

### 2️⃣ FYDB — Banco de Dados Nativo do Kernel

**Arquivo:** `kernel/fydb.asm`

O segundo módulo recém-concluído é um sistema de banco de dados estruturado, operando diretamente sobre a camada de arquivos do sistema operacional, sem dependência de bibliotecas de sistema gerenciador de banco externo.

Tabela

| Característica | Detalhe |
| --- | --- |
| **Formato de arquivo** | `.fydb` — cabeçalho de 64 bytes + registros de tamanho fixo |
| **Tamanho máximo de registro** | 512 bytes |
| **Operações implementadas** | inicializar, ler, escrever, inserir, remover, buscar, contar, proteger |
| **Persistência** | Síncrona — cada operação atualiza o disco imediatamente |
| **Integração** | Sistema de permissões FydPerm + campos reservados para criptografia por registro |

O FYDB foi projetado para armazenamento de configurações do sistema, registros de eventos, tabelas de usuários e aplicações nativas que demandem estrutura de dados organizada, tudo mantendo a filosofia de leveza e velocidade do núcleo.

---

### 3️⃣ Fydelis-Crypto — Biblioteca de Primitivas Criptográficas

**Arquivo:** `kernel/crypto/fycrypto.asm`

Terceiro componente concluído: uma biblioteca de funções criptográficas essenciais, implementadas em Assembly puro, disponíveis para todo o sistema.

Tabela

| Primitiva | Finalidade |
| --- | --- |
| SHA-256 | Função de hash criptográfica — integridade de dados |
| HMAC-SHA256 | Código de autenticação — verificação de origem e integridade |
| AES-256-GCM | Criptografia autenticada — referência e compatibilidade |
| PBKDF2-HMAC-SHA256 | Derivação de chave — proteção de senhas |

Esta biblioteca serve de fundação para os demais componentes de segurança do sistema, fornecendo funções verificáveis e auditáveis sem recurso a implementações externas.

---

### 4️⃣ FydPerm — Sistema Nativo de Controle de Acesso e Permissões

**Arquivo:** `kernel/fydperm.asm`

Quarto módulo integrado hoje: um modelo de permissões projetado para o FydelisTech OS, operando em conjunto com o banco de dados e o sistema de arquivos.

Tabela

| Aspecto | Funcionamento |
| --- | --- |
| **Escopo** | Definição de níveis de acesso: usuário, sistema, kernel, somente-leitura, bloqueado |
| **Armazenamento** | 16 bytes integrados diretamente no cabeçalho do arquivo `.fydb` e em atributos de arquivos do sistema |
| **Verificação** | `fydperm_verificar()` — chamada antes de operações de leitura e escrita |
| **Bloqueio** | `fydperm_bloquear_fydb()` — elevação para acesso restrito ao kernel |

O FydPerm fecha a arquitetura de segurança do sistema, garantindo que cada componente possa definir e aplicar suas próprias regras de acesso sem delegar essa responsabilidade a camadas externas.

---

## 🔗 Integração dos Componentes

Abaixo é apresentada a relação entre os quatro novos módulos e as camadas pré-existentes do sistema:

```
┌──────────────────────────────────────────────────────┐
│             Aplicações e Interface Gráfica            │
├──────────────────────────────────────────────────────┤
│   ┌──────────┐    ┌──────────────┐    ┌────────────┐  │
│   │  FYDB    │◄──►│  FydPerm     │◄───►│ Sistema de │  │
│   │ (Banco)  │    │ (Permissões) │    │ Arquivos   │  │
│   └────┬─────┘    └──────────────┘    └────────────┘  │
│        │                                               │
│   ┌────▼──────┐      ┌──────────────┐                 │
│   │ Fydelis-  │◄────►│ Fydelis-     │                 │
│   │ Cipher    │      │ Crypto (SHA, │                 │
│   │           │      │ AES, PBKDF2) │                 │
│   └───────────┘      └──────────────┘                 │
├──────────────────────────────────────────────────────┤
│                Núcleo do Sistema Operacional          │
└──────────────────────────────────────────────────────┘
```

Cada módulo foi projetado para operar de forma independente, mas com pontos de integração claramente definidos:

- O **FYDB** utiliza o **FydPerm** para validar acesso aos registros na abertura
- O **FYDB** reserva espaço no cabeçalho para uso da **Fydelis-Cipher** na criptografia de registros
- A **Fydelis-Cipher** pode ser substituída por algoritmos da **Fydelis-Crypto** conforme requisitos de compatibilidade
- A **FydPerm** pode ser aplicada a arquivos, bancos de dados e recursos de sistema de forma uniforme

---

## 📈 Evolução e Perspectivas

Com a conclusão destes quatro módulos, o FydelisTech OS passa a contar com:

Tabela

| Marco | Status Anterior | Situação Atual |
| --- | --- | --- |
| Interface gráfica funcional | ✅ Concluído | Mantido e otimizado |
| Drivers de rede e Wi-Fi | ✅ Concluído | Mantido e documentado |
| Sistema de arquivos | ✅ Concluído | Mantido |
| Banco de dados nativo | ⏳ Em desenvolvimento | ✅ **Concluído hoje** |
| Cifra de bloco nativa | ⏳ Em desenvolvimento | ✅ **Concluído hoje** |
| Biblioteca criptográfica | ⏳ Em desenvolvimento | ✅ **Concluído hoje** |
| Sistema de permissões | ⏳ Em desenvolvimento | ✅ **Concluído hoje** |

### Próximos Passos

- 🔄 **Criptografia automática no FYDB:** ligação direta entre Fydelis-Cipher e operações de leitura/escrita do banco
- 📖 **Documentação de vetores de teste:** para cada função criptográfica, garantindo correção e possibilidade de auditoria
- 🔍 **Revisão de código comunitária:** convite a desenvolvedores para análise e sugestões nos repositórios públicos
- 📝 **Manual de integração:** guia de uso das APIs para desenvolvedores que desejem construir sobre estes componentes

---

## 🎓 Considerações Finais

Construir um sistema operacional do zero é, por natureza, um exercício de persistência. Cada componente — desde o primeiro prompt de texto até este conjunto de módulos concluídos hoje — representa não apenas código escrito, mas compreensão acumulada de como hardware, memória, arquivos e segurança interagem entre si.

O mais relevante deste marco não é apenas que o FydelisTech OS agora dispõe de cifra própria, banco de dados, biblioteca criptográfica e sistema de permissões, mas sim que **tudo foi construído de forma coerente, integrada e independente**. Não há aqui peças importadas de projetos alheios; cada linha foi escrita para este propósito específico.

Que este trabalho sirva como prova de que é possível aprender, construir e compartilhar conhecimento a partir do zero, com paciência, organização e dedicação.

> 
> *"Do modo texto 80×25 até este ponto — cada linha foi escrita em Salvador, Bahia. Compartilhado para que outros também possam começar os seus próprios projetos."*

— FydelisTech OS, 22 de novembro de 2026
