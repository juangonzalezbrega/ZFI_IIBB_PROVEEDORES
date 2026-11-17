@EndUserText.label: 'ARBA Retenciones - Ejecucion (Interface)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define root view entity ZI_ARBA_RET_EJECUCION
  as select from zarba_ret_ejec as ejec
  composition [0..*] of ZI_ARBA_RET_EJEC_LOG as _Log
  // Solapa "Errores" (Redmine 33756, 07/10): errores sin repetir, calculados al vuelo desde el log.
  association [0..*] to ZI_ARBA_RET_EJEC_ERR as _Errores on $projection.EjecucionUUID = _Errores.EjecucionUUID
  association [0..1] to ZI_ARBA_RET_ERR_CNT  as _ErrCnt  on $projection.EjecucionUUID = _ErrCnt.EjecucionUUID
{
  key ejec.ejecucion_uuid          as EjecucionUUID,
      ejec.id_ejecucion            as IdEjecucion,

      // Parametros de ejecucion (EF seccion 8)
      ejec.sociedad                as Sociedad,
      ejec.tipo_retencion          as TipoRetencion,
      ejec.provincia               as Provincia,
      ejec.nombre_archivo          as NombreArchivo,
      ejec.tamanio_archivo         as TamanioArchivo,
      @Semantics.largeObject: { mimeType: 'MimeType',
                                fileName: 'NombreArchivo',
                                contentDispositionPreference: #ATTACHMENT }
      ejec.archivo                 as Archivo,
      @Semantics.mimeType: true
      ejec.mime_type               as MimeType,
      ejec.modo_simulacion         as ModoSimulacion,
      ejec.actualizar_solo_padron  as ActualizarSoloPadron,
      ejec.indicador_fuera_padron  as IndicadorFueraPadron,
      // Control interno: provincia para la que ya se aplico el indicador default (no se muestra en UI)
      ejec.provincia_aplicada      as ProvinciaAplicada,
      ejec.prov_desde              as ProvDesde,
      ejec.prov_hasta              as ProvHasta,
      ejec.solo_con_retencion      as SoloConRetencion,

      // Parametros especificos de Tucuman
      ejec.modo_archivo            as ModoArchivo,
      ejec.tipo_ret_fuera          as TipoRetFueraPadron,
      ejec.indicador_exento_cm     as IndicadorExentoCM,
      ejec.indicador_cm_coef0      as IndicadorCmCoef0,

      // Auditoria
      ejec.usuario                 as Usuario,
      ejec.fecha_hora              as FechaHora,

      // Estado y KPIs (EF seccion 11)
      ejec.estado_ejecucion        as EstadoEjecucion,
      ejec.total_leidos            as TotalLeidos,
      ejec.total_actualizados      as TotalActualizados,
      ejec.total_sin_cambios       as TotalSinCambios,
      ejec.total_no_encontrados    as TotalNoEncontrados,
      ejec.total_rechazados        as TotalRechazados,
      ejec.total_error_tecnico     as TotalErrorTecnico,
      ejec.total_pendiente_config  as TotalPendienteConfig,
      ejec.total_omitidos          as TotalOmitidos,
      // Alicuotas del archivo sin indicador configurado (PCF), p. ej. "0,70 (9); 1,25 (2)". Lo llena el job.
      ejec.alicuotas_pend          as AlicuotasPend,

      // Ajuste de partidas abiertas (EF seccion 6.5)
      ejec.job_partidas            as JobPartidas,

      // Export de cambios (.txt del padron dentro de .zip) para la app estandar de retenciones AR
      @Semantics.largeObject: { mimeType: 'ExportMime',
                                fileName: 'ExportFilename',
                                contentDispositionPreference: #ATTACHMENT }
      ejec.export_content          as ExportContent,
      @Semantics.mimeType: true
      ejec.export_mime             as ExportMime,
      ejec.export_filename         as ExportFilename,

      @Semantics.systemDateTime.lastChangedAt: true
      ejec.last_changed_at         as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      ejec.local_last_changed_at   as LocalLastChangedAt,

      // Criticidad del estado de la ejecucion (semaforo en UI)
      case ejec.estado_ejecucion
        when 'FALLIDA'        then 1   // rojo
        when 'OK_CON_ERRORES' then 2   // amarillo
        when 'OK'             then 3   // verde
        else 0                         // neutral (EN_PROCESO)
      end                          as EstadoEjecucionCriticality,

      // Campo de control (persistente) para ocultar los parametros de Tucuman (@UI.hidden: #(HideTuc)).
      // Lo mantiene la determinacion setHideTuc: 'X' cuando la provincia NO es 'TUC'. Es persistente
      // porque los campos calculados no se recomputan en modo draft.
      ejec.hide_tuc                as HideTuc,

      // Campo de control (persistente) para ocultar "Indicador CM Coef. 0" (@UI.hidden: #(HideCmCoef0)).
      // Lo mantiene la determinacion setHideCmCoef0: 'X' salvo cuando Provincia='TUC' Y ModoArchivo='C'
      // (Coeficientes). Persistente por el mismo motivo que HideTuc (draft no recomputa calculados).
      ejec.hide_cm_coef0           as HideCmCoef0,

      // Campo de control (persistente) para el matchcode de "Indicador Fuera de Padron": tipo de retencion
      // por el que se filtran los codigos (additionalBinding en ZC_ARBA_RET_EJECUCION). Lo mantiene la
      // determinacion setTipoIndFuera: Tucuman -> TipoRetFueraPadron (No Inscriptos); resto -> TipoRetencion.
      // Persistente por el mismo motivo que HideTuc (draft no recomputa calculados).
      ejec.tipo_ind_fuera          as TipoIndFuera,
      // Salta: Indicador Fuera de Padron para proveedores con region distinta de 09 (solo provincia SAL).
      ejec.ind_fuera_no_sal        as IndicadorFueraPadronNoSal,
      // Control persistente (como HideTuc): lo mantiene setHideSal. 'X' si la provincia NO es 'SAL'.
      ejec.hide_sal                as HideSal,

      // Semaforo de la solapa "Errores": rojo si hay algun error, verde si no; neutral mientras no hay resultado.
      cast( coalesce( _ErrCnt.CantErrores, 0 ) as abap.int4 ) as CantErrores,
      cast( case
        when ejec.estado_ejecucion = 'PENDIENTE' or ejec.estado_ejecucion = 'EN_PROCESO' then 0
        when coalesce( _ErrCnt.CantErrores, 0 ) > 0                                      then 1
        else 3
      end as abap.int1 )           as ErroresCriticality,
      cast( case
        when ejec.estado_ejecucion = 'PENDIENTE' or ejec.estado_ejecucion = 'EN_PROCESO' then 'Sin resultado aún'
        when coalesce( _ErrCnt.CantErrores, 0 ) > 0                                      then 'Con errores'
        else 'Sin errores'
      end as abap.char(20) )       as ErroresEstado,

      _Log,
      _Errores
}


