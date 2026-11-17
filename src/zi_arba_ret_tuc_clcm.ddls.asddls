@EndUserText.label: 'Tucuman - Equivalencia alicuota/codigo + CL/CM (desde ZTFI_RET_TUC)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZI_ARBA_RET_TUC_CLCM
  as select from ztfi_ret_tuc
{
  key cast( 'AR' as abap.char( 3 ) ) as Country,
  key witht                          as WithholdingTaxType,
  key wt_withcd                      as WithholdingTaxCode,
      wt_qsatz                       as WithholdingTaxPercent,
      conv_mult                      as ConvMult
}
where wt_withcd <> '99'
