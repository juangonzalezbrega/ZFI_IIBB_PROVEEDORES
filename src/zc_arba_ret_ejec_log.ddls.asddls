@EndUserText.label: 'ARBA Retenciones - Log de Ejecucion (Projection)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@Search.searchable: true
define view entity ZC_ARBA_RET_EJEC_LOG
  as projection on ZI_ARBA_RET_EJEC_LOG
{
  key EjecucionUUID,
  key LogUUID,
      NroLinea,
      Cuit,
      Proveedor,
      Caso,
      TipoRet,
      IndicadorAnterior,
      IndicadorNuevo,
      AlicuotaAnterior,
      AlicuotaNueva,
      SujetoRetAnterior,
      SujetoRetNuevo,
      Estado,
      Mensaje,
      EstadoTecnico,
      TipoContribuyente,
      MarcaAltaBaja,
      MarcaCambioAlic,
      NroGrupo,
      FechaPublicacion,
      VigenciaDesde,
      VigenciaHasta,
      LastChangedAt,
      EstadoCriticality,

      _Ejecucion : redirected to parent ZC_ARBA_RET_EJECUCION
}
// Redmine 33756 (13/10): sin filas NOE (CUIT sin proveedor en SAP) en el Log de Auditoria; tambien oculta
// las corridas anteriores. El total sigue en TotalNoEncontrados de la cabecera.
where
  Estado <> 'NOE'
