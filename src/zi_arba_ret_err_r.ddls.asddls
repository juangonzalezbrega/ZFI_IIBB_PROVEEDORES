
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Padron Ret - Errores: filas del log'

// Solapa "Errores" (Redmine 33756, 07/10): filas del log que son error para el usuario.
// Quedan AFUERA: NOE (CUIT sin proveedor = aviso), SCB, ACT/REG ok, OMI por filtro o duplicado identico.
// Entran tambien filas ACT con fallo en el mensaje (exenciones "NO APLICADO:" -solo el ultimo intento, va al inicio-
// y "Partidas: no se pudo"). "Region ... sin proveedores" (Tucuman) es aviso: no entra.
// 14/10: mientras la ejecucion esta EN_PROCESO (job grabando el log) no se lista nada: la lista seria parcial
// y la UI no se refresca sola al terminar el job (ZI_ARBA_RET_ERR_K muestra en su lugar "Proceso en curso").

define view entity ZI_ARBA_RET_ERR_R
  as select from zarba_ret_log  as log
    inner join   zarba_ret_ejec as ejec on ejec.ejecucion_uuid = log.ejecucion_uuid
{
  key log.ejecucion_uuid as EjecucionUUID,
  key log.log_uuid       as LogUUID,
      log.estado         as Estado,
      log.caso           as Caso,
      log.cuit           as Cuit,
      log.proveedor      as Proveedor,
      log.mensaje        as Mensaje,

      // 'X' = el texto de la API indica que el proveedor esta bloqueado / en uso por otro usuario
      // (like_regexpr no existe en este release: si coincide, todo el texto se reemplaza por 'X').
      replace_regexpr( pcre          => '(?is)^.*(\\blocked by\\b|\\blocked\\b(?! for)|being (processed|edited) by|(bloquead[oa]|siendo (tratad|procesad|editad|modificad|utilizad|usad)[oa]|se est. (tratando|procesando|editando)|tratad[oa]|procesad[oa]|en uso) por (el )?usuario|HTTP 423).*$',
                       value         => log.mensaje,
                       with          => 'X',
                       result_length => 255 ) as MarcaBloqueo,

      // Mensaje sin las partes que cambian por fila (indicador actual, valor leido del archivo, nro de campos)
      // para mostrar cada error UNA sola vez.

      // #33749 H4 - CODIGO ORIGINAL (comentado):
      // replace_regexpr( pcre          => '(?<=\\))\\.\\s.*$|:\\s*".*$|\\s*\\(\\d+\\)|\\s*\\(informado:.*$|\\s*\\(linea de \\d+ caracteres\\)|\\.\\s+(Se mantiene el indicador actual|No se da de alta la retenci).*$|^.*(?=Partidas: no se pudo)|\\s+(Excluido: destildar|Coeficiente <).*$',

      // #33749 H4 - NUEVO: se agregan las alternativas de mensajes de Entre Rios.
      replace_regexpr( pcre          => '(?<=\\))\\.\\s.*$|:\\s*".*$|\\s*\\(\\d+\\)|\\s*\\(informado:.*$|\\s*\\(linea de \\d+ caracteres\\)|\\.\\s+(Se mantiene el indicador actual|No se da de alta la retenci).*$|^.*(?=Partidas: no se pudo)|\\s+(Excluido: destildar|Coeficiente <|ER marca B: destildar|ER: (mantiene|cambio)).*$',
                       value         => log.mensaje,
                       with          => '',
                       result_length => 255 ) as MensajeBase
}
where ejec.estado_ejecucion <> 'EN_PROCESO'
  and ( log.estado = 'REV'
     or log.estado = 'DUP'
     or log.estado = 'PCF'
     or log.estado = 'ETE'
     or ( log.estado = 'OMI' and ( log.mensaje like 'Omitido: proveedor no ampliado%'
                                or log.mensaje like 'Fuera de padron%NO ejecutado%'
                                or log.mensaje like 'Alta fuera de padron%NO ejecutada%'
                                or log.mensaje like 'Baja del tipo%NO aplicada%' ) )
     or ( log.estado = 'ACT' and ( log.mensaje like 'NO APLICADO:%'
                                or log.mensaje like '%Partidas: no se pudo%' ) )
     // Tucuman (nota #57): baja del tipo por API cuyo ajuste de partidas no se pudo programar.
     or ( log.estado = 'BAJ' and log.mensaje like '%Partidas: no se pudo%' ) )
