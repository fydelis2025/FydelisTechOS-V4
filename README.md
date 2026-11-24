# 📚 Documentação — FydelisTechOS / FydelTerm
<div align="center">

[![C](https://img.shields.io/badge/Language-C-00599C?style=for-the-badge&logo=c&logoColor=white)]()
[![GTK4](https://img.shields.io/badge/GUI-GTK4-55A6E0?style=for-the-badge&logo=gtk&logoColor=white)]()
[![FydelTerm](https://img.shields.io/badge/Terminal-FydelTerm-4169E1?style=for-the-badge)]()
[![Version](https://img.shields.io/badge/Version-4.2-228B22?style=for-the-badge)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

</div>

<p align="center">
  <img src="https://github.com/fydelis2025/FydelisTechOS-V2/blob/main/assets/images/logo_menu.png" alt="FydelisTechOS Dashboard" width="40%">
</p>

[![OpenSSF Scorecard](https://github.com/fydelis2025/FydelisTechOS-V4/actions/workflows/scorecard.yml/badge.svg)](https://github.com/fydelis2025/FydelisTechOS-V4/actions/workflows/scorecard.yml)



Bem-vindo ao centro oficial de documentação do **FydelisTechOS — V2**. Aqui você encontra a visão completa do projeto: sua história, arquitetura, estado atual e os caminhos percorridos até chegar onde estamos.

---

## 📑 Índice Geral

### 📖 História e Evolução


| Documento | Descrição |
| --- | --- |
| **FydelTerm — Da Ideia à Versão 4.2** | Origem do projeto, os primeiros passos, as dificuldades iniciais e o aprendizado através de múltiplas reestruturações até a consolidação da versão 4.2 |
| **FydelTerm — Da Linha de Comando à Interface Gráfica** | Experiências com Qt e GTK4, os desafios de compreender a arquitetura completa, os períodos de perda de caminho trabalhando sozinho e a consolidação da interface oficial |
| **Reconstruindo Aplicativos — Da Migração à Estrutura Própria** | Por que aplicativos prontos foram refeitos, a decisão de abandonar estruturas externas e os benefícios de construir sobre uma arquitetura nativa e independente |

### 🏗️ Arquitetura e Sistema


| Documento | Descrição |
| --- | --- |
| **Arquitetura do Sistema** | Visão geral por camadas (`boot`, `kernel`, `drivers`, `grafico`, `user`, `virtual`, `tools`), responsabilidades de cada componente e fluxo de inicialização |
| **Layout de Disco e Boot** | Organização da imagem híbrida, setores de boot, endereçamento LBA e carregamento do kernel |
| **Gráficos e GPU** | Sistema de despacho (`gpu_dispatch`), suporte a `virtio_gpu` e estratégias de fallback genérico |

## 📸 Interface do Sistema

<p align="center">
  <img src="https://github.com/fydelis2025/FydelisTechOS-V2/blob/main/FyelTerm.png" alt="FydelisTechOS Dashboard" width="100%">
</p>
<p align="center">
  <img src="https://github.com/fydelis2025/FydelisTechOS-V2/blob/main/Login.png" alt="FydelisTechOS Dashboard" width="100%">
</p>
<p align="center">
  <img src="https://github.com/fydelis2025/FydelisTechOS-V2/blob/main/Desktop.png" alt="FydelisTechOS Dashboard" width="100%">
</p>

---

## 🧠 Sobre o Projeto

### O Que É o FydelisTechOS?

O **FydelisTechOS** é um sistema operacional em desenvolvimento, construído de forma independente, com foco em aprendizado profundo, clareza arquitetural e evolução contínua. Não nasceu de um modelo pronto — nasceu da curiosidade e cresceu através de tentativas, erros, recomeços e persistência.

> 
> 💡 **Este projeto é, antes de tudo, uma jornada de conhecimento.** Cada componente, cada camada e cada decisão arquitetural representa horas de estudo, ajustes e compreensão acumulada. O FydelTerm, nosso ambiente de interface e terminais, é o coração de interação com o sistema e o símbolo dessa trajetória.

### Filosofia de Desenvolvimento

- **Transparência:** documentamos não apenas o que funciona, mas também os caminhos que não deram certo;
- **Resiliência:** reconstruir não é sinal de falha — é sinal de que hoje sabemos mais do que sabíamos ontem;
- **Autonomia:** construir uma arquitetura própria, sem dependências obrigatórias de frameworks externos;
- **Progresso contínuo:** o sistema não está completo — está em constante ajuste, evolução e refinamento.

---

## 🗺️ Panorama da Estrutura do Sistema

```
FydelisTechOS-V2/
├── boot/            # Inicialização e bootloader
├── kernel/          # Núcleo do sistema — agendamento, memória, processos
├── drivers/         # Suporte a hardware e interfaces de dispositivo
├── grafico/         # Subsistema gráfico, renderização e gerenciamento de janelas
├── user/            # Aplicativos e espaço do usuário
│   └── fydelterm/   # Terminal principal e ambiente de trabalho
├── virtual/         # Abstrações e camada de virtualização
├── tools/           # Utilitários de desenvolvimento e compilação
└── docs/            # 📌 Esta documentação
```

---

## 🔄 Como a Documentação Está Organizada

Aqui você encontra três tipos de conteúdo:

1. **📖 Histórico e Narrativo:** explica o caminho percorrido, os desafios e as lições aprendidas — ideal para entender a motivação e a evolução do projeto;
2. **🏗️ Técnico e Arquitetural:** detalha camadas, fluxos, protocolos e especificações — referência para desenvolvimento e manutenção;
3. **🖼️ Referência Visual:** capturas e demonstrações do sistema em funcionamento.

> 
> 📌 **Sugestão de leitura:** Se você está chegando agora, comece pela seção **História e Evolução** — ela coloca em perspectiva o contexto de cada decisão técnica que você verá nas seções seguintes. Depois, avance para **Arquitetura do Sistema** para compreender como tudo se conecta.

---

## ⚠️ Estado do Projeto

Tabela

| Aspecto | Status |
| --- | --- |
| Versão atual | **FydelTerm 4.2** / FydelisTechOS V2 em desenvolvimento |
| Construção | 🏗️ Em andamento — ajustes contínuos |
| Trabalho | 🧑 Desenvolvimento individual |
| Documentação | 📝 Em expansão — conteúdo sendo atualizado constantemente |
| Estabilidade | ⚡ Funcional, com melhorias em curso |

> 
> 🚧 **Aviso:** Este é um projeto em desenvolvimento ativo. Partes do sistema estão sendo reestruturadas, ajustadas e melhoradas continuamente. Documentação e código evoluem juntos — pode haver diferenças temporárias entre descrição técnica e implementação. Sempre consulte os arquivos de código-fonte como referência final.

---

## 🤝 Contribuindo

No momento, o FydelisTechOS está em fase inicial de desenvolvimento individual. Ainda assim, sugestões, perguntas e observações são sempre bem-vindas. Sinta-se à vontade para abrir uma **Issue** para compartilhar ideias, dúvidas ou apontamentos sobre a documentação ou o sistema.

---

## ✨ Uma Palavra Final

> 
> *"Construir algo do zero, especialmente sozinho, é uma das formas mais corajosas de aprender. Há dias em que tudo faz sentido, e dias em que parece que nada funciona. Isso não é falha — é parte do processo. O FydelisTechOS não é perfeito, mas é real: erros, ajustes, reconstruções e tudo. E é exatamente essa jornada que faz dele algo único."* — FydelisTechOS Team

Obrigado por visitar e acompanhar nosso desenvolvimento. Seja bem-vindo(a) a esta jornada!
