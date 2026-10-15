/// Domínio da plataforma onde cada loja ganha seu subdomínio
/// (`<link-da-loja>.<kDominioBaseLojas>`). Espelha `dominio_base_lojas()` no
/// banco — trocar nos dois lugares quando a INARI tiver domínio próprio.
const String kDominioBaseLojas = 'inari.lukz.com.br';

/// IP da VPS pra onde o domínio próprio da loja deve apontar (registro A).
const String kIpServidorLojas = '187.77.60.141';
