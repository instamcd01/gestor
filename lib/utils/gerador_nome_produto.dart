import 'dart:async';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import 'produto_validators.dart';

/// Mantém "Nome do Produto" atualizado ao vivo enquanto o usuário preenche
/// categoria + cadastro estruturado — antes só acontecia ao salvar (o
/// trigger `gerar_nome_produto_estruturado` do banco), o que deixava a
/// impressão de que preencher os campos "não fazia nada" até dar submit.
///
/// Chama a mesma função SQL que o trigger usa (`compor_nome_produto`, via
/// RPC) em vez de duplicar a lógica de montagem do nome em Dart — evita os
/// dois lados divergirem silenciosamente (já achamos 2 bugs de formatação
/// nessa função nesta mesma sessão; duplicar o algoritmo arriscaria um
/// terceiro lugar pra manter sincronizado). Debounced (400ms) pra não
/// disparar uma chamada de rede a cada tecla.
class GeradorNomeProduto {
  final TextEditingController nomeController;
  final TextEditingController categoriaController;
  final TextEditingController nomeComercialController;
  final TextEditingController doseController;
  final TextEditingController composicaoController;
  final TextEditingController apresentacaoController;
  final TextEditingController especieController;
  final TextEditingController faseController;
  final TextEditingController porteController;
  final TextEditingController saborController;
  final TextEditingController pesoController;
  final TextEditingController volumeController;
  final TextEditingController fabricanteController;

  /// Lido a cada disparo (não guardado no construtor) porque o valor mora
  /// num `setState` da tela, não num controller — é o switch "Editar nome
  /// manualmente".
  final bool Function() nomeManualOverride;

  Timer? _debounce;
  bool _disposed = false;

  GeradorNomeProduto({
    required this.nomeController,
    required this.categoriaController,
    required this.nomeComercialController,
    required this.doseController,
    required this.composicaoController,
    required this.apresentacaoController,
    required this.especieController,
    required this.faseController,
    required this.porteController,
    required this.saborController,
    required this.pesoController,
    required this.volumeController,
    required this.fabricanteController,
    required this.nomeManualOverride,
  }) {
    for (final controller in _controladoresObservados) {
      controller.addListener(_aoMudarCampo);
    }
  }

  List<TextEditingController> get _controladoresObservados => [
        categoriaController,
        nomeComercialController,
        doseController,
        composicaoController,
        apresentacaoController,
        especieController,
        faseController,
        porteController,
        saborController,
        pesoController,
        volumeController,
        fabricanteController,
      ];

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    for (final controller in _controladoresObservados) {
      controller.removeListener(_aoMudarCampo);
    }
  }

  void _aoMudarCampo() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _atualizarNome);
  }

  /// Mesma condição de saída do trigger: com "Editar nome manualmente"
  /// ligado, ou sem nome comercial preenchido, não mexe no campo "Nome".
  Future<void> _atualizarNome() async {
    if (nomeManualOverride()) return;
    if (nomeComercialController.text.trim().isEmpty) return;

    try {
      final resultado = await supabase.rpc('compor_nome_produto', params: {
        'p_categoria': categoriaController.text,
        'p_nome_comercial': nomeComercialController.text,
        'p_dose': doseController.text.isEmpty ? null : doseController.text,
        'p_composicao': composicaoController.text.isEmpty ? null : composicaoController.text,
        'p_apresentacao': apresentacaoController.text.isEmpty ? null : apresentacaoController.text,
        'p_especie': especieController.text.isEmpty ? null : especieController.text,
        'p_fase': faseController.text.isEmpty ? null : faseController.text,
        'p_porte': porteController.text.isEmpty ? null : porteController.text,
        'p_sabor': saborController.text.isEmpty ? null : saborController.text,
        'p_peso': ProdutoValidators.parseNumero(pesoController.text),
        'p_volume': ProdutoValidators.parseNumero(volumeController.text),
        'p_fabricante': fabricanteController.text.isEmpty ? null : fabricanteController.text,
      });

      if (_disposed) return;
      final nomeGerado = resultado as String?;
      if (nomeGerado != null && nomeGerado.isNotEmpty) {
        nomeController.text = nomeGerado;
      }
    } catch (e) {
      debugPrint('Erro ao pré-visualizar nome gerado: $e');
    }
  }
}
