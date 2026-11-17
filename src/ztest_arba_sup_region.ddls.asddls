@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Test region proveedor'
define view entity ZTEST_ARBA_SUP_REGION
  as select from I_Supplier
{
  key Supplier,
      _AddressDefaultRepresentation.Region as Region
}
