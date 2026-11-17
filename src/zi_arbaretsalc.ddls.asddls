@EndUserText.label: 'Padrón Salta - Condición'
@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
define view entity ZI_ArbaRetSalc
  as select from ZARBA_RET_SALC
  association to parent ZI_ArbaRetSalc_S as _SaltaCondicionAll on $projection.SingletonID = _SaltaCondicionAll.SingletonID
{
  key WITHT as Witht,
  key CONDICION as Condicion,
  WT_WITHCD as WtWithcd,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  @Consumption.hidden: true
  LOCAL_LAST_CHANGED_AT as LocalLastChangedAt,
  @Semantics.systemDateTime.lastChangedAt: true
  LAST_CHANGED_AT as LastChangedAt,
  @Consumption.hidden: true
  1 as SingletonID,
  _SaltaCondicionAll
}
