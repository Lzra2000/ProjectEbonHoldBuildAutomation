# EbonBuilds

[English](README.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [Português (Brasil)](README.pt-BR.md) | **[Español](README.es.md)** | [Français](README.fr.md) | [Polski](README.pl.md)

Un addon de World of Warcraft (3.3.5a) para **ProjectEbonhold** que automatiza las elecciones de eco (Banish / Reroll / Freeze / Select) según un build que defines, y se autoajusta con el tiempo a partir de datos reales de juego.

Requiere **ProjectEbonhold** o **ProjectEbonhold Enhanced**. Algunas funciones usan además **[Details!](https://www.curseforge.com/wow/addons/details)** si está instalado.

## Qué hace

- **Definir un build**: pesos por eco, bonificaciones de calidad/familia/novedad, ranuras bloqueadas, ecos prohibidos.
- **Automatización**: evalúa cada pantalla de elección de eco contra tu build y actúa (banish/reroll/freeze/select) para que no tengas que hacerlo tú.
- **Tuning Advisor**: compara tus umbrales de Banish/Reroll/Freeze con lo que tu build realmente recibe de oferta (no un modelo teórico), sugiere mejores valores y puede ajustarlos automáticamente y de forma gradual con el tiempo.
- **Reparto de presupuesto durante toda la partida**: los umbrales se vuelven automáticamente más estrictos a medida que se agotan las cargas de Banish/Reroll/Freeze, para que no gastes tus últimas cargas en ofertas dudosas.
- **Seguimiento de DPS y tasa de aparición**: con Details! instalado, rastrea el DPS real por eco activo; siempre rastrea con qué frecuencia aparece cada eco en una pantalla de elección. Ambos se pueden sincronizar opcionalmente con otros jugadores de la misma clase.
- **Manual Training Mode**: suspende la automatización de un build, elige manualmente, y EbonBuilds aprende de tus elecciones, generando sugerencias de peso a partir de lo que realmente preferiste.
- **Sugerencias de peso y bonificación**: los datos de DPS y las elecciones manuales alimentan sugerencias de peso por eco, y (de forma experimental) sugerencias de bonificación de Calidad/Familia.
- **Export (AI)**: un volcado completo en texto plano de la configuración del build, todos los ecos disponibles para tu clase con descripciones reales de efecto, y todos los datos de ajuste — pensado para pegarlo en un chat de IA para su análisis.
- **Tome Atlas**: ubicaciones de drop de tomos de eco, recopiladas por la comunidad.
- **Public Builds**: explora e importa builds compartidos por otros jugadores.

Consulta [`FAQ.md`](FAQ.md) para explicaciones detalladas de cada función, y [`CHANGELOG.md`](CHANGELOG.md) para el historial completo de versiones.

## Instalación

La raíz de este repositorio *es* la carpeta del addon (`EbonBuilds.toc`, `core/`, `modules/` están en el nivel superior, no dentro de una subcarpeta).

**Vía Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Vía descarga de ZIP:** el "Download ZIP" de GitHub nombra la carpeta extraída según la rama (p. ej. `EbonBuilds-main`) — renómbrala exactamente a `EbonBuilds` antes de colocarla en `Interface/AddOns/`, para que el nombre de la carpeta coincida con `EbonBuilds.toc`.

Luego reinicia el juego o haz `/reload`.

## Comandos

Todos los comandos empiezan con `/ebb`. También hay una referencia completa en el juego mediante `/ebb showcase`.

| Comando | Descripción |
|---|---|
| `/ebb` | Abrir o cerrar la ventana principal |
| `/ebb faq` (o `/ebb help`) | Guía completa dentro del juego |
| `/ebb showcase` (o `/ebb commands`) | Esta lista de comandos, en el juego |
| `/ebb tuning` (o `/ebb advisor`) | Tuning Advisor: umbrales, auto-tune, compartir DPS/tasa de aparición |
| `/ebb cleartraining` | Borrar los datos de Manual Training del build activo |
| `/ebb atlas` (o `/ebb tomes`) | Tome Atlas |
| `/ebb affix` | Referencia de afijos |
| `/ebb autosell` | Alternar la venta automática de basura de 0 de cobre en vendedores |
| `/ebb bagdots` | Alternar puntos de color en objetos de la mochila sin afijo |
| `/ebb debug` | Alternar el registro detallado de decisiones de la automatización |
| `/ebb debuglog` (o `/ebb log`) | Ver el registro de depuración capturado |
| `/ebb errors` | Ver errores capturados, para reportes de errores |
| `/ebb clicktrace` | Registrar cada clic de botón de la interfaz, para reportes de "no pasó nada" |

## Reportar errores

Adjunta la salida de `/ebb errors` o un registro de `/ebb debug` a tu reporte — es la forma más rápida de que algo se corrija de verdad en lugar de solo suponerlo.

## Desarrollo

- Lua puro, API de WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` se usa para comprobar la sintaxis de cada archivo antes de cada versión; consulta `.github/workflows/lua-syntax.yml` para la misma comprobación ejecutándose en CI.
- Sin paso de compilación — la raíz del repositorio *es* la estructura de carpeta del addon que espera `Interface/AddOns/`.
