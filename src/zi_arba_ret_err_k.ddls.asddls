@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Padron Ret - Errores: clasificados'
@Metadata.ignorePropagatedAnnotations: true
// Clasifica cada fila de error y arma la clave de agrupacion (Redmine 33756, 07/10):
// - cada error se muestra UNA vez (clave = mensaje sin partes variables);
// - EXCEPCION: proveedor bloqueado por otro usuario y proveedor no ampliado a la sociedad -> una fila por proveedor;
// - una ejecucion FALLIDA no deja filas en el log -> se agrega una fila desde la cabecera;
// - 14/10: ejecucion EN_PROCESO (job corriendo) -> una sola fila de aviso (categoria 01, no cuenta como error).
define view entity ZI_ARBA_RET_ERR_K
  as select from ZI_ARBA_RET_ERR_R
{
  key EjecucionUUID,
  key LogUUID,
      cast( case
        when MarcaBloqueo = 'X' and ( Estado = 'ETE' or MensajeBase like 'NO APLICADO:%' ) then '10'
        when Estado = 'ETE' or Estado = 'ACT' or Estado = 'BAJ'
          or ( Estado = 'OMI' and Caso = 'B' )                          then '20'
        when Estado = 'OMI' and Caso = '1'                              then '30'
        when Estado = 'DUP'                                             then '40'
        when Estado = 'PCF' or Estado = 'OMI'                           then '50'
        else                                                                 '60'
      end as abap.char(2) ) as Categoria,
      cast( case
        when MarcaBloqueo = 'X' and ( Estado = 'ETE' or MensajeBase like 'NO APLICADO:%' ) then 'Proveedor bloqueado'
        when Estado = 'ETE' or Estado = 'ACT' or Estado = 'BAJ'
          or ( Estado = 'OMI' and Caso = 'B' )                          then 'Técnico / API'
        when Estado = 'OMI' and Caso = '1'                              then 'Dato maestro'
        when Estado = 'DUP'                                             then 'Dato maestro'
        when Estado = 'PCF' or Estado = 'OMI'                           then 'Configuración'
        else                                                                 'Archivo'
      end as abap.char(20) ) as CategoriaTexto,
      // Bloqueo / no ampliado: el texto puede traer el usuario o el nro de BP -> se agrupa por proveedor
      cast( case
        when MarcaBloqueo = 'X' and ( Estado = 'ETE' or MensajeBase like 'NO APLICADO:%' ) then Proveedor
        when Estado = 'OMI' and Caso = '1'                              then Proveedor
        else ''
      end as abap.char(10) ) as ProveedorClave,
      cast( MensajeBase as abap.char(255) ) as MensajeClave,
      Cuit,
      Proveedor
}
union all
  select from zarba_ret_ejec as ejec
{
  key ejec.ejecucion_uuid as EjecucionUUID,
  key ejec.ejecucion_uuid as LogUUID,
      cast( '00' as abap.char(2) )  as Categoria,
      cast( 'Ejecución' as abap.char(20) ) as CategoriaTexto,
      cast( '' as abap.char(10) ) as ProveedorClave,
      cast( 'La ejecución terminó FALLIDA: el archivo está vacío, no tiene líneas válidas o no se pudo procesar.' as abap.char(255) ) as MensajeClave,
      cast( '' as abap.char(11) ) as Cuit,
      cast( '' as abap.char(10) ) as Proveedor
}
where ejec.estado_ejecucion = 'FALLIDA'
union all
  select from zarba_ret_ejec as ejec
{
  key ejec.ejecucion_uuid as EjecucionUUID,
  key ejec.ejecucion_uuid as LogUUID,
      cast( '01' as abap.char(2) )  as Categoria,
      cast( 'Ejecución' as abap.char(20) ) as CategoriaTexto,
      cast( '' as abap.char(10) ) as ProveedorClave,
      cast( 'Proceso en curso: los errores se muestran al terminar. Actualice la página (F5) en unos minutos.' as abap.char(255) ) as MensajeClave,
      cast( '' as abap.char(11) ) as Cuit,
      cast( '' as abap.char(10) ) as Proveedor
}
where ejec.estado_ejecucion = 'EN_PROCESO'
