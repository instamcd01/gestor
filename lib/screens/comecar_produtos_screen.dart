import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/plataforma_config.dart';
import '../widgets/importar_produtos_planilha.dart';
import 'cadastro_produto_screen.dart';

/// Primeiro contato da loja nova com o cadastro de produtos (aberto pelo guia
/// "Primeiros passos"). O cadastro manual tem muitos campos e assusta quem
/// está começando, então ele fica por último: primeiro planilha, ou a INARI
/// cadastra junto.
class ComecarProdutosScreen extends StatelessWidget {
  const ComecarProdutosScreen({super.key});

  Future<void> _chamarSuporte(BuildContext context) async {
    const texto = 'Oi! Acabei de criar minha loja na INARI e quero ajuda pra cadastrar meus produtos.';
    final uri = Uri.parse('https://wa.me/$kWhatsappSuportePlataforma?text=${Uri.encodeComponent(texto)}');
    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não deu pra abrir o WhatsApp. Chame no (21) 99887-7477.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    void abrir(Widget tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

    final opcoes = [
      (
        Icons.upload_file_outlined,
        'Já tenho uma planilha',
        'Do Excel ou exportada do sistema que você usa hoje. A INARI reconhece as colunas sozinha.',
        () => abrir(const ImportarProdutosScreen(primeiraVez: true)),
      ),
      (
        Icons.support_agent_outlined,
        'Quero que a INARI cadastre pra mim',
        'Manda a lista do jeito que tiver (foto, PDF, planilha) e a gente cadastra junto com você.',
        () => _chamarSuporte(context),
      ),
      (
        Icons.edit_note_outlined,
        'Cadastrar um por um',
        'Bom pra poucos produtos: nome, categoria, preço e custo, o resto é opcional.',
        () => abrir(const CadastroProdutoScreen()),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Cadastrar produtos')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Como você quer começar?', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Escolha o jeito mais fácil pra você. Dá pra misturar depois.',
                  style: TextStyle(color: cores.onSurfaceVariant)),
              const SizedBox(height: 16),
              for (final (icone, titulo, detalhe, acao) in opcoes)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(icone, color: cores.primary, size: 32),
                    title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(detalhe)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: acao,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
