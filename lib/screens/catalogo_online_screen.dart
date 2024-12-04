import 'package:flutter/material.dart';

class CatalogoOnlineScreen extends StatefulWidget {
  @override
  _CatalogoOnlineScreenState createState() => _CatalogoOnlineScreenState();
}

class _CatalogoOnlineScreenState extends State<CatalogoOnlineScreen> {
  String lojaNome = 'Nome da Loja';
  String lojaLink = 'https://www.exemplo.com';
  String catalogoVersao = 'Clássico';
  String corPrincipal = 'Azul';
  bool pedidosOnline = false;
  String whatsapp = '';
  String instagram = '';
  String facebook = '';
  String email = '';
  String informacoesExtras = '';
  String cpfCnpj = '';
  String razaoSocial = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Catálogo Online'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: <Widget>[
            // Publicar Catálogo
            ElevatedButton(
              onPressed: () {
                // Lógica para publicar o catálogo online
                print('Publicando catálogo online...');
              },
              child: Text('Publicar Catálogo Online'),
            ),
            SizedBox(height: 16),
            // Endereço do site
            ListTile(
              title: Text('Endereço do Site'),
              subtitle: Text(lojaLink),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição de nome da loja e link
                  _editarEndereco();
                },
              ),
            ),
            SizedBox(height: 16),
            // Versão do catálogo
            ListTile(
              title: Text('Versão do Catálogo'),
              subtitle: Text(catalogoVersao),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição da versão do catálogo
                  _editarVersaoCatalogo();
                },
              ),
            ),
            SizedBox(height: 16),
            // Dados da Loja
            ListTile(
              title: Text('Dados da Loja'),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição dos dados da loja
                  // _editarDadosLoja();
                },
              ),
            ),
            SizedBox(height: 16),
            // Identificação
            ListTile(
              title: Text('Identificação'),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição de CPF ou CNPJ
                  // _editarIdentificacao();
                },
              ),
            ),
            SizedBox(height: 16),
            // Opções de Exibição
            ListTile(
              title: Text('Opções de Exibição'),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição das opções de exibição
                  // _editarExibicao();
                },
              ),
            ),
            SizedBox(height: 16),
            // Pedidos
            ListTile(
              title: Text('Pedidos'),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição das configurações de pedidos
                  // _editarPedidos();
                },
              ),
            ),
            SizedBox(height: 16),
            // Redes Sociais e Outros
            ListTile(
              title: Text('Redes Sociais e Outros'),
              trailing: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () {
                  // Redireciona para a tela de edição de redes sociais e outras informações
                  // _editarRedesSociais();
                },
              ),
            ),
            SizedBox(height: 16),
            // Botão para abrir catálogo
            ElevatedButton(
              onPressed: () {
                // Lógica para abrir o catálogo online
                print('Abrindo catálogo...');
              },
              child: Text('Abrir Catálogo'),
            ),
            SizedBox(height: 16),
            // Botão para compartilhar catálogo
            ElevatedButton(
              onPressed: () {
                // Lógica para compartilhar o catálogo
                print('Compartilhando catálogo...');
              },
              child: Text('Compartilhar Catálogo'),
            ),
          ],
        ),
      ),
    );
  }

  void _editarEndereco() {
    // Redirecionar para a tela de edição do nome da loja e link
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditarEnderecoScreen(lojaNome, lojaLink)),
    );
  }

  void _editarVersaoCatalogo() {
    // Redirecionar para a tela de edição da versão do catálogo
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditarVersaoCatalogoScreen()),
    );
  }

  // void _editarDadosLoja() {
  //   // Redirecionar para a tela de edição dos dados da loja
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (context) => EditarDadosLojaScreen()),
  //   );
  // }
  //
  // void _editarIdentificacao() {
  //   // Redirecionar para a tela de edição de CPF ou CNPJ
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (context) => EditarIdentificacaoScreen()),
  //   );
  // }
  //
  // void _editarExibicao() {
  //   // Redirecionar para a tela de edição das opções de exibição
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (context) => EditarExibicaoScreen()),
  //   );
  // }
  //
  // void _editarPedidos() {
  //   // Redirecionar para a tela de edição de pedidos
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (context) => EditarPedidosScreen()),
  //   );
  // }
  //
  // void _editarRedesSociais() {
  //   // Redirecionar para a tela de edição de redes sociais
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (context) => EditarRedesSociaisScreen()),
  //   );
  // }
}

class EditarEnderecoScreen extends StatelessWidget {
  final String nomeLoja;
  final String linkLoja;

  EditarEnderecoScreen(this.nomeLoja, this.linkLoja);

  @override
  Widget build(BuildContext context) {
    TextEditingController nomeController = TextEditingController(text: nomeLoja);
    TextEditingController linkController = TextEditingController(text: linkLoja);

    return Scaffold(
      appBar: AppBar(title: Text('Editar Endereço')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: nomeController,
              decoration: InputDecoration(labelText: 'Nome da Loja'),
            ),
            TextField(
              controller: linkController,
              decoration: InputDecoration(labelText: 'Link da Loja'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Lógica para salvar alterações
                print('Salvando alterações de endereço...');
              },
              child: Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

// Exemplo de outras telas de edição que você pode criar de forma similar

class EditarVersaoCatalogoScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar Versão do Catálogo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Escolha a versão do catálogo:'),
            RadioListTile<String>(
              title: Text('Clássico'),
              value: 'Clássico',
              groupValue: 'Clássico',
              onChanged: (value) {},
            ),
            RadioListTile<String>(
              title: Text('Novo'),
              value: 'Novo',
              groupValue: 'Clássico',
              onChanged: (value) {},
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Lógica para salvar as alterações
                print('Salvando versão do catálogo...');
              },
              child: Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
