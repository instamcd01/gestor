import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/veiculo.dart';
import '../providers/auth_provider.dart';
import '../repositories/veiculo_repository.dart';
import 'despesas_veiculo_screen.dart';

/// Cadastro dos veículos próprios da loja (moto/carro) — cada um leva pro
/// seu histórico de despesas reais (`DespesasVeiculoScreen`), usado pra
/// calcular custo/km de verdade em vez de estimativa estática. Um
/// entregador se vincula a um desses veículos (Usuários > Entregador)
/// quando usa moto da loja; entregador com veículo próprio não precisa de
/// nenhum veículo cadastrado aqui.
class VeiculosScreen extends StatefulWidget {
  const VeiculosScreen({super.key});

  @override
  State<VeiculosScreen> createState() => _VeiculosScreenState();
}

class _VeiculosScreenState extends State<VeiculosScreen> {
  final _repo = VeiculoRepository();
  List<Veiculo> _veiculos = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final veiculos = await _repo.listar();
      if (!mounted) return;
      setState(() => _veiculos = veiculos);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar veículos: $e')));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirFormulario({Veiculo? veiculo}) async {
    final nomeController = TextEditingController(text: veiculo?.nome ?? '');
    var tipo = veiculo?.tipo ?? 'moto';
    var ativo = veiculo?.ativo ?? true;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(veiculo == null ? 'Novo veículo' : 'Editar veículo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome/apelido', hintText: 'Ex: Moto Biz vermelha'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'moto', child: Text('Moto')),
                  DropdownMenuItem(value: 'carro', child: Text('Carro')),
                  DropdownMenuItem(value: 'bicicleta', child: Text('Bicicleta')),
                  DropdownMenuItem(value: 'outro', child: Text('Outro')),
                ],
                onChanged: (v) => setDialogState(() => tipo = v ?? 'moto'),
              ),
              if (veiculo != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  value: ativo,
                  onChanged: (v) => setDialogState(() => ativo = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (salvar != true || !mounted) return;
    final nome = nomeController.text.trim();
    if (nome.isEmpty) return;

    try {
      if (veiculo == null) {
        final empresaId = context.read<AuthProvider>().empresaId;
        if (empresaId == null) return;
        await _repo.criar(Veiculo(nome: nome, tipo: tipo), empresaId: empresaId);
      } else {
        await _repo.atualizar(Veiculo(id: veiculo.id, nome: nome, tipo: tipo, ativo: ativo));
      }
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  IconData _iconePara(String tipo) => switch (tipo) {
        'moto' => Icons.two_wheeler_outlined,
        'carro' => Icons.directions_car_outlined,
        'bicicleta' => Icons.pedal_bike_outlined,
        _ => Icons.local_shipping_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Veículos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _veiculos.isEmpty
              ? const Center(child: Text('Nenhum veículo cadastrado ainda.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _veiculos.length,
                  itemBuilder: (context, i) {
                    final v = _veiculos[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(_iconePara(v.tipo)),
                        title: Text(v.nome, style: TextStyle(color: v.ativo ? null : Theme.of(context).disabledColor)),
                        subtitle: Text(v.ativo ? 'Ativo' : 'Inativo'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _abrirFormulario(veiculo: v),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DespesasVeiculoScreen(veiculo: v)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
