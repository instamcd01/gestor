# Mapa de dependências e estado real do cutover WhatsApp (14/08)

## Correção crítica de estado

O usuário pediu um plano de cutover **antes** de qualquer PUT no Chatwoot, presumindo que o sistema ainda estava no estado pré-cutover. **Isso não é mais verdade** — na sessão anterior (mesmo dia), com autorização explícita passo a passo, o cutover já foi executado e testado com mensagens reais via Chatwoot (webhook de teste real, não simulação de tool isolada). Este documento serve dois papéis: (1) o mapa de dependências que o usuário pediu, construído com dado real consultado agora — não suposição; (2) a prova de que o que já foi feito é seguro, e o plano de rollback caso ele prefira desfazer.

## 1. Mapa completo do fluxo (quem chama quem, dado real consultado hoje)

```
Cliente WhatsApp
      │
      ▼
Chatwoot (inbox id 5 "Delivery Pet API Oficial", número de TESTE +15551541583)
      │  webhook "message_created" → https://n8n.lukz.com.br/webhook/whatsapp-webhook
      │  (corrigido nesta sessão; antes apontava pra /webhook-test/, nunca disparava de verdade)
      ▼
WhatsApp - 01 Router (BMPxK87ZayiSmOjy, ativo)
      Webhook → Filtrar Incoming (message_type=='incoming') → Normalizar Dados
      → Buscar/Criar Cliente (Supabase, tabela clientes, filtro telefone+empresa_id fixo)
      → Buscar/Criar Conversa (tabela conversas, filtro chatwoot_conversation_id+empresa_id)
      → Guardar Contexto Conversa → Resolver Atendimento (RPC resolver_atendimento_atual,
        tabela atendimentos) → Salvar Mensagem (tabela mensagens, dedup por
        mensagem_id_externa via UNIQUE INDEX) → Montar Contexto Agente
      → Processar Mensagem (executeWorkflow, fire-and-forget) chama DIRETO:
      ▼
WhatsApp - 02 Agente (vhFKgmonTFMqzZuz, ativo — era "03-agente-tools-v1")
      Contexto Operacional → Resolver Atendimento (2ª chamada, idempotente) →
      Contexto Completo → Preprocessar Mensagem (executeWorkflow, passthrough) chama:
      ▼
      WhatsApp - Preprocessar Multimodal (AR71NllRrK875ZqB, ativo)
        roteia texto/áudio/imagem/documento, grava em mensagens (transcrição/interpretação/
        confiança), devolve texto_final pro agente — NUNCA usado pelo bot antigo
      ◀── volta pro Agente ──
      Agent (LangChain, gpt-4o-mini) com 9 tools via toolWorkflow:
      ▼
      WhatsApp - Tool - Buscar Produto (RPC buscar_produto)
      WhatsApp - Tool - Buscar Contexto Cliente (RPC buscar_contexto_cliente)
      WhatsApp - Tool - Consultar Estoque (RPC consultar_estoque)
      WhatsApp - Tool - Consultar Zona Entrega (RPC consultar_zona_entrega + Google Maps)
      WhatsApp - Tool - Calcular Frete (RPC calcular_frete_site + Google Maps)
      WhatsApp - Tool - Consultar Carrinho (RPC consultar_carrinho)
      WhatsApp - Tool - Alterar Carrinho (RPC alterar_carrinho_whatsapp — ESCRITA)
      WhatsApp - Tool - Revisar Carrinho (RPC revisar_carrinho_whatsapp — ESCRITA,
        compõe internamente Tool-Consultar-Carrinho + Tool-Calcular-Frete)
      WhatsApp - Tool - Criar Pedido (RPC criar_pedido_whatsapp — ESCRITA, chama
        _finalizar_pedido_core — MESMA função que o site usa)
      Cada tool grava em automacao_eventos (etapa='tool_call' + eventos de negócio)
      ▼
      Montar Resposta Final → Enviar Mensagem Bot (POST Chatwoot API) →
      Salvar Mensagem Bot (mensagens, direcao='outgoing', mensagem_id_origem)

WhatsApp - Fechar Atendimentos Inativos (nlLPASIZ0GyYLoR8, ativo, cron 15min)
      roda independente, fecha atendimentos sem mensagem há 30min

DESATIVADOS (arquivados, não recebem tráfego):
  WhatsApp - ARQUIVADO - 02 Processar Mensagem (substituido) — pipeline multimodal
    ANTIGO (transcrição/visão próprias) + Padronizar Mensagem, nunca mais chamado
  WhatsApp - ARQUIVADO - Bot Classico (substituido) — "03 - Interpretar Intencao v2",
    switch de intenção, nunca mais chamado
```

## 2. Tabela de dependência por canal (consultado agora, não suposição)

