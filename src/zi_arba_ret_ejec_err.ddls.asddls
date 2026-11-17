@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Padron Ret - Errores de la ejecucion'
@Metadata.allowExtensions: true
// Solapa "Errores" de la ejecucion: cada error una sola vez (salvo bloqueo / no ampliado: uno por proveedor).
define view entity ZI_ARBA_RET_EJEC_ERR
  as select from ZI_ARBA_RET_ERR_K
{
  key EjecucionUUID,
  key Categoria,
  key MensajeClave,
  key ProveedorClave,
      CategoriaTexto,
      count( * )  as Cantidad,
      min( Cuit ) as CuitEjemplo
}
group by EjecucionUUID, Categoria, MensajeClave, ProveedorClave, CategoriaTexto
