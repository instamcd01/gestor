import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../models/modelo_visual.dart';
import '../providers/branding_provider.dart';
import '../providers/preferencias_provider.dart';
import '../theme/app_theme.dart';

/// Tela de personalização visual da empresa (Configurações > Aparência e Marca).
/// Cada empresa do SaaS edita aqui a própria identidade visual do app.
class AparenciaScreen extends StatelessWidget {
  const AparenciaScreen({super.key});

  /// As mudanças de branding já aplicam localmente na hora (a UI reage ao
  /// `notifyListeners()` do provider antes mesmo da escrita no banco
  /// terminar). Se a escrita falhar, sem isso o erro ficava só no console
  /// e a tela seguia mostrando a mudança como "aplicada" apesar de não ter
  /// sido salva.
  Future<void> _salvarComFeedback(BuildContext context, Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = context.watch<BrandingProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Aparência e Marca')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Escolha um modelo pronto e personalize a cor/tema por cima dele.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),

          Text('Modelo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _GaleriaModelos(
            modelos: branding.modelosDisponiveis,
            modeloSelecionadoId: branding.modelo?.id,
            onSelecionar: (modelo) =>
                _salvarComFeedback(context, () => branding.escolherModelo(modelo.id)),
          ),
          const SizedBox(height: 24),

          Text('Personalizar por cima do modelo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          _SecaoCor(
            titulo: 'Cor principal',
            subtitulo: 'Usada em botões, destaques e ícones ativos',
            cor: branding.corPrimaria,
            onEscolher: () => _abrirSeletorDeCor(
              context,
              corAtual: branding.corPrimaria,
              onSelecionada: (cor) =>
                  _salvarComFeedback(context, () => branding.atualizarCores(corPrimaria: cor)),
            ),
          ),
          const SizedBox(height: 16),

          _SecaoCor(
            titulo: 'Cor secundária',
            subtitulo: 'Usada em elementos de apoio e gráficos',
            cor: branding.corSecundaria,
            onEscolher: () => _abrirSeletorDeCor(
              context,
              corAtual: branding.corSecundaria,
              onSelecionada: (cor) =>
                  _salvarComFeedback(context, () => branding.atualizarCores(corSecundaria: cor)),
            ),
          ),
          const SizedBox(height: 24),

          Text('Tema', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Claro'),
                  value: ThemeMode.light,
                  groupValue: branding.temaModo,
                  onChanged: (v) => _salvarComFeedback(context, () => branding.atualizarTemaPreferido(v!)),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Escuro'),
                  value: ThemeMode.dark,
                  groupValue: branding.temaModo,
                  onChanged: (v) => _salvarComFeedback(context, () => branding.atualizarTemaPreferido(v!)),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Automático (segue o sistema)'),
                  value: ThemeMode.system,
                  groupValue: branding.temaModo,
                  onChanged: (v) => _salvarComFeedback(context, () => branding.atualizarTemaPreferido(v!)),
                ),
              ],
            ),
          ),

          if (branding.layoutNavegacao == LayoutNavegacao.sidebar) ...[
            const SizedBox(height: 24),
            Text('Navegação', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Só vale pra este aparelho — cada pessoa que usa o app escolhe pra si.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Consumer<PreferenciasProvider>(
              builder: (context, preferencias, _) => Card(
                child: SwitchListTile(
                  title: const Text('Barra lateral sempre visível'),
                  subtitle: const Text(
                    'Mantém a barra de ícones fixa nas telas principais, mesmo no celular — '
                    'em vez de precisar abrir o menu toda vez que for navegar.',
                  ),
                  value: preferencias.barraLateralFixa,
                  onChanged: (valor) => preferencias.definirBarraLateralFixa(valor),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _salvarComFeedback(context, branding.restaurarPadrao),
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar cor do modelo'),
          ),
        ],
      ),
    );
  }

  void _abrirSeletorDeCor(
    BuildContext context, {
    required Color corAtual,
    required ValueChanged<Color> onSelecionada,
  }) {
    Color corEscolhida = corAtual;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Escolha a cor'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: corAtual,
            onColorChanged: (cor) => corEscolhida = cor,
            enableAlpha: false,
            labelTypes: const [ColorLabelType.hex],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              onSelecionada(corEscolhida);
              Navigator.pop(context);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }
}

class _GaleriaModelos extends StatelessWidget {
  final List<ModeloVisual> modelos;
  final String? modeloSelecionadoId;
  final ValueChanged<ModeloVisual> onSelecionar;

  const _GaleriaModelos({
    required this.modelos,
    required this.modeloSelecionadoId,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    if (modelos.isEmpty) {
      return const Text('Nenhum modelo disponível no momento.', style: TextStyle(color: Colors.grey));
    }

    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: modelos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final modelo = modelos[index];
          final selecionado = modelo.id == modeloSelecionadoId;
          final corPrimaria = AppTheme.hexParaColor(modelo.corPrimariaPadrao);
          final corSecundaria = AppTheme.hexParaColor(modelo.corSecundariaPadrao);

          return GestureDetector(
            onTap: () => onSelecionar(modelo),
            child: Container(
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selecionado ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                  width: selecionado ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prévia: um cartão em miniatura com o raio de canto do
                  // modelo e as duas cores padrão dele.
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: corPrimaria.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(modelo.radiusCard.clamp(4, 24)),
                      border: Border.all(color: corPrimaria.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _amostraCor(corPrimaria),
                        const SizedBox(width: 6),
                        _amostraCor(corSecundaria),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(modelo.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    modelo.layoutNavegacao == LayoutNavegacao.sidebar ? 'Barra lateral' : 'Menu gaveta',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (selecionado)
                    Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Selecionado',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _amostraCor(Color cor) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
    );
  }
}

class _SecaoCor extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final Color cor;
  final VoidCallback onEscolher;

  const _SecaoCor({
    required this.titulo,
    required this.subtitulo,
    required this.cor,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitulo),
        trailing: GestureDetector(
          onTap: onEscolher,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
        onTap: onEscolher,
      ),
    );
  }
}
