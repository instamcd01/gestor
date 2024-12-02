import 'package:flutter/material.dart';

class GerenciarEntregaScreen extends StatefulWidget {
  final Function(Map<String, Map<String, double>>) onSalvarOpcoesEntrega;
  final Map<String, Map<String, double>> opcoesEntrega;

  GerenciarEntregaScreen({
    required this.onSalvarOpcoesEntrega,
    required this.opcoesEntrega,
  });

  @override
  _GerenciarEntregaScreenState createState() => _GerenciarEntregaScreenState();
}

class _GerenciarEntregaScreenState extends State<GerenciarEntregaScreen> {
  late Map<String, Map<String, double>> opcoesEntrega;

  final _distanciaController = TextEditingController();
  final _valorController = TextEditingController();

  String? _selectedCategoria;

  @override
  void initState() {
    super.initState();
    opcoesEntrega = Map.from(widget.opcoesEntrega);
  }

  void _adicionarOuEditarOpcaoEntrega({
    String? categoria,
    String? distancia,
    double? valor,
  }) {
    setState(() {
      _selectedCategoria = categoria ?? null;
    });

    _distanciaController.text = distancia ?? '';
    _valorController.text = valor?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(categoria != null ? 'Editar Opção de Entrega' : 'Adicionar Nova Opção de Entrega'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCategoria,
                hint: Text('Selecione uma Categoria'),
                items: opcoesEntrega.keys.map((categoria) {
                  return DropdownMenuItem<String>(
                    value: categoria,
                    child: Text(categoria),
                  );
                }).toList(),
                onChanged: (newCategoria) {
                  setState(() {
                    _selectedCategoria = newCategoria;
                  });
                },
                decoration: InputDecoration(labelText: 'Categoria (Frete Grátis/Entrega Paga)'),
              ),
              TextField(
                controller: _distanciaController,
                decoration: InputDecoration(labelText: 'Distância (km)'),
                keyboardType: TextInputType.text,
              ),
              TextField(
                controller: _valorController,
                decoration: InputDecoration(labelText: 'Valor (R\$)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                String novaDistancia = _distanciaController.text.trim();
                double novoValor = double.tryParse(_valorController.text) ?? 0.0;

                if (_selectedCategoria != null && novaDistancia.isNotEmpty) {
                  setState(() {
                    opcoesEntrega[_selectedCategoria!] ??= {};
                    opcoesEntrega[_selectedCategoria!]![novaDistancia] = novoValor;
                    _ordenarOpcoesPorDistancia(_selectedCategoria!);
                  });
                }

                Navigator.of(ctx).pop();
              },
              child: Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  void _ordenarOpcoesPorDistancia(String categoria) {
    if (opcoesEntrega[categoria] != null) {
      final Map<String, double> ordenado = Map.fromEntries(
        opcoesEntrega[categoria]!.entries.toList()
          ..sort((a, b) {
            int valorA = int.tryParse(a.key.split('-').first) ?? 0;
            int valorB = int.tryParse(b.key.split('-').first) ?? 0;
            return valorA.compareTo(valorB);
          }),
      );
      opcoesEntrega[categoria] = ordenado;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gerenciar Opções de Entrega'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: opcoesEntrega.keys.map((categoria) {
                  return _buildCategoria(categoria);
                }).toList(),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _adicionarOuEditarOpcaoEntrega();
              },
              child: Text('Adicionar Nova Opção de Entrega'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                widget.onSalvarOpcoesEntrega(opcoesEntrega);
                Navigator.pop(context);
              },
              child: Text('Salvar Alterações'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoria(String categoria) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(
          categoria,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        children: opcoesEntrega[categoria]?.entries
            .map((entry) => ListTile(
          title: Text('Distância: ${entry.key} km'),
          subtitle: Text('Valor: R\$ ${entry.value.toStringAsFixed(2)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  _adicionarOuEditarOpcaoEntrega(
                    categoria: categoria,
                    distancia: entry.key,
                    valor: entry.value,
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: () {
                  setState(() {
                    opcoesEntrega[categoria]?.remove(entry.key);
                    if (opcoesEntrega[categoria]?.isEmpty ?? true) {
                      opcoesEntrega.remove(categoria);
                    }
                  });
                },
              ),
            ],
          ),
        ))
            .toList() ??
            [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Nenhuma opção cadastrada.'),
              ),
            ],
      ),
    );
  }
}
