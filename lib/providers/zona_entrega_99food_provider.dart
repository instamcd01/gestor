import 'zona_entrega_provider.dart';

/// Zonas de entrega específicas da 99Food — tabela independente
/// (zonas_entrega_99food), configurada separadamente da loja própria.
/// Ver [[gestor_99food_integration_architecture]]: cada canal tem sua
/// própria config, sem sincronização automática entre eles.
class ZonaEntrega99FoodProvider extends ZonaEntregaProvider {
  ZonaEntrega99FoodProvider() : super(tabela: 'zonas_entrega_99food');
}
