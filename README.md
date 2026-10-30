# Matugen Theme 1.1 — desarrollo local

Tema dinámico para Emacs 28.1 o superior, a partir de una paleta de Matugen o
DankMaterialShell en formato Ghostty. Esta es la versión local mejorada de
[diegoveraniego/matugen-theme-emacs](https://github.com/diegoveraniego/matugen-theme-emacs).
`BASELINE.txt` identifica la copia original y su respaldo. Esta carpeta no es
un checkout de GitHub y los cambios todavía no están publicados allí.

La paleta se procesa en etapas: **leer → validar → construir roles → aplicar
perfil → comprobar contraste → generar faces**. Una escritura incompleta conserva
el último tema válido. Las notificaciones se agrupan y las entradas idénticas
no vuelven a aplicar faces, fuentes ni modos globales.

## Perfiles

Ejecuta `M-x matugen-theme-select-style` para previsualizar. `C-g` restaura el
perfil y los temas anteriores. La selección dura esta sesión; para conservarla
cambia `matugen-theme-style` en tu configuración o usa Customize.

| Perfil | Política de paleta | Énfasis | Uso |
|---|---|---|---|
| `writing` | Neutros teñidos suavemente por el acento | Mínimo | Escribir en Org o Markdown |
| `monochrome` | Grises neutros | Mínimo | Escribir sin color decorativo |
| `coding` | Colores del sistema | Equilibrado | Programación y navegación |
| `presentation` | Colores del sistema | Intenso | Jerarquía más visible, cabeceras moderadas |
| `full` | Igual que `coding` | Equilibrado | Compatibilidad |
| `accent` | Contenido neutro y acento de interfaz del sistema | Equilibrado | Interfaz discreta con foco coloreado |
| `background` | Fondo del sistema, un color de contenido | Mínimo | Mantener el wallpaper con poco énfasis |
| `harmonized` | Cromática reducida | Equilibrado | Código con tinte suave |
| `neon` | Colores del sistema con mayor saturación | Intenso | Mayor énfasis en sintaxis |

Los nombres antiguos siguen disponibles, pero `monochrome`, `accent` y
`background` tienen ahora los comportamientos descritos en esta tabla. Los
perfiles mínimos usan un único color para la sintaxis y las cabeceras; los
metadatos tienen un tono secundario legible. Enlaces y estados se distinguen
también mediante peso o subrayado.

Opciones independientes:

```elisp
(setq matugen-theme-style 'writing
      matugen-theme-palette 'preset       ; preset, system, tinted, neutral
      matugen-theme-emphasis 'preset      ; preset, minimal, balanced, vivid
      matugen-theme-semantic-colors 'auto ; auto, t, nil
      matugen-theme-heading-scale 1.0)
```

`preset` toma la decisión del perfil seleccionado. Cualquier otra opción la
sobrescribe: por ejemplo `neutral + minimal` produce contenido neutro aunque
el perfil elegido sea `coding`. `semantic-colors = auto` conserva colores de
error/aviso/éxito en perfiles equilibrados o intensos; en los mínimos usa énfasis
sin color. `t` conserva esos colores también al escribir. La escala de cabeceras
es independiente del tamaño y la familia de la fuente.

## Instalación y configuración

Los archivos necesarios son `matugen-theme.el` y `matugen-theme-faces.el`, juntos
en un directorio. Ejemplo para Emacs:

```elisp
(add-to-list 'load-path "/ruta/a/matugen-theme-emacs")
(require 'matugen-theme)
(setq matugen-theme-colors-file
      (expand-file-name "~/.config/ghostty/themes/dankcolors")
      matugen-theme-style 'writing)
(matugen-theme-mode 1)
```

En este equipo, `~/.config/doom/lisp/` contiene enlaces a estos archivos y Doom
los carga desde `config.el`. No hace falta `doom sync`. Reinicia Emacs después
de migrar desde la versión 1.0 para liberar sus observadores y hooks antiguos.

Desactiva otros conmutadores automáticos de tema, como `auto-dark`, si pretendes
que Matugen gestione los cambios. Desactivar `matugen-theme-mode` detiene la
sincronización y conserva los colores actuales. `M-x matugen-theme-reload`
recarga la paleta; `C-u M-x matugen-theme-reload` fuerza la aplicación aunque
los datos no hayan cambiado.

## Contrato de entrada y colores

Los colores reconocidos son hexadecimales `#RRGGBB`. Se permiten espacios,
tabuladores y comentarios de final de línea separados por espacios. Los índices
de paleta van de 0 a 15; si se repiten, se usa el último valor.

```conf
background = #19120c
foreground = #efe0d5
cursor-color = #feb877
selection-background = #60432a
selection-foreground = #ffe8d0
palette = 1=#ff7269
palette = 2=#8dfe77
palette = 3=#ffe569
palette = 4=#f1a157
palette = 5=#a05b00
palette = 6=#feb877
```

`background` y `foreground` son obligatorios. El resto es opcional. Se ignoran
otros ajustes de terminal. `accent` tiene prioridad sobre `cursor-color`; sin
ambos, se usa `palette-4` y finalmente `foreground`. También se aceptan
`error`, `warning` y `success` explícitos; si faltan se usan colores semánticos
propios, corregidos para el fondo.

La correspondencia ANSI se limita a la importación: índices 1–6 alimentan los
roles de variable, string, tipo, función, palabra clave y constante. En el resto
del código se usan funciones del color, no nombres como “rojo” o “azul”.

El corrector busca tanto hacia negro como hacia blanco, con búsqueda acotada,
y verifica el resultado hexadecimal redondeado. Los roles de contenido se
validan con al menos 4,5:1 sobre fondo principal, superficie elevada y línea de
modo; el cursor alcanza 3:1. Selección y búsquedas tienen su propia pareja de
colores: **la selección reemplaza el foreground de sintaxis mientras está activa**.

La política neutra conserva aproximadamente la luminancia de entrada al
convertirla a gris. Los tintes son mezclas sRGB explícitas. La implementación
no promete interpolación perceptualmente uniforme; un motor OKLCH se puede
evaluar después, sin mezclarlo con importación, perfiles ni notificaciones.

## Observadores e integración

Se observan los directorios de la ruta principal y del fallback, incluyendo los
dos nombres de un renombrado. Un chequeo de atributos cada cinco segundos
recupera observadores detenidos y detecta directorios que aparecieron después
del arranque. Solo se lee y recalcula cuando cambian atributos u opciones.
Una lectura fallida tiene hasta dos reintentos después de la notificación.

Opciones: `matugen-theme-update-delay` (0,15 segundos),
`matugen-theme-poll-interval` (5 segundos) y
`matugen-theme-fallback-colors-file` (Ghostty por defecto, `nil` para desactivarlo).
Un archivo principal existente pero inválido conserva la última paleta; no se
sustituye silenciosamente por un fallback posiblemente desactualizado.

Las recargas actualizan faces y frames sin volver a cargar fuentes ni alternar
Solaire. Los frames nuevos adoptan el modo claro/oscuro mientras la sincronización
está activa. Las personalizaciones del usuario siguen teniendo precedencia.

Para adaptar configuraciones externas después de cada cambio:

```elisp
(defun my-theme-integration ()
  (when (boundp 'org-tag-faces)
    (setq org-tag-faces
          (unless (matugen-theme-minimal-p)
            `(("trabajo" . (:foreground ,(matugen-theme-color 'function))))))))
(add-hook 'matugen-theme-after-apply-hook #'my-theme-integration)
```

El hook solo se ejecuta cuando se aplican cambios. `matugen-theme-color` devuelve
el color del rol aplicado, o `nil` antes de la primera carga.

## Desarrollo y comprobaciones

`matugen-theme.el` contiene entrada, color, roles y ciclo de vida.
`matugen-theme-faces.el` solo convierte roles a especificaciones de faces.
`test/matugen-theme-test.el` contiene regresiones de comportamiento, incluyendo
fuentes inválidas, contraste, cancelación, observadores y timers.

```sh
make test
make compile
make validate
```

`make validate` exporta 36 combinaciones de paleta y perfil, recalcula los
contrastes con Python y genera `palette-comparison.html`. La comparación usa
una captura real y casos sintéticos claros, medios y de acento oscuro. Los datos
de la versión anterior se guardan en `test/baseline.json`.

La validación disponible se realiza con Emacs 31.1. Emacs 28.1 y otros sistemas
necesitan su propia ejecución de pruebas. El HTML aproxima algunas faces;
la tipografía, el orden de herencia y otros paquetes requieren revisión gráfica.
