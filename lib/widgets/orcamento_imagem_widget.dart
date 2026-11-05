import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

/// Uma linha do orçamento.
class ItemOrcamentoImagem {
  final String nome;
  final int quantidade;
  final double precoUnitario;

  /// Preço antes da promoção. Só o preço real do produto: desconto inventado
  /// é propaganda enganosa.
  final double? precoCheio;
  final Uint8List? foto;

  const ItemOrcamentoImagem({
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    this.precoCheio,
    this.foto,
  });

  bool get emPromocao => precoCheio != null && precoCheio! > precoUnitario;
  double get total => quantidade * precoUnitario;
  double get totalCheio => quantidade * (emPromocao ? precoCheio! : precoUnitario);
}

/// Orçamento em forma de imagem pra mandar no WhatsApp do cliente, feita pra
/// ler no celular sem dar zoom. As fotos e a logo chegam já baixadas: a imagem
/// é capturada na hora, e foto ainda carregando sairia em branco. Fundo e cores
/// são fixos (não seguem o tema do app) porque a imagem sai do app.
class OrcamentoImagemWidget extends StatelessWidget {
  final String nomeLoja;
  final Color corPrimaria;
  final Uint8List? logo;
  final DateTime data;
  final List<ItemOrcamentoImagem> itens;

  /// Desconto do pedido (cupom ou dado na hora), além das promoções dos itens.
  final double desconto;

  /// Valor cobrado pela entrega. null = ainda não calculada. 0 = frete grátis.
  final double? entrega;

  /// Valor normal da entrega nessa região, mesmo quando saiu grátis.
  final double? entregaCheia;

  /// Quanto o pedido precisa alcançar pra ter frete grátis nessa região.
  final double? minimoFreteGratis;
  final bool retirada;

  const OrcamentoImagemWidget({
    super.key,
    required this.nomeLoja,
    required this.corPrimaria,
    required this.data,
    required this.itens,
    this.logo,
    this.desconto = 0,
    this.entrega,
    this.entregaCheia,
    this.minimoFreteGratis,
    this.retirada = false,
  });

  static const largura = 540.0;
  static const _texto = Color(0xFF1E1E24);
  static const _apagado = Color(0xFF5B5B66);
  static const _linha = Color(0xFFE6E6EA);
  static const _verde = Color(0xFF1F7A45);
  static const _verdeFundo = Color(0xFFE7F5EC);
  static const _trilha = Color(0xFFD5DEE8);

  /// Longe demais do frete grátis, a meta desanima em vez de animar: só aparece
  /// quando falta até metade do mínimo.
  static const fracaoMaximaParaMostrarMeta = 0.5;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  /// "Ração X 15kg – PremieRpet" vira "Ração X 15kg": o fabricante só alonga a
  /// linha, a foto já mostra a marca.
  static String nomeCurto(String nome) => nome.split(RegExp(r'\s+[–—-]\s+')).first.trim();

  double get _subtotal => itens.fold(0, (s, i) => s + i.total);
  double get _subtotalCheio => itens.fold(0, (s, i) => s + i.totalCheio);
  double get _descontoPromocoes => _subtotalCheio - _subtotal;
  double get _total => _subtotal - desconto + (retirada ? 0 : (entrega ?? 0));

  bool get _freteGratisGanho => !retirada && entrega == 0 && (entregaCheia ?? 0) > 0;
  double get _economiaEntrega => _freteGratisGanho ? entregaCheia! : 0;
  double get _economia => _descontoPromocoes + desconto + _economiaEntrega;

  double get _faltaFreteGratis {
    final minimo = minimoFreteGratis;
    if (retirada || minimo == null || minimo <= 0 || (entrega ?? 0) == 0) return 0;
    return _subtotal >= minimo ? 0 : minimo - _subtotal;
  }

  bool get _mostrarMetaFrete =>
      _faltaFreteGratis > 0 && _faltaFreteGratis <= minimoFreteGratis! * fracaoMaximaParaMostrarMeta;

