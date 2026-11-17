@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Padron Ret - Cantidad de errores'
// Cantidad de errores distintos por ejecucion (semaforo de la solapa "Errores").
// La fila de aviso "Proceso en curso" (categoria 01) no es un error.
define view entity ZI_ARBA_RET_ERR_CNT
  as select from ZI_ARBA_RET_EJEC_ERR
{
  key EjecucionUUID,
      count( * ) as CantErrores
}
where Categoria <> '01'
group by EjecucionUUID
