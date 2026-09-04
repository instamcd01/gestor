import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/venda.dart';

/// Recibo em forma de widget — o mesmo conteúdo é usado tanto pra exibir
/// na tela (visualização) quanto capturado como imagem PNG pra compartilhar
/// (ver `ReciboScreen`, que envolve isso num RepaintBoundary).
/// Fundo branco fixo e cores calculadas a partir da marca da loja (não do
/// tema claro/escuro do app) porque essa imagem sai do app — precisa ficar
/// legível e com a cara da loja em qualquer lugar (WhatsApp, etc).
class ReciboVendaWidget extends StatelessWidget {
  final Venda venda;
  final String nomeLoja;
  final String razaoSocial;
  final String cnpj;
  final bool mostrarCnpj;
  final Uint8List? logoBytes;
  final String mensagemRodape;
  final Color corPrimaria;
  final Color corSecundaria;

  const ReciboVendaWidget({
    super.key,
    required this.venda,
    required this.nomeLoja,
    required this.razaoSocial,
    required this.cnpj,
    required this.mostrarCnpj,
    required this.mensagemRodape,
    required this.corPrimaria,
    required this.corSecundaria,
    this.logoBytes,
  });

  static const _corTexto = Colors.black87;
  static const _corTextoClaro = Colors.black54;

  Color get _corSobrePrimaria =>
      ThemeData.estimateBrightnessForColor(corPrimaria) == Brightness.light ? Colors.black87 : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecalho(),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rotuloComprovante(),
                const SizedBox(height: 16),
                _infoVenda(),
                const SizedBox(height: 16),
                _DividerTracejado(cor: corPrimaria.withValues(alpha: 0.35)),
                const SizedBox(height: 14),
                _tabelaItens(),
                const SizedBox(height: 8),
                _DividerTracejado(cor: corPrimaria.withValues(alpha: 0.35)),
                const SizedBox(height: 14),
                _caixaTotais(),
                if (venda.observacao.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Observações: ${venda.observacao}',
                    style: const TextStyle(fontSize: 12, color: _corTexto, fontStyle: FontStyle.italic),
                  ),
                ],
                if (mensagemRodape.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _DividerTracejado(cor: Colors.black12),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      mensagemRodape,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: corSecundaria, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [corPrimaria, Color.alphaBlend(Colors.black.withValues(alpha: 0.18), corPrimaria)],
        ),
      ),
      child: Column(
        children: [
          if (logoBytes != null) ...[
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              padding: const EdgeInsets.all(6),
              child: ClipOval(child: Image.memory(logoBytes!, fit: BoxFit.cover)),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            nomeLoja.isNotEmpty ? nomeLoja : 'Recibo de Venda',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _corSobrePrimaria),
          ),
          if (mostrarCnpj && (razaoSocial.isNotEmpty || cnpj.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Text(
              [razaoSocial, if (cnpj.isNotEmpty) 'CNPJ: $cnpj'].where((s) => s.isNotEmpty).join(' • '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _corSobrePrimaria.withValues(alpha: 0.85)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rotuloComprovante() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: corSecundaria.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'COMPROVANTE DE VENDA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: corSecundaria,
          ),
        ),
      ),
    );
  }

  Widget _infoVenda() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _linhaComIcone(Icons.person_outline, 'Cliente', venda.cliente.nome),
        _linhaComIcone(Icons.calendar_today_outlined, 'Data', DateFormat('dd/MM/yyyy HH:mm').format(venda.dataVenda)),
        _linhaComIcone(Icons.confirmation_number_outlined, 'ID da Venda', venda.idVenda ?? '-'),
        _linhaComIcone(Icons.payment_outlined, 'Pagamento', venda.metodoPagamento),
      ],
    );
  }

  Widget _linhaComIcone(IconData icone, String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 15, color: corSecundaria),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12.5, color: _corTexto),
                children: [
                  TextSpan(text: '$rotulo: ', style: const TextStyle(color: _corTextoClaro)),
                  TextSpan(text: valor, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelaItens() {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 5,
              child: Text('Produto',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: corSecundaria)),
            ),
            Expanded(
              flex: 2,
              child: Text('Qtd',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: corSecundaria),
                  textAlign: TextAlign.center),
            ),
            Expanded(
              flex: 3,
              child: Text('Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: corSecundaria),
                  textAlign: TextAlign.right),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...List.generate(venda.itens.length, (i) {
          final item = venda.itens[i];
          final zebra = i.isOdd;
          return Container(
            color: zebra ? corPrimaria.withValues(alpha: 0.04) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.produto.nome,
                          style: const TextStyle(fontSize: 12.5, color: _corTexto, fontWeight: FontWeight.w600)),
                      Text(
                        '${item.quantidade}x ${currencyFormat.format(item.precoUnitario)}',
                        style: const TextStyle(fontSize: 11, color: _corTextoClaro),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text('${item.quantidade}',
                      style: const TextStyle(fontSize: 12.5, color: _corTexto), textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 3,
                  child: Text(currencyFormat.format(item.precoTotal),
                      style: const TextStyle(fontSize: 12.5, color: _corTexto, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.right),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _caixaTotais() {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final temEntrega = venda.valorEntrega > 0 || venda.entregaSelecionada.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: corPrimaria.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _linhaValor('Subtotal', currencyFormat.format(venda.subtotal)),
          if (venda.desconto > 0) _linhaValor('Desconto', '-${currencyFormat.format(venda.desconto)}'),
          if (venda.saldoUsado > 0) _linhaValor('Saldo utilizado', '-${currencyFormat.format(venda.saldoUsado)}'),
          if (temEntrega) _linhaValor('Entrega', '+${currencyFormat.format(venda.valorEntrega)}'),
          if (venda.jurosParcelamento != null && venda.jurosParcelamento! > 0)
            _linhaValor(
              'Juros do parcelamento (${venda.parcelasCartao}x)',
              '+${currencyFormat.format(venda.jurosParcelamento)}',
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _DividerTracejado(cor: corPrimaria.withValues(alpha: 0.3)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _corTexto)),
              Text(
                currencyFormat.format(venda.valorTotal),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: corPrimaria),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _linhaValor('Valor Pago', currencyFormat.format(venda.valorPago)),
          if (venda.troco > 0) _linhaValor('Troco', currencyFormat.format(venda.troco)),
          if (venda.valorParcelaCartao != null)
            _linhaValor(
              'Parcelamento',
              '${venda.parcelasCartao}x de ${currencyFormat.format(venda.valorParcelaCartao)}',
            ),
        ],
      ),
    );
  }

  Widget _linhaValor(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: const TextStyle(fontSize: 12.5, color: _corTextoClaro)),
          Text(valor, style: const TextStyle(fontSize: 12.5, color: _corTexto, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Linha tracejada — dá o clássico visual de "picote" de recibo/cupom.
class _DividerTracejado extends StatelessWidget {
  final Color cor;

  const _DividerTracejado({required this.cor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 1,
      child: CustomPaint(painter: _TracejadoPainter(cor)),
    );
  }
}

class _TracejadoPainter extends CustomPainter {
  final Color cor;

  _TracejadoPainter(this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cor
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _TracejadoPainter oldDelegate) => oldDelegate.cor != cor;
}
