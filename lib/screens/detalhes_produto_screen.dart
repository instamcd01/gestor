import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../utils/produto_validators.dart';
import '../widgets/form_section.dart';

/// Tela somente-leitura de produto, usada pelo papel "vendedor" — precisa
/// ver preço/estoque/descrição pra atender o cliente, mas não deve alterar
/// o catálogo nem ver custo/margem/fornecedor. Deliberadamente uma tela
/// separada de EditarProdutoScreen (não um modo "campos desabilitados" da
/// mesma tela) — assim uma mudança futura no formulário de edição nunca
/// corre o risco de acidentalmente reabrir edição pro vendedor.
class DetalhesProdutoScreen extends StatelessWidget {
  final Produto produto;

  const DetalhesProdutoScreen({super.key, required this.produto});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semEstoque = produto.estoqueAtual <= 0;
    final estoqueBaixo = !semEstoque &&
        produto.estoqueMinimo > 0 &&
        produto.estoqueAtual <= produto.estoqueMinimo;
    final temPromocao = produto.precoPromocional != null && produto.precoPromocional! < produto.preco;

    return Scaffold(
      appBar: AppBar(title: const Text('Produto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 140,
                height: 140,
                color: colorScheme.surfaceContainerHighest,
                child: produto.imagemUrl.isNotEmpty
                    ? Image.network(
                        produto.imagemUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            produto.nome,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (produto.categoria.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              (produto.subcategoria?.isNotEmpty ?? false)
                  ? '${produto.categoria} • ${produto.subcategoria}'
                  : produto.categoria,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),

          FormSection(
            titulo: 'Venda',
            children: [
              _linha(context, 'Preço', 'R\$ ${produto.preco.toStringAsFixed(2)}'),
              if (temPromocao)
                _linha(
                  context,
                  'Preço promocional',
                  'R\$ ${produto.precoPromocional!.toStringAsFixed(2)}',
                  cor: Colors.green,
                ),
              _linha(
                context,
                'Estoque',
                semEstoque ? 'Sem estoque' : '${produto.estoqueAtual} unidade(s)',
                cor: semEstoque ? colorScheme.error : (estoqueBaixo ? Colors.orange : null),
              ),
            ],
          ),
          const SizedBox(height: 16),

          FormSection(
            titulo: 'Identificação',
            children: [
              if (produto.codigoBarras.isNotEmpty) _linha(context, 'Código de barras', produto.codigoBarras),
              if (produto.sku?.isNotEmpty ?? false) _linha(context, 'SKU', produto.sku!),
              if (produto.validade?.isNotEmpty ?? false)
                _linha(context, 'Validade', ProdutoValidators.formatarValidade(produto.validade)),
              if (produto.codigoBarras.isEmpty && !(produto.sku?.isNotEmpty ?? false) && !(produto.validade?.isNotEmpty ?? false))
                Text('Nenhuma informação adicional.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ],
          ),

          if (produto.descricao.isNotEmpty) ...[
            const SizedBox(height: 16),
            FormSection(
              titulo: 'Descrição',
              children: [Text(produto.descricao)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _linha(BuildContext context, String label, String valor, {Color? cor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(
          flex: 3,
          child: Text(valor, style: TextStyle(color: cor, fontWeight: cor != null ? FontWeight.w700 : null)),
        ),
      ],
    );
  }
}