  Color get _sobrePrimaria =>
      ThemeData.estimateBrightnessForColor(corPrimaria) == Brightness.light ? _texto : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: largura,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cabecalho(),
              const SizedBox(height: 8),
              for (final (i, item) in itens.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 24, endIndent: 24, color: _linha),
                _item(item),
              ],
              _resumo(),
              if (_mostrarMetaFrete) _metaFreteGratis(),
              if (_economia >= 0.01) _faixaEconomia(),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    final d = DateFormat('dd/MM/yyyy').format(data);
    return Container(
      color: corPrimaria,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      child: Row(
        children: [
          // A logo costuma ser o próprio nome da loja: uma ou outro, nunca os dois.
          Expanded(
            child: logo != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(height: 56, child: Image.memory(logo!, fit: BoxFit.contain)),
                  )
                : Text(nomeLoja,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _sobrePrimaria)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Orçamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _sobrePrimaria)),
              Text(d, style: TextStyle(fontSize: 14, color: _sobrePrimaria)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selo(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: _verde, borderRadius: BorderRadius.circular(5)),
        child: Text(texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
      );

  Widget _item(ItemOrcamentoImagem item) {
    final promo = item.emPromocao;
    final percentual = promo ? ((1 - item.precoUnitario / item.precoCheio!) * 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _linha),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(3),
            child: item.foto == null
                ? const Icon(Icons.pets, color: _linha, size: 30)
                : Image.memory(item.foto!, fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sem cortar: o peso/tamanho fica no fim do nome e é o que o
                // cliente mais precisa conferir.
                Text(nomeCurto(item.nome),
                    style: const TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w600, color: _texto)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${item.quantidade} × ${_moeda.format(item.precoUnitario)}',
                        style: const TextStyle(fontSize: 15, color: _apagado)),
                    if (percentual > 0) _selo('−$percentual%'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (promo)
                Text(_moeda.format(item.totalCheio),
                    style: const TextStyle(
                        fontSize: 15, color: _apagado, decoration: TextDecoration.lineThrough, decorationColor: _apagado)),
              Text(_moeda.format(item.total),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: promo ? _verde : _texto)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linhaResumo(String rotulo, String valor, {Color cor = _apagado, String? valorCortado}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: Text(rotulo, style: TextStyle(fontSize: 16, color: cor))),
            if (valorCortado != null) ...[
              Text(valorCortado,
                  style: const TextStyle(
                      fontSize: 15, color: _apagado, decoration: TextDecoration.lineThrough, decorationColor: _apagado)),
              const SizedBox(width: 8),
            ],
            Text(valor, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cor)),
          ],
        ),
      );

  Widget _resumo() {
    final valorEntrega = retirada || entrega == 0
        ? 'Grátis'
        : (entrega == null ? 'a calcular' : _moeda.format(entrega));
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _texto, width: 1.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _linhaResumo('Subtotal', _moeda.format(_subtotalCheio)),
          if (_descontoPromocoes >= 0.01)
            _linhaResumo('Promoções', '− ${_moeda.format(_descontoPromocoes)}', cor: _verde),
          if (desconto > 0) _linhaResumo('Desconto', '− ${_moeda.format(desconto)}', cor: _verde),
          _linhaResumo(
            retirada ? 'Retirada na loja' : 'Entrega',
            valorEntrega,
            cor: _freteGratisGanho || retirada ? _verde : _apagado,
            valorCortado: _freteGratisGanho ? _moeda.format(entregaCheia) : null,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(child: Text('Total', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _texto))),
              Text(_moeda.format(_total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: _texto)),
            ],
          ),
        ],
      ),
    );
  }

  /// A entrega que ele deixa de pagar é o que puxa o "só mais um item".
  Widget _metaFreteGratis() {
    final progresso = (_subtotal / minimoFreteGratis!).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
      decoration: BoxDecoration(color: const Color(0xFFF0F6FD), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(TextSpan(
            style: const TextStyle(fontSize: 17, color: _texto),
            children: [
              const TextSpan(text: 'Faltam '),
              TextSpan(text: _moeda.format(_faltaFreteGratis), style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: ' para o '),
              const TextSpan(text: 'frete grátis', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          )),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 9,
              backgroundColor: _trilha,
              valueColor: AlwaysStoppedAnimation(corPrimaria),
            ),
          ),
        ],
      ),
    );
  }

  Widget _faixaEconomia() => Container(
        margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: _verdeFundo, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Expanded(
              child: Text('Você está economizando',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _verde)),
            ),
            Text(_moeda.format(_economia),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _verde)),
          ],
        ),
      );
}
