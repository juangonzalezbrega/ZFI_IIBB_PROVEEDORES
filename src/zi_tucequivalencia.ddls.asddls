@EndUserText.label: 'Tucuman - Equivalencia alicuota / codigo'
@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
define view entity ZI_TucEquivalencia
  as select from ZARBA_TUC_ALIC
  association to parent ZI_TucEquivalencia_S as _TucumanEquivalenAll on $projection.SingletonID = _TucumanEquivalenAll.SingletonID
{
  key WITHT as Witht,
  key WT_WITHCD as WtWithcd,
  CONV_MULT as ConvMult,
  WT_QSATZ as WtQsatz,
  @Consumption.hidden: true
  1 as SingletonID,
  _TucumanEquivalenAll
}
