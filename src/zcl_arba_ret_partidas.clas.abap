CLASS zcl_arba_ret_partidas DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_supplier TYPE c LENGTH 10.
    TYPES ty_jobref   TYPE c LENGTH 32.   " jobname para trazabilidad (F1240)

    "! AJUSTE DE PARTIDAS ABIERTAS (EF seccion 6.5).
    "!
    "! El report on-premise RFWT0010 NO tiene equivalente como API/job PLANIFICABLE en
    "! S/4HANA Cloud Public Edition (verificado 2026-08). El mecanismo Cloud-nativo para
    "! este caso (retencion AR por provincia, keyed por CUIT) es la APP ESTANDAR
    "! "Update Withholding Tax Codes and Open Items": lee el archivo del padron (delimitado)
    "! y actualiza el CODIGO de retencion en el MAESTRO **y ajusta las PARTIDAS ABIERTAS** en
    "! un solo paso, usando la BAdI ES_FIWTAR_UPDATE_TAXCODE (impl. ZCL_ARBA_RET_BADI_TAXCODE)
    "! para determinar el indicador por alicuota igual que el RAP.
    "!
    "! Por eso este metodo YA NO planifica ningun job (no existe plantilla): solo informa que
    "! el ajuste se corre desde esa app. La firma se mantiene por compatibilidad con el saver/job.
    METHODS ajustar_partidas
      IMPORTING iv_sociedad    TYPE bukrs
                iv_prov_desde  TYPE ty_supplier OPTIONAL
                iv_prov_hasta  TYPE ty_supplier OPTIONAL
                iv_fecha_desde TYPE d OPTIONAL
                iv_fecha_hasta TYPE d OPTIONAL
                iv_test        TYPE abap_boolean DEFAULT abap_false
      EXPORTING ev_job         TYPE ty_jobref
                ev_ok          TYPE abap_boolean
                ev_mensaje     TYPE string.
protected section.
private section.
ENDCLASS.



CLASS ZCL_ARBA_RET_PARTIDAS IMPLEMENTATION.


  METHOD ajustar_partidas.
    " EF 6.5 - Ajuste de partidas abiertas.
    " No hay job/API planificable en Cloud Public para el equivalente de RFWT0010. El ajuste
    " (maestro + partidas abiertas) se realiza con la app estandar "Update Withholding Tax
    " Codes and Open Items" alimentada con el padron, usando la BAdI ES_FIWTAR_UPDATE_TAXCODE
    " (impl. ZCL_ARBA_RET_BADI_TAXCODE) para el indicador por alicuota. Aca solo se informa.
    CLEAR: ev_job.
    ev_ok      = abap_false.
    ev_mensaje = 'EF 6.5: ejecutar la app estandar "Update Withholding Tax Codes and Open Items" ' &&
                 'con el padron (BAdI ZCL_ARBA_RET_BADI_TAXCODE) para ajustar maestro + partidas abiertas. ' &&
                 'No hay job planificable en Cloud Public para este ajuste.'.
  ENDMETHOD.
ENDCLASS.
