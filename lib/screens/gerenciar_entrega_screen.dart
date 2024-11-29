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
  Map<String, Map<String, double>> tempOpcoesEntrega = {};

  // Controladores para os campos de entrada
  final _tipoEntregaController = TextEditingController();
  final _distanciaController = TextEditingController();
  final _valorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    tempOpcoesEntrega = Map.from(widget.opcoesEntrega);
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
            // Exibe as opções de entrega cadastradas
            Expanded(
              child: ListView.builder(
                itemCount: tempOpcoesEntrega.keys.length,
                itemBuilder: (ctx, index) {
                  String tipoEntrega = tempOpcoesEntrega.keys.elementAt(index);
                  return ListTile(
                    title: Text(tipoEntrega),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: tempOpcoesEntrega[tipoEntrega]!
                          .entries
                          .map((entry) => Text('${entry.key}: R\$ ${entry.value}'))
                          .toList(),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () {
                            // Quando clicar em editar, preencher os campos com os valores atuais
                            _tipoEntregaController.text = tipoEntrega;
                            _distanciaController.text = tempOpcoesEntrega[tipoEntrega]!.keys.first;
                            _valorController.text = tempOpcoesEntrega[tipoEntrega]!.values.first.toString();
                            showDialog(
                              context: context,
                              builder: (ctx) {
                                return AlertDialog(
                                  title: Text('Editar Opção de Entrega'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: _tipoEntregaController,
                                        decoration: InputDecoration(labelText: 'Tipo de Entrega'),
                                      ),
                                      TextField(
                                        controller: _distanciaController,
                                        decoration: InputDecoration(labelText: 'Distância (km)'),
                                      ),
                                      TextField(
                                        controller: _valorController,
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(labelText: 'Valor'),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                      },
                                      child: Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        String tipoEntrega = _tipoEntregaController.text;
                                        String distancia = _distanciaController.text;
                                        double valor = double.tryParse(_valorController.text) ?? 0.0;

                                        setState(() {
                                          tempOpcoesEntrega[tipoEntrega]![distancia] = valor;
                                        });

                                        Navigator.of(ctx).pop();
                                      },
                                      child: Text('Salvar'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete),
                          onPressed: () {
                            setState(() {
                              tempOpcoesEntrega.remove(tipoEntrega);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // Adiciona uma nova opção de entrega
                showDialog(
                  context: context,
                  builder: (ctx) {
                    return AlertDialog(
                      title: Text('Adicionar Nova Opção de Entrega'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _tipoEntregaController,
                            decoration: InputDecoration(labelText: 'Tipo de Entrega'),
                          ),
                          TextField(
                            controller: _distanciaController,
                            decoration: InputDecoration(labelText: 'Distância (km)'),
                          ),
                          TextField(
                            controller: _valorController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: 'Valor'),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                          },
                          child: Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () {
                            String tipoEntrega = _tipoEntregaController.text;
                            String distancia = _distanciaController.text;
                            double valor = double.tryParse(_valorController.text) ?? 0.0;

                            setState(() {
                              if (tempOpcoesEntrega[tipoEntrega] == null) {
                                tempOpcoesEntrega[tipoEntrega] = {};
                              }
                              tempOpcoesEntrega[tipoEntrega]![distancia] = valor;
                            });

                            Navigator.of(ctx).pop();
                          },
                          child: Text('Salvar'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: Text('Adicionar Nova Opção de Entrega'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                widget.onSalvarOpcoesEntrega(tempOpcoesEntrega);
                Navigator.pop(context);
              },
              child: Text('Salvar Alterações'),
            ),
          ],
        ),
      ),
    );
  }
}
