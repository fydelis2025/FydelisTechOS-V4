#include <stdint.h>

// Função auxiliar para comparar strings (substitui o strcmp padrão)
static int cfg_strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

// Função auxiliar para copiar string limitando o tamanho
static void cfg_strncpy(char *dest, const char *src, int max_len) {
    int i = 0;
    while (src[i] && i < max_len - 1) {
        dest[i] = src[i];
        i++;
    }
    dest[i] = '\0';
}

// Remove espaços em branco à esquerda e à direita de uma string in-place
static char* trim_whitespace(char *str) {
    char *end;
    while (*str == ' ' || *str == '\t' || *str == '\r' || *str == '\n') str++;
    if (*str == '\0') return str;
    
    int len = 0;
    while (str[len] != '\0') len++;
    end = str + len - 1;
    
    while (end > str && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        *end = '\0';
        end--;
    }
    return str;
}

/**
 * Lê uma chave de uma seção específica no buffer do arquivo .cfg carregado na memória
 * @param file_buffer Ponteiro para o conteúdo bruto do fyd_boot.cfg
 * @param target_section Seção desejada (ex: "Principal", "Memoria")
 * @param target_key Chave desejada (ex: "kernel", "tamanho_troca")
 * @param out_val Buffer de saída para o valor encontrado
 * @param max_len Tamanho máximo do buffer de saída
 * @return 1 se encontrado, 0 caso contrário
 */
int parse_boot_config(const char *file_buffer, const char *target_section, const char *target_key, char *out_val, int max_len) {
    if (!file_buffer) return 0;

    char current_section[64] = "";
    const char *p = file_buffer;
    char line[256];
    int line_idx = 0;

    while (1) {
        // Lê linha por linha até o fim do buffer
        if (*p == '\n' || *p == '\r' || *p == '\0') {
            line[line_idx] = '\0';
            char *trimmed = trim_whitespace(line);

            // Ignora linhas vazias ou comentários (#)
            if (trimmed[0] != '\0' && trimmed[0] != '#') {
                // Verifica se é um cabeçalho de seção ex: [Principal]
                if (trimmed[0] == '[' && trimmed[line_idx - 1] == ']') {
                    trimmed[line_idx - 1] = '\0'; // Remove o ']'
                    cfg_strncpy(current_section, trimmed + 1, sizeof(current_section));
                    trim_whitespace(current_section);
                } 
                // Se estamos na seção correta, procura pela chave
                else if (cfg_strcmp(current_section, target_section) == 0) {
                    char *eq = 0;
                    for (int i = 0; trimmed[i] != '\0'; i++) {
                        if (trimmed[i] == '=') {
                            eq = &trimmed[i];
                            break;
                        }
                    }

                    if (eq != 0) {
                        *eq = '\0'; // Divide a chave e o valor
                        char *k = trim_whitespace(trimmed);
                        char *v = trim_whitespace(eq + 1);

                        if (cfg_strcmp(k, target_key) == 0) {
                            cfg_strncpy(out_val, v, max_len);
                            return 1; // Chave encontrada com sucesso!
                        }
                    }
                }
            }

            line_idx = 0;
        } else {
            if (line_idx < (int)sizeof(line) - 1) {
                line[line_idx++] = *p;
            }
        }

        if (*p == '\0') break;
        p++;
    }

    return 0; // Não encontrado
}