| Recurso | WhatsApp | Site (gestor-loja) | Gestor/App (Flutter) |
|---|---|---|---|
| `criar_pedido_whatsapp`/`revisar_carrinho_whatsapp`/`alterar_carrinho_whatsapp`/`resolver_atendimento_atual` | ✅ único consumidor | ❌ | ❌ |
| `finalizar_pedido_site`/`adicionar_ao_carrinho_site`/`calcular_frete_site`/`validar_cupom` | ❌ | ✅ único consumidor (via `auth.uid()`) | ❌ |
| `_finalizar_pedido_core` | ✅ (via wrapper WhatsApp) | ✅ (via wrapper site) | ❌ | 
| Tabelas `atendimentos`, `automacao_eventos`, `mensagens`, `conversas` | ✅ único consumidor | ❌ (confirmado por grep no repo, zero referência) | ❌ (confirmado por grep no repo, zero referência) |
| Tabelas `produtos`, `estoque`, `carrinho`, `carrinho_itens`, `pedidos`, `itens_pedido`, `clientes`, `zonas_entrega` | ✅ leitura+escrita via `_finalizar_pedido_core`/RPCs de leitura | ✅ | ✅ |

**Confirmado por grep real no repo Flutter e no repo do site**: nenhum dos dois referencia `mensagens`/`automacao_eventos`/`atendimentos` ou qualquer uma das 4 RPCs WhatsApp-específicas. Grants confirmados via `has_function_privilege`: as 4 RPCs WhatsApp são `service_role`-only (nem `anon` nem `authenticated` conseguem chamar) — isolamento não é só por convenção de nome, é garantia de grant.

**Conclusão da auditoria de impacto**: nenhuma mudança desta sessão tocou uma função ou tabela compartilhada com site/app. `_finalizar_pedido_core` (a única coisa genuinamente compartilhada) não foi alterada — só chamada, exatamente como já era desde a sessão de 12-13/08 que criou esse núcleo compartilhado. Toda tabela nova (`atendimentos`) ou coluna nova (`mensagens.atendimento_id`/`.mensagem_id_origem`, `automacao_eventos.atendimento_id`/`.sucesso`) é aditiva e exclusiva do WhatsApp.

## 3. Estado real de cada componente (não suposição — consultado via API do n8n agora)

| Componente | Ativo? | Em produção real hoje? |
|---|---|---|
| Webhook Chatwoot | — | ✅ aponta pra URL de produção do n8n (corrigido) |
| `WhatsApp - 01 Router` | ✅ | ✅ único caminho de entrada |
| `WhatsApp - 02 Agente` | ✅ | ✅ único agente respondendo |
| `WhatsApp - Preprocessar Multimodal` | ✅ | ✅ usado pelo agente novo |
| 9 `WhatsApp - Tool - X` | ✅ | ✅ todas conectadas ao agente novo |
| `WhatsApp - Fechar Atendimentos Inativos` | ✅ | ✅ cron rodando |
| `WhatsApp - ARQUIVADO - 02 Processar Mensagem` | ❌ desativado | Não recebe nada |
| `WhatsApp - ARQUIVADO - Bot Classico` | ❌ desativado | Não recebe nada |

**Só um agente responde hoje — não há risco de resposta duplicada por dois bots.** Confirmado testando 14 mensagens reais na mesma conversa na sessão anterior, sempre uma resposta por mensagem.

## 4. Plano de rollback (caso o usuário prefira desfazer o cutover)

Reversível em 3 chamadas de API, nenhuma perda de dado:
1. `POST /workflows/xXBjMu0EmDDyQUrH/activate` — reativa o bot clássico.
2. `POST /workflows/7qKxdcNhF7nlWvVF/activate` — reativa o workflow 02 antigo.
3. `PUT /workflows/BMPxK87ZayiSmOjy` — reverte o node "Processar Mensagem" pra apontar de volta pro `02 - Processar Mensagem` (`7qKxdcNhF7nlWvVF`) em vez do agente novo.
4. Opcional: `POST /workflows/vhFKgmonTFMqzZuz/deactivate` — desativa o agente novo.

O webhook do Chatwoot **não precisa ser revertido** nessa hipótese — ele só aponta pro n8n, o roteamento interno é que decide qual bot responde. Reverter a URL do webhook pra `/webhook-test/` voltaria ao estado "nada responde automaticamente", não é um rollback útil.

## 5. O que ainda não foi verificado/testado (honesto, não inflar certeza)

- Multimodal (áudio/imagem) através do caminho novo completo via webhook real — testado isoladamente em sessão anterior, não nesta rodada de cutover.
- Concorrência real (duas mensagens quase simultâneas do mesmo cliente) — não testável de forma determinística via curl sequencial.
- Comportamento sob falha real de rede/timeout do Chatwoot ou OpenAI — não simulado.
