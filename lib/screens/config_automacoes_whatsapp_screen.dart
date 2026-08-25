import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

/// Configuração das automações proativas de WhatsApp (carrinho abandonado,
/// reativação, aniversário, promoção segmentada, pesquisa de satisfação,
/// alertas internos de estoque/validade) — mesmo padrão de leitura/escrita
/// direta em colunas de `empresas` já usado em ConfigPetCashScreen. Todas
/// as automações voltadas ao cliente vêm desligadas por padrão; os alertas
/// internos (estoque baixo, validade vencendo) vêm ligados, pois não são
/// mensagem de marketing pro cliente.
class ConfigAutomacoesWhatsappScreen extends StatefulWidget {
  const ConfigAutomacoesWhatsappScreen({super.key});

  @override
  State<ConfigAutomacoesWhatsappScreen> createState() => _ConfigAutomacoesWhatsappScreenState();
}

class _ConfigAutomacoesWhatsappScreenState extends State<ConfigAutomacoesWhatsappScreen> {
  bool _carregando = true;
  bool _salvando = false;

  bool _carrinhoAbandonado = false;
  bool _reativacao = false;
  bool _aniversarioPet = false;
  bool _aniversarioCliente = false;
  bool _promocaoSegmentada = false;
  bool _pesquisaSatisfacao = false;
  bool _alertaEstoque = true;
  bool _alertaValidade = true;
  final _diasAntecedenciaValidadeController = TextEditingController(text: '15');

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _diasAntecedenciaValidadeController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select(
              'whatsapp_carrinho_abandonado_ativo, whatsapp_reativacao_ativo, whatsapp_aniversario_pet_ativo, '
              'whatsapp_aniversario_cliente_ativo, whatsapp_promocao_segmentada_ativo, whatsapp_pesquisa_satisfacao_ativo, '
              'whatsapp_alerta_estoque_ativo, whatsapp_alerta_validade_ativo, dias_antecedencia_alerta_validade')
          .eq('id', empresaId)
          .single();

      if (!mounted) return;
      setState(() {
        _carrinhoAbandonado = data['whatsapp_carrinho_abandonado_ativo'] as bool? ?? false;
        _reativacao = data['whatsapp_reativacao_ativo'] as bool? ?? false;
        _aniversarioPet = data['whatsapp_aniversario_pet_ativo'] as bool? ?? false;
        _aniversarioCliente = data['whatsapp_aniversario_cliente_ativo'] as bool? ?? false;
        _promocaoSegmentada = data['whatsapp_promocao_segmentada_ativo'] as bool? ?? false;
        _pesquisaSatisfacao = data['whatsapp_pesquisa_satisfacao_ativo'] as bool? ?? false;
        _alertaEstoque = data['whatsapp_alerta_estoque_ativo'] as bool? ?? true;
        _alertaValidade = data['whatsapp_alerta_validade_ativo'] as bool? ?? true;
        final diasAntecedencia = data['dias_antecedencia_alerta_validade'] as int?;
        if (diasAntecedencia != null) _diasAntecedenciaValidadeController.text = diasAntecedencia.toString();
      });
    } catch (e) {
      debugPrint('Erro ao carregar configuração de automações WhatsApp: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'whatsapp_carrinho_abandonado_ativo': _carrinhoAbandonado,
        'whatsapp_reativacao_ativo': _reativacao,
        'whatsapp_aniversario_pet_ativo': _aniversarioPet,
        'whatsapp_aniversario_cliente_ativo': _aniversarioCliente,
        'whatsapp_promocao_segmentada_ativo': _promocaoSegmentada,
        'whatsapp_pesquisa_satisfacao_ativo': _pesquisaSatisfacao,
        'whatsapp_alerta_estoque_ativo': _alertaEstoque,
        'whatsapp_alerta_validade_ativo': _alertaValidade,
        'dias_antecedencia_alerta_validade': int.tryParse(_diasAntecedenciaValidadeController.text.trim()) ?? 15,
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração salva.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Automações de WhatsApp')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AvisoBanner(
              texto: 'Mensagens que a loja manda por iniciativa própria pelo WhatsApp, fora de uma conversa em '
                  'andamento. As de cliente vêm desligadas por padrão — ligue quando quiser começar a testar. '
                  'Só chegam pra quem tem "aceitar lembretes por WhatsApp" ativo no cadastro.',
            ),
            const SizedBox(height: 16),
            FormSection(
              titulo: 'Recompra e retenção',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Carrinho abandonado'),
                  subtitle: const Text('Cliente deixou itens no carrinho e sumiu — lembra dele algumas horas depois.'),
                  value: _carrinhoAbandonado,
                  onChanged: (v) => setState(() => _carrinhoAbandonado = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reativação de cliente'),
                  subtitle: const Text('Cliente marcado como inativo (90+ dias sem comprar) recebe um convite pra voltar.'),
                  value: _reativacao,
                  onChanged: (v) => setState(() => _reativacao = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Promoção de produto recorrente'),
                  subtitle: const Text('Avisa quando um produto que o cliente compra com regularidade entra em promoção.'),
                  value: _promocaoSegmentada,
                  onChanged: (v) => setState(() => _promocaoSegmentada = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FormSection(
              titulo: 'Datas especiais',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aniversário do pet'),
                  subtitle: const Text('Parabeniza no dia, se o pet tiver data de nascimento cadastrada.'),
                  value: _aniversarioPet,
                  onChanged: (v) => setState(() => _aniversarioPet = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aniversário do cliente'),
                  subtitle: const Text('Parabeniza no dia, se o cliente tiver data de nascimento cadastrada.'),
                  value: _aniversarioCliente,
                  onChanged: (v) => setState(() => _aniversarioCliente = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FormSection(
              titulo: 'Pós-venda',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pesquisa de satisfação'),
                  subtitle: const Text('Pergunta como foi a entrega, algumas horas depois do pedido ser marcado como entregue.'),
                  value: _pesquisaSatisfacao,
                  onChanged: (v) => setState(() => _pesquisaSatisfacao = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FormSection(
              titulo: 'Alertas internos (pra você, não pro cliente)',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Estoque baixo'),
                  subtitle: const Text('Resumo diário dos produtos no mínimo ou abaixo dele.'),
                  value: _alertaEstoque,
                  onChanged: (v) => setState(() => _alertaEstoque = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Validade vencendo'),
                  subtitle: const Text('Resumo diário dos lotes perto de vencer — precisa registrar validade na entrada de estoque.'),
                  value: _alertaValidade,
                  onChanged: (v) => setState(() => _alertaValidade = v),
                ),
                if (_alertaValidade) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _diasAntecedenciaValidadeController,
                    decoration: const InputDecoration(
                      labelText: 'Avisar com quantos dias de antecedência',
                      suffixText: 'dias',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: _salvando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
