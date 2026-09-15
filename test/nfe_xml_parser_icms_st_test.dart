import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/services/nfe_xml_parser.dart';

// XML mínimo, mas real na estrutura: 1 item com ICMS-ST (CST 70) + IPI
// tributado, igual ao padrão encontrado numa nota real de fornecedor
// (achado 15/09: vICMSST/vFCPST/vIPI não entravam no custo, subestimando
// custo e superestimando margem).
const _xmlComEncargos = '''
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe">
  <NFe>
    <infNFe Id="NFe33260906347830000257550010014607581263321001" versao="4.00">
      <ide><nNF>1460758</nNF><serie>1</serie><dhEmi>2026-09-14T00:00:00-03:00</dhEmi></ide>
      <emit><CNPJ>06347830000257</CNPJ><xNome>Fornecedor Teste</xNome></emit>
      <det nItem="1">
        <prod>
          <cEAN>7899599607324</cEAN>
          <xProd>Produto com ICMS-ST</xProd>
          <NCM>23091000</NCM>
          <qCom>2.0000</qCom>
          <vUnCom>2.2100000000</vUnCom>
          <vProd>4.42</vProd>
        </prod>
        <imposto>
          <ICMS><ICMS70><CST>70</CST><vICMSST>0.15</vICMSST><vFCPST>0.01</vFCPST></ICMS70></ICMS>
          <IPI><IPITrib><CST>50</CST><vIPI>0.10</vIPI></IPITrib></IPI>
        </imposto>
      </det>
      <total><ICMSTot><vProd>4.42</vProd><vNF>4.68</vNF></ICMSTot></total>
    </infNFe>
  </NFe>
</nfeProc>
''';

void main() {
  test('custo unitário do item soma ICMS-ST + FCP-ST + IPI, não só vUnCom', () {
    final nfe = NfeXmlParser.parse(_xmlComEncargos);
    final item = nfe.itens.single;

    // vProd(4.42) + vICMSST(0.15) + vFCPST(0.01) + vIPI(0.10) = 4.68,
    // dividido pela quantidade (2) = 2.34 por unidade — bem acima do
    // vUnCom (2.21) que o parser usava sozinho antes da correção.
    expect(item.valorTotal, closeTo(4.68, 0.001));
    expect(item.custoUnitario, closeTo(2.34, 0.001));
  });

  test('item sem nenhum encargo continua igual a vProd/qCom (sem regressão)', () {
    const xmlSemEncargos = '''
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe">
  <NFe>
    <infNFe Id="NFe33260906347830000257550010014607581263321001" versao="4.00">
      <ide><nNF>1</nNF><serie>1</serie><dhEmi>2026-09-14T00:00:00-03:00</dhEmi></ide>
      <emit><CNPJ>06347830000257</CNPJ><xNome>Fornecedor Teste</xNome></emit>
      <det nItem="1">
        <prod><cEAN>123</cEAN><xProd>Produto simples</xProd><qCom>3.0</qCom><vUnCom>10.00</vUnCom><vProd>30.00</vProd></prod>
        <imposto><ICMS><ICMS00><CST>00</CST></ICMS00></ICMS></imposto>
      </det>
      <total><ICMSTot><vProd>30.00</vProd><vNF>30.00</vNF></ICMSTot></total>
    </infNFe>
  </NFe>
</nfeProc>
''';
    final nfe = NfeXmlParser.parse(xmlSemEncargos);
    final item = nfe.itens.single;
    expect(item.custoUnitario, closeTo(10.00, 0.001));
    expect(item.valorTotal, closeTo(30.00, 0.001));
  });
}
