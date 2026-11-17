@EndUserText.label: 'ARBA Ret. - Texto representativo por Tipo de Retencion'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.resultSet.sizeCategory: #XS
// Texto del tipo = texto mas frecuente de sus indicadores, sin la alicuota
// (ver ZI_ARBA_RET_TIPO_TXT_B/_C/_M). Ej.: tipo 21 -> 'IIBB Santa Fe'.
// Las vistas de texto de tipo de retencion (I_WithholdingTaxTypeText, etc.) no estan liberadas.
define view entity ZI_ARBA_RET_TIPO_TXT
  as select from ZI_ARBA_RET_TIPO_TXT_M as m
{
  key m.Country,
  key m.WithholdingTaxType,
      cast( substring( m.ClaveOrden, 6, 40 ) as abap.char(40) ) as Descripcion
}
