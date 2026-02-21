import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/cliente.dart';
import '../providers/cliente_provider.dart';
import 'editar_cliente_screen.dart';

class ClienteDetalhesScreen extends StatefulWidget {
  final Cliente cliente;

  ClienteDetalhesScreen({required this.cliente});

  @override
  State<ClienteDetalhesScreen> createState() => _ClienteDetalhesScreenState();
}

class _ClienteDetalhesScreenState extends State<ClienteDetalhesScreen> {
  late Cliente cliente;

  @override
  void initState() {
    super.initState();
    cliente = widget.cliente;
  }

  void _atualizarCliente(Cliente clienteAtualizado) {
    setState(() {
      cliente = clienteAtualizado;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(cliente.nome),
          actions: [
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => _confirmarDelecao(context),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Dados'),
              Tab(text: 'Vendas'),
              Tab(text: 'Pedidos'),
              Tab(text: 'Conta'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDadosTab(context),
            Center(child: Text('Vendas')),
            Center(child: Text('Pedidos')),
            Center(child: Text('Conta')),
          ],
        ),
      ),
    );
  }

  Widget _buildDadosTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[300],
              child: Icon(Icons.camera_alt, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.message, color: Colors.green),
                onPressed: () => _abrirWhatsApp(cliente.celular),
              ),
              IconButton(
                icon: Icon(Icons.email, color: Colors.blue),
                onPressed: () => _enviarEmail(cliente.email),
              ),
              IconButton(
                icon: Icon(Icons.location_on, color: Colors.red),
                onPressed: () => _abrirMapa(cliente.endereco),
              ),
            ],
          ),
          const Divider(),
          _buildClienteInfo('Nome', cliente.nome),
          _buildClienteInfo('Celular/WhatsApp', cliente.celular),
          _buildClienteInfo('Endereço', cliente.endereco),
          _buildClienteInfo(
              'Distância', cliente.rangeDistancia != null ? '${cliente.rangeDistancia!.toStringAsFixed(2)} km' : 'Não informado'),
          _buildClienteInfo(
              'Estimativa de entrega', cliente.estimativaEntrega != null ? '${cliente.estimativaEntrega} min' : 'Não informado'),
          _buildClienteInfo('Complemento', cliente.complemento),
          _buildClienteInfo('E-mail', cliente.email),
          _buildClienteInfo('CPF/CNPJ', cliente.cpf),
          _buildClienteInfo('Observação', cliente.observacao),
          _buildClienteInfo('Saldo', 'R\$ ${cliente.saldo.toStringAsFixed(2)}'),
          _buildClienteInfo('Canal de Origem', cliente.canalOrigem ?? 'Não informado'),
          _buildClienteInfo(
              'Aniversário',
              cliente.aniversario != null
                  ? '${cliente.aniversario!.day}/${cliente.aniversario!.month}/${cliente.aniversario!.year}'
                  : 'Não informado'),
          _buildClienteInfo('Aceita Marketing?', cliente.aceitaMarketing == true ? 'Sim' : 'Não'),
          _buildClienteInfo(
              'Data de Cadastro',
              cliente.dataCadastro != null
                  ? '${cliente.dataCadastro!.day}/${cliente.dataCadastro!.month}/${cliente.dataCadastro!.year}'
                  : 'Não informado'),
          _buildClienteInfo('Compras Realizadas', cliente.quantidadeCompras.toString()),
          const SizedBox(height: 20),
          Text(
            'Pets Cadastrados:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          cliente.pets.isNotEmpty
              ? Column(
            children: cliente.pets.map((pet) {
              return ListTile(
                leading: pet.imagemUrl.isNotEmpty
                    ? Image.network(pet.imagemUrl, width: 40, height: 40, fit: BoxFit.cover)
                    : Icon(Icons.pets, size: 30),
                title: Text(pet.nome),
                subtitle: Text('${pet.especie} - ${pet.raca}'),
              );
            }).toList(),
          )
              : Text(
            'Nenhum pet registrado.',
            style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: () async {
                final Cliente? clienteAtualizado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarClienteScreen(
                      clienteSelecionado: cliente,
                    ),
                  ),
                );

                if (clienteAtualizado != null) {
                  _atualizarCliente(clienteAtualizado);
                }
              },
              child: Text('Editar Dados'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteInfo(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.isNotEmpty == true ? value! : 'Não informado',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmarDelecao(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirmar Exclusão'),
        content: Text('Tem certeza de que deseja excluir este cliente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<ClientProvider>(context, listen: false)
                  .removerClienteDoFirestore(cliente);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _abrirWhatsApp(String numero) async {
    final Uri uri = Uri.parse('https://wa.me/55$numero');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Não foi possível abrir $uri';
    }
  }

  void _enviarEmail(String email) async {
    final Uri uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Não foi possível abrir $uri';
    }
  }

  void _abrirMapa(String endereco) async {
    final Uri uri =
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$endereco');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Não foi possível abrir $uri';
    }
  }
}
