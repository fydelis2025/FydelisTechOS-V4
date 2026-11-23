# 📝 Registro de Alterações — FydelisTechOS V2

Este arquivo registra as principais mudanças, evoluções e marcos do **FydelisTechOS** e do **FydelTerm**.

> 📌 **Nota:** O projeto está em desenvolvimento ativo. Alterações frequentes podem ocorrer antes de cada marco estável.

---

## 🚧 Em Desenvolvimento

### 🏗️ Em andamento
- Estabilização do fluxo de boot híbrido (**UEFI x64** + **Legacy BIOS**) e montagem automatizada de imagem (`LBA 0` / `LBA 4096` / `LBA 8192+`)
- Integração e testes do subsistema gráfico (`gpu_dispatch`, `virtio_gpu` e fallback linear)
- Refinamento da interface gráfica oficial e da experiência do terminal
- Expansão e padronização da documentação técnica (`docs/`)

---

## 📌 Marcos de Versão

### FydelTerm — Versão 4.2
**Data:** Nov 2026

✅ **Consolidação arquitetural e interface nativa**
- Estrutura modular organizada entre boot, núcleo, drivers, subsistema gráfico, espaço de usuário e ferramentas
- Interface gráfica oficial nativa consolidada, sem dependência de frameworks externos
- Separação clara entre lógica de sistema e camada visual
- Reestruturação completa dos aplicativos migrados para a arquitetura própria
- Documentação reorganizada em `docs/` com guias técnicos e histórico do projeto

> 📖 Esta versão marca o ponto em que, após múltiplas reconstruções e aprendizado acumulado, o projeto consolidou uma base arquitetural própria e sustentável.

---

### Transição de UI — Testes com GTK4 e Adoção de Arquitetura Nativa
**Período:** Out–Nov 2026

🔄 **Migração e desacoplamento**
- Avaliação do **GTK4** após os primeiros protótipos em Qt
- Decisão estratégica de abandonar frameworks externos pesados em favor de uma arquitetura gráfica nativa
- Desacoplamento entre a lógica do sistema e a camada de apresentação
- Mapeamento completo das fronteiras internas entre núcleo, drivers e interface

> ⚠️ Período de maior complexidade arquitetural e refatoração intensa, decisivo para dominar a integração interna do sistema.

---

### Experiência Inicial com Qt
**Período:** Set–Out 2026

🧪 **Primeira interface gráfica com Qt**
- Primeiros protótipos visuais funcionais
- Componentes operando, porém fortemente acoplados ao framework
- Aprendizado inicial sobre comunicação entre interface e núcleo

> 💡 Etapa fundamental para validar requisitos visuais e definir os limites desejados para a arquitetura de longo prazo.

---

### Reestruturações do FydelTerm — Versões 1.x até 4.x
**Período:** Ago–Nov 2026

🔁 **Ciclos de refatoração**
- Reescrita estrutural do código em múltiplas etapas
- Definição clara de escopo e responsabilidades de cada módulo
- Evolução de um interpretador inicial de comandos para um ambiente de terminal estruturado

> 🏆 Cada reestruturação consolidou o aprendizado técnico acumulado nas versões anteriores.

---

### FydelTerm — Conceito Inicial
**Período:** Ago 2026

🌱 **Nascimento do projeto**
- Criação do ambiente de terminal base para o **FydelisTechOS**
- Implementação dos primeiros comandos e rotinas fundamentais

---

## 📖 Legenda dos Emblemas

| Emblema | Significado |
| :--- | :--- |
| ✅ | Marco concluído e estável |
| 🔄 | Alteração ou refatoração |
| 🧪 | Protótipo ou experimento |
| 🏗️ | Em andamento / parcialmente concluído |
| ⚠️ | Desafio ou ponto de atenção |

---

> ✨ *"Cada versão conta uma história — não apenas do que foi construído, mas do que foi aprendido."*
