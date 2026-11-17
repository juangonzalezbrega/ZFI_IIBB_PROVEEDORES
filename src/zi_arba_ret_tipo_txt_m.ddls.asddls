@EndUserText.label: 'ARBA Ret. - Texto mas frecuente por Tipo'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.resultSet.sizeCategory: #XS
// Clave de orden = (99999 - frecuencia) con 5 digitos + texto: el MIN da el texto
// mas frecuente del tipo y, ante empate, el menor alfabeticamente.
// ZI_ARBA_RET_TIPO_TXT le quita el prefijo numerico.
define view entity ZI_ARBA_RET_TIPO_TXT_M
  as select from ZI_ARBA_RET_TIPO_TXT_C as c
{
  key c.Country,
  key c.WithholdingTaxType,
      min( concat( lpad( cast( 99999 - c.Cantidad as abap.char(11) ), 5, '0' ),
                   c.TextoBase ) ) as ClaveOrden
}
group by c.Country,
         c.WithholdingTaxType
