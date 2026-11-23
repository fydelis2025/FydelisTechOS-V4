# 🤝 Como Contribuir com o FydelisTechOS

Primeiramente, muito obrigado pelo seu interesse em contribuir com o **FydelisTechOS**! 💜

> Este projeto está em desenvolvimento ativo e, no momento, é mantido de forma independente. Isso não significa que sua ajuda não seja bem-vinda — pelo contrário: toda revisão técnica, sugestão ou dúvida agrega muito ao projeto.

---

## 🗺️ Sobre o Projeto

O **FydelisTechOS** é um sistema operacional bare-metal `x86_64` desenvolvido em Assembly (NASM) e C, com foco em inicialização UEFI/Legacy, drivers próprios, subsistema gráfico nativo e ferramentas de sistema.

Você pode conhecer a arquitetura e a evolução do projeto na pasta [`docs/`](./docs/) e no [`CHANGELOG.md`](./CHANGELOG.md).

---

## 💡 Formas de Contribuir

Mesmo sem escrever Assembly ou C, há várias formas de ajudar:

- 🐛 **Reportar bugs:** encontrou algo que não funciona como esperado? Abra uma Issue descrevendo o cenário e o comportamento observado.
- 💡 **Sugestões de melhoria:** tem uma ideia de funcionalidade, otimização ou simplificação arquitetural? Compartilhe.
- 📝 **Documentação:** ajustes de clareza, correções e exemplos na pasta `docs/` são muito bem-vindos.
- 💬 **Dúvidas e revisões:** perguntas técnicas ajudam a identificar pontos onde o código ou a documentação podem ficar mais claros.

---

## 📋 Diretrizes

### Antes de contribuir
- ✅ Verifique se já não existe uma Issue ou discussão aberta sobre o mesmo tema.
- ✅ Mantenha a comunicação objetiva, respeitosa e construtiva.
- ✅ Para mudanças estruturais maiores (boot, layout de disco, drivers centrais ou arquitetura do núcleo), abra uma Issue antes de investir muito tempo para alinharmos a abordagem.

### Ao relatar um problema
Inclua sempre que possível:
- O que você estava tentando fazer;
- O que aconteceu e o que era esperado;
- Passos para reproduzir;
- **Ambiente de execução:** emulador/VM utilizado (ex.: QEMU, VirtualBox, hardware real) e modo de boot (**UEFI** ou **Legacy BIOS**).

### Ao enviar código (Pull Requests)
- Mantenha as alterações focadas e explique claramente o que o PR resolve ou melhora;
- Não inclua artefatos gerados de compilação no commit (`.o`, `.d`, `.bin`, `.img`, `.iso`, `.efi` ou chaves locais);
- Teste a compilação limpa (`make clean && make`) antes de enviar.

---

## 🌱 Filosofia do Projeto

- **Aprendizado > Perfeição:** evolução contínua acima de soluções engessadas.
- **Transparência:** registramos tanto os marcos funcionais quanto as reconstruções e desafios do caminho.
- **Persistência:** refatorar não é recuar — é amadurecer a arquitetura.
- **Respeito:** toda contribuição, por menor que pareça, faz diferença.

---

> 💜 Obrigado por acompanhar e contribuir com esta jornada!
> — **FydelisTechOS**
