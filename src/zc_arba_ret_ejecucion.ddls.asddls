@EndUserText.label: 'ARBA Retenciones - Ejecucion (Projection)'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@Search.searchable: true
define root view entity ZC_ARBA_RET_EJECUCION
  provider contract transactional_query
  as projection on ZI_ARBA_RET_EJECUCION
{
  key EjecucionUUID,
      IdEjecucion,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_CompanyCode', element: 'CompanyCode' } }]
      Sociedad,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_ARBA_RET_TIPO_VH', element: 'WithholdingTaxType' } }]
      TipoRetencion,
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_ARBA_PROVINCIA_VH', element: 'Provincia' } }]
      Provincia,
      NombreArchivo,
      TamanioArchivo,
      Archivo,
      MimeType,
      ModoSimulacion,
      ActualizarSoloPadron,
      // Indicador: codigos del tipo de TipoIndFuera (Tucuman: Tipo Ret. Fuera de Padron; resto: Tipo de Retencion)
      @Consumption.valueHelpDefinition: [{ entity:            { name: 'I_WithholdingTaxCodeVH', element: 'WithholdingTaxCode' },
                                           additionalBinding: [ { localElement: 'TipoIndFuera', element: 'WithholdingTaxType', usage: #FILTER } ] }]
      IndicadorFueraPadron,
      // Salta: Indicador Fuera de Padron No Salta (codigos del Tipo de Retencion)
      @Consumption.valueHelpDefinition: [{ entity:            { name: 'I_WithholdingTaxCodeVH', element: 'WithholdingTaxCode' },
                                           additionalBinding: [ { localElement: 'TipoRetencion', element: 'WithholdingTaxType', usage: #FILTER } ] }]
      IndicadorFueraPadronNoSal,
      ProvDesde,
      ProvHasta,
      SoloConRetencion,
      // Modo Tucuman: dropdown A / C
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_ARBA_RET_MODO_VH', element: 'Modo' } }]
      ModoArchivo,
      // Tipo de retencion fuera de padron (No Inscriptos, ej. TN)
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_ARBA_RET_TIPO_VH', element: 'WithholdingTaxType' } }]
      TipoRetFueraPadron,
      // Indicadores del tipo de padron (filtra WithholdingTaxCode por el WithholdingTaxType de TipoRetencion)
      @Consumption.valueHelpDefinition: [{ entity:            { name: 'I_WithholdingTaxCodeVH', element: 'WithholdingTaxCode' },
                                           additionalBinding: [ { localElement: 'TipoRetencion', element: 'WithholdingTaxType', usage: #FILTER } ] }]
      IndicadorExentoCM,
      @Consumption.valueHelpDefinition: [{ entity:            { name: 'I_WithholdingTaxCodeVH', element: 'WithholdingTaxCode' },
                                           additionalBinding: [ { localElement: 'TipoRetencion', element: 'WithholdingTaxType', usage: #FILTER } ] }]
      IndicadorCmCoef0,
      Usuario,
      FechaHora,
      EstadoEjecucion,
      TotalLeidos,
      TotalActualizados,
      TotalSinCambios,
      TotalNoEncontrados,
      TotalRechazados,
      TotalErrorTecnico,
      TotalPendienteConfig,
      TotalOmitidos,
      AlicuotasPend,
      JobPartidas,
      ExportContent,
      ExportMime,
      ExportFilename,
      LastChangedAt,
      LocalLastChangedAt,
      EstadoEjecucionCriticality,
      HideTuc,
      HideCmCoef0,
      TipoIndFuera,
      HideSal,
      CantErrores,
      ErroresCriticality,
      ErroresEstado,

      _Log : redirected to composition child ZC_ARBA_RET_EJEC_LOG,
      _Errores
}


