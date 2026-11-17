@EndUserText.label: 'ARBA Ret. - Frecuencia de texto por Tipo'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.resultSet.sizeCategory: #XS
// Cuantos indicadores del tipo comparten el mismo texto sin alicuota
define view entity ZI_ARBA_RET_TIPO_TXT_C
  as select from ZI_ARBA_RET_TIPO_TXT_B as b
{
  key b.Country,
  key b.WithholdingTaxType,
  key b.TextoBase,
      count( * ) as Cantidad
}
group by b.Country,
         b.WithholdingTaxType,
         b.TextoBase
