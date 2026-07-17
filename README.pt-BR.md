# EbonBuilds

[English](README.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | **[Português (Brasil)](README.pt-BR.md)** | [Español](README.es.md) | [Français](README.fr.md) | [Polski](README.pl.md)

Um addon de World of Warcraft (3.3.5a) para o **ProjectEbonhold** que automatiza as escolhas de echo (Banish / Reroll / Freeze / Select) com base em um build que você define, e se auto-ajusta ao longo do tempo com dados reais de jogo.

Requer **ProjectEbonhold** ou **ProjectEbonhold Enhanced**. Alguns recursos usam adicionalmente o **[Details!](https://www.curseforge.com/wow/addons/details)**, se instalado.

## O que ele faz

- **Definir um build**: pesos por echo, bônus de qualidade/família/novidade, slots travados, echoes banidos.
- **Automação**: avalia cada tela de escolha de echo contra o seu build e age (banish/reroll/freeze/select) para você não precisar.
- **Tuning Advisor**: compara seus limiares de Banish/Reroll/Freeze com o que seu build realmente recebe de oferta (não um modelo teórico), sugere valores melhores e pode ajustá-los automaticamente e gradualmente ao longo do tempo.
- **Distribuição de orçamento durante toda a run**: os limiares ficam automaticamente mais rígidos conforme as cargas de Banish/Reroll/Freeze diminuem, para você não gastar suas últimas cargas em ofertas duvidosas.
- **Rastreamento de DPS e taxa de aparição**: com o Details! instalado, rastreia o DPS real por echo ativo; sempre rastreia com que frequência cada echo realmente aparece numa tela de escolha. Ambos podem opcionalmente sincronizar com outros jogadores da mesma classe.
- **Manual Training Mode**: suspenda a automação de um build, escolha manualmente, e o EbonBuilds aprende com suas escolhas, gerando sugestões de peso a partir do que você realmente preferiu.
- **Sugestões de peso e bônus**: dados de DPS e escolhas manuais alimentam sugestões de peso por echo, e (experimentalmente) sugestões de bônus de Qualidade/Família.
- **Export (AI)**: um dump completo em texto simples das configurações do build, todos os echoes disponíveis para sua classe com descrições reais de efeito, e todos os dados de ajuste — feito para ser colado num chat de IA para análise.
- **Tome Atlas**: locais de drop de tomos de echo, coletados pela comunidade.
- **Public Builds**: navegue e importe builds compartilhados por outros jogadores.

Veja [`FAQ.md`](FAQ.md) para explicações detalhadas de cada recurso, e [`CHANGELOG.md`](CHANGELOG.md) para o histórico completo de versões.

## Instalação

A raiz deste repositório *é* a pasta do addon (`EbonBuilds.toc`, `core/`, `modules/` ficam no nível superior, não dentro de uma subpasta).

**Via Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Via download do ZIP:** o "Download ZIP" do GitHub nomeia a pasta extraída de acordo com a branch (ex.: `EbonBuilds-main`) — renomeie-a exatamente para `EbonBuilds` antes de colocá-la em `Interface/AddOns/`, para que o nome da pasta corresponda ao `EbonBuilds.toc`.

Depois reinicie o jogo ou dê `/reload`.

## Comandos

Todo comando começa com `/ebb`. Uma referência completa também está disponível no jogo via `/ebb showcase`.

| Comando | Descrição |
|---|---|
| `/ebb` | Abrir ou fechar a janela principal |
| `/ebb faq` (ou `/ebb help`) | Guia completo no jogo |
| `/ebb showcase` (ou `/ebb commands`) | Esta lista de comandos, no jogo |
| `/ebb tuning` (ou `/ebb advisor`) | Tuning Advisor: limiares, auto-tune, compartilhamento de DPS/taxa de aparição |
| `/ebb cleartraining` | Apagar os dados de Manual Training do build ativo |
| `/ebb atlas` (ou `/ebb tomes`) | Tome Atlas |
| `/ebb affix` | Referência de afixos |
| `/ebb autosell` | Alternar venda automática de itens de 0 cobre nos vendedores |
| `/ebb bagdots` | Alternar pontos coloridos em itens da mochila sem afixo |
| `/ebb debug` | Alternar o log detalhado de decisões da automação |
| `/ebb debuglog` (ou `/ebb log`) | Ver o log de debug capturado |
| `/ebb errors` | Ver erros capturados, para relatos de bugs |
| `/ebb clicktrace` | Registrar todo clique em botão da interface, para relatos de "nada aconteceu" |

## Relatando bugs

Anexe a saída de `/ebb errors` ou um log de `/ebb debug` ao seu relato — é a forma mais rápida de algo ser realmente corrigido em vez de apenas suposto.

## Desenvolvimento

- Lua puro, API do WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` é usado para verificar a sintaxe de cada arquivo antes de cada release; veja `.github/workflows/lua-syntax.yml` para a mesma verificação rodando em CI.
- Sem etapa de build — a raiz do repositório *é* a estrutura de pasta do addon esperada por `Interface/AddOns/`.
