@EndUserText.label: 'Padrón por provincia'
@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
define view entity ZI_ArbaRetProv
  as select from ZARBA_RET_PROV
  association to parent ZI_ArbaRetProv_S as _PadronProvinciaAll on $projection.SingletonID = _PadronProvinciaAll.SingletonID
{
  key PROVINCIA as Provincia,
  ACTIVA as Activa,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  @Consumption.hidden: true
  LOCAL_LAST_CHANGED_AT as LocalLastChangedAt,
  @Semantics.systemDateTime.lastChangedAt: true
  LAST_CHANGED_AT as LastChangedAt,
  @Consumption.hidden: true
  1 as SingletonID,
  _PadronProvinciaAll
}
