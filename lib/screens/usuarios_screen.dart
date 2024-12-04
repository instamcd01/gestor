import 'package:flutter/material.dart';

// Classe principal da tela de usuários
class UsuariosScreen extends StatefulWidget {
  @override
  _UsuariosScreenState createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  // Lista de usuários simulada
  List<Map<String, String>> usuarios = [
    {"foto": "https://placekitten.com/200/200", "nome": "João Silva", "email": "joao@example.com", "senha": "123456"},
    {"foto": "https://placekitten.com/200/200", "nome": "Maria Oliveira", "email": "maria@example.com", "senha": "abcdef"},
    {"foto": "https://placekitten.com/200/200", "nome": "Carlos Pereira", "email": "carlos@example.com", "senha": "qwerty"},
    // Adicione mais usuários conforme necessário
  ];

  // Controlador para pesquisa
  TextEditingController _searchController = TextEditingController();

  // Filtragem dos usuários conforme a pesquisa
  List<Map<String, String>> get filteredUsuarios {
    String query = _searchController.text.toLowerCase();
    return usuarios
        .where((user) =>
    user['nome']!.toLowerCase().contains(query) ||
        user['email']!.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Usuários'),
        actions: [
          // Ícone de adicionar um novo usuário
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              // Navegação para a tela de adicionar novo usuário
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => NovoUsuarioScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Campo de pesquisa
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Pesquisar Usuário',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
            SizedBox(height: 8),
            // Lista de usuários
            Expanded(
              child: ListView.builder(
                itemCount: filteredUsuarios.length,
                itemBuilder: (context, index) {
                  final usuario = filteredUsuarios[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(usuario['foto']!),
                    ),
                    title: Text(usuario['nome']!),
                    subtitle: Text(usuario['email']!),
                    onTap: () {
                      // Navegação para a tela de detalhes do usuário
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UsuarioDetailScreen(usuario),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Tela para adicionar novo usuário (simulada)
class NovoUsuarioScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Adicionar Novo Usuário')),
      body: Center(child: Text('Tela para adicionar novo usuário')),
    );
  }
}

// Tela de detalhes do usuário
class UsuarioDetailScreen extends StatelessWidget {
  final Map<String, String> usuario;

  UsuarioDetailScreen(this.usuario);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(usuario['nome']!),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(usuario['foto']!),
            ),
            SizedBox(height: 16),
            Text('Nome: ${usuario['nome']}'),
            SizedBox(height: 8),
            Text('Email: ${usuario['email']}'),
            SizedBox(height: 8),
            Text('Senha: ${usuario['senha']}'),
          ],
        ),
      ),
    );
  }
}
