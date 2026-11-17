@EndUserText.label: 'ARBA Retenciones - Log de Ejecucion (Interface)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define view entity ZI_ARBA_RET_EJEC_LOG
  as select from zarba_ret_log as log
  association to parent ZI_ARBA_RET_EJECUCION as _Ejecucion
    on $projection.EjecucionUUID = _Ejecucion.EjecucionUUID
{
  key log.ejecucion_uuid        as EjecucionUUID,
  key log.log_uuid              as LogUUID,

      log.nro_linea             as NroLinea,
      log.cuit                  as Cuit,
      log.proveedor             as Proveedor,
      log.caso                  as Caso,
      log.tipo_ret              as TipoRet,

      // Valores anterior / nuevo (EF seccion 11)
      log.indicador_anterior    as IndicadorAnterior,
      log.indicador_nuevo       as IndicadorNuevo,
      log.alicuota_anterior     as AlicuotaAnterior,
      log.alicuota_nueva        as AlicuotaNueva,
      log.sujeto_ret_anterior   as SujetoRetAnterior,
      log.sujeto_ret_nuevo      as SujetoRetNuevo,

      // Resultado
      log.estado                as Estado,
      log.mensaje               as Mensaje,
      log.estado_tecnico        as EstadoTecnico,

      // Informativos del archivo (solo log)
      log.tipo_contribuyente    as TipoContribuyente,
      log.marca_alta_baja       as MarcaAltaBaja,
      log.marca_cambio_alic     as MarcaCambioAlic,
      log.nro_grupo             as NroGrupo,
      log.fecha_publicacion     as FechaPublicacion,
      log.vigencia_desde        as VigenciaDesde,
      log.vigencia_hasta        as VigenciaHasta,

      @Semantics.systemDateTime.lastChangedAt: true
      log.last_changed_at       as LastChangedAt,

      // Criticidad del estado de negocio (semaforo en UI)
      case log.estado
        when 'ACT' then 3   // Actualizado          -> verde
        when 'SCB' then 0   // Sin cambios          -> neutral
        when 'NOE' then 0   // No encontrado        -> neutral
        when 'REV' then 1   // Rechazado validacion -> rojo
        when 'DUP' then 1   // Duplicado en SAP     -> rojo
        when 'ETE' then 1   // Error tecnico        -> rojo
        when 'PCF' then 2   // Pendiente config     -> amarillo
        when 'OMI' then 0   // Omitido              -> neutral
        when 'BAJ' then 2   // Baja del tipo (API)  -> amarillo
        else 0
      end                       as EstadoCriticality,

      _Ejecucion
}
