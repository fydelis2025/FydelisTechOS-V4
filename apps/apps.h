#ifndef FYDELIS_APPS_H
#define FYDELIS_APPS_H

#include <stdint.h>

// Primitivas gráficas exportadas pelo compositor (kernel/exec.c)
extern void gui_retangulo(int x, int y, int w, int h, uint32_t cor);
extern void gui_borda(int x, int y, int w, int h, uint32_t cor);
extern void gui_texto(int x, int y, const char *str, uint32_t cor);

// Categorias oficiais do Menu Iniciar
typedef enum {
    CAT_ACESSORIOS = 0,
    CAT_SISTEMA    = 1,
    CAT_REDE       = 2,
    CAT_MULTIMIDIA = 3
} AppCategoria;

// Estrutura descritora de um aplicativo nativo
typedef struct {
    const char  *nome;
    AppCategoria categoria;
    int          aberta;
    int          x, y, w, h;
    void (*abrir)(void);
    void (*desenhar)(void);
    void (*on_click)(int rel_x, int rel_y);
    void (*on_key)(char tecla);
} FydelisApp;

// Instâncias dos aplicativos nativos
extern FydelisApp app_calculadora;
extern FydelisApp app_visualizador_logs;
extern FydelisApp app_explorer;
extern FydelisApp app_browser;
extern FydelisApp app_notepad;

// Controles de minimizar/restaurar na barra de tarefas
extern void notepad_alternar_minimizar(void);
extern int  notepad_esta_minimizado(void);

#endif
