@EndUserText.label: 'ARBA Retenciones - VH Tipo de Retencion'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.resultSet.sizeCategory: #XS
@Search.searchable: true
define view entity ZI_ARBA_RET_TIPO_VH
  as select distinct from I_WithholdingTaxCodeVH as vh
    left outer join ZI_ARBA_RET_TIPO_TXT as txt
      on  txt.Country            = vh.Country
      and txt.WithholdingTaxType = vh.WithholdingTaxType
{
      @ObjectModel.text.element: ['Descripcion']
  key vh.WithholdingTaxType as WithholdingTaxType,
      @Semantics.text: true
      txt.Descripcion       as Descripcion
}
where vh.Country = 'AR'
