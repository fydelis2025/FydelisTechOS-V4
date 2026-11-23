
// ==========================================
// FYDELIS TECH OS — Syscalls: Ferramentas de Disco
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef DISKTOOLS_SYSCALLS_H
#define DISKTOOLS_SYSCALLS_H

#include <stdint.h>

// === RECUPERAÇÃO ===
int  escanear_particoes_perdidas(const char* disco);
int  recuperar_particao(const char* disco, int numero, const char* caminho_saida);
int  recuperar_arquivos(const char* particao, const char* filtro, const char* destino);

// === CLONAGEM ===
int  clonar_disco(const char* origem, const char* destino);
int  criar_imagem(const char* disco, const char* arquivo_img);
int  restaurar_imagem(const char* arquivo_img, const char* disco);

// === VERIFICAÇÃO ===
int  verificar_setores_defeituosos(const char* disco);
int  reparar_tabela_particoes(const char* disco);
int  verificar_sistema_arquivos(const char* unidade);

// === INFORMAÇÃO ===
uint64_t calcular_espaco_livre(const char* caminho);
int  obter_identificador_disco(const char* disco, char* buffer, int tam);

#endif // DISKTOOLS_SYSCALLS_H
