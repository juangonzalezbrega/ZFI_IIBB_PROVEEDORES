@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proveedores por region de domicilio (TUC fuera de padron)'
// Fuente de proveedores por region del domicilio para el caso 6 de Tucuman (fuera de padron): a los
// proveedores con domicilio en Tucuman (REGION 14) que no estan en el archivo se les asigna el tipo
// No Inscriptos (TN). Navega la asociacion liberada _AddressDefaultRepresentation de I_Supplier, que
// activa en ABAP Cloud. NOTA: la lectura de la direccion del BP puede requerir autorizacion; si el
// usuario con que corre el job no la tiene, la lectura vuelve vacia o da error y el motor NO ejecuta
// el fuera de padron por region (blindaje en ZCL_ARBA_RET_BP_UPDATER: nunca genera un snapshot vacio).
define view entity ZI_ARBA_RET_SUP_REGION
  as select from I_Supplier
{
  key Supplier                             as Supplier,
      _AddressDefaultRepresentation.Region as Region
}
