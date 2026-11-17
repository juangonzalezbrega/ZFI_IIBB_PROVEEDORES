"! Motor del padron IIBB Entre Rios (ATER, retenciones a proveedores, Redmine #33749). Autocontenido,
"! molde ZCL_ARBA_RET_SAL_PROC (zcl_arba_ret_sal_proc.clas.abap). Lo invoca el Application Job para la
"! provincia 'ER'. Persiste el log con los estados/casos del flujo generico, asi ALTA por API, job de
"! partidas, export, BAdI y Errores funcionan sin cambios.
"!   Marca A/S/N -> indicador por ZTFI_RET_TUC (C = CM: alicuota x 0,5 con MA 'X'; D/P = CL: alicuota tal cual)
"!                  y "sujeto a retencion" debe quedar tildado (lo tilda ZCL_ARBA_RET_ER_SUJETO por API).
"!   Marca B     -> no se determina indicador: si tiene el registro del tipo, destildar "sujeto a retencion"
"!                  (caso 'X', lo aplica ZCL_ARBA_RET_ER_SUJETO); si no lo tiene, nada (OMI).
"! Fuera de padron (sin "Actualizar Solo Padron"):
"!   (A) titulares del tipo fuera del archivo: region 05 (AR, ampliado) -> Indicador Fuera de Padron (03);
"!       otra region / vacia / extranjero -> se conserva (SCB keeper), regla 16/10 de todos los padrones.
"!   (B) no titulares region 05, AR y ampliados -> alta caso 4 con el Indicador Fuera de Padron.
"!   Lectura de region con error o archivo sin registros validos -> no se ejecuta (se conservan todos).
CLASS zcl_arba_ret_er_proc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Igual a ZCL_ARBA_RET_SAL_PROC=>ty_log_row + campos informativos del archivo (los lee el export,
    "! zbp_i_arba_ret_ejecucion.clas.locals_imp.abap:609-611 y :799-809).
    TYPES: BEGIN OF ty_log_row,
             nro_linea           TYPE i,
             cuit                TYPE c LENGTH 11,
             proveedor           TYPE c LENGTH 10,
             caso                TYPE c LENGTH 1,
             indicador_anterior  TYPE c LENGTH 2,
             indicador_nuevo     TYPE c LENGTH 2,
             alicuota_anterior   TYPE p LENGTH 5 DECIMALS 2,
             alicuota_nueva      TYPE p LENGTH 5 DECIMALS 2,
             sujeto_ret_anterior TYPE c LENGTH 1,
             sujeto_ret_nuevo    TYPE c LENGTH 1,
             estado              TYPE c LENGTH 3,
             mensaje             TYPE string,
             tipo_contribuyente  TYPE c LENGTH 1,
             marca_alta_baja     TYPE c LENGTH 1,
             marca_cambio_alic   TYPE c LENGTH 1,
             nro_grupo           TYPE c LENGTH 2,
             fecha_publicacion   TYPE d,
             vigencia_desde      TYPE d,
             vigencia_hasta      TYPE d,
           END OF ty_log_row.
    TYPES ty_log_tt TYPE STANDARD TABLE OF ty_log_row WITH EMPTY KEY.

    TYPES: BEGIN OF ty_kpi,
             leidos           TYPE i,
             actualizados     TYPE i,
             sin_cambios      TYPE i,
             no_encontrados   TYPE i,
             rechazados       TYPE i,
             error_tecnico    TYPE i,
             pendiente_config TYPE i,
             omitidos         TYPE i,
           END OF ty_kpi.

    TYPES ty_cuit        TYPE c LENGTH 11.
    TYPES ty_cuit_set    TYPE SORTED TABLE OF ty_cuit WITH UNIQUE KEY table_line.
    TYPES ty_estado_ejec TYPE c LENGTH 15.

    METHODS constructor
      IMPORTING io_parser       TYPE REF TO zcl_arba_ret_er_parser       OPTIONAL
                io_determinador TYPE REF TO zcl_arba_ret_er_determinador OPTIONAL
                io_bp_updater   TYPE REF TO zcl_arba_ret_bp_updater      OPTIONAL.

    "! Punto de entrada desde el job: procesa la ejecucion completa.
    METHODS procesar
      IMPORTING is_ejec    TYPE zarba_ret_ejec
                iv_simular TYPE abap_boolean.

  PRIVATE SECTION.
    CONSTANTS c_lote TYPE i VALUE 1000.

    TYPES: BEGIN OF ty_cuit_dup,
             cuit           TYPE ty_cuit,
             firma          TYPE string,        " tipo|marca|alicuota: misma firma = repetido identico
             contradictorio TYPE abap_boolean,
             procesado      TYPE abap_boolean,
           END OF ty_cuit_dup.
    TYPES ty_cuit_dup_tt TYPE HASHED TABLE OF ty_cuit_dup WITH UNIQUE KEY cuit.

    "! Resumen de PCF por tipo de contribuyente + alicuota del archivo (p. ej. "C 0,25 (859)").
    TYPES: BEGIN OF ty_pcf,
             clave TYPE string,
             cnt   TYPE i,
           END OF ty_pcf.

    DATA mo_parser       TYPE REF TO zcl_arba_ret_er_parser.
    DATA mo_determinador TYPE REF TO zcl_arba_ret_er_determinador.
    DATA mo_bp           TYPE REF TO zcl_arba_ret_bp_updater.
    DATA mt_pcf          TYPE HASHED TABLE OF ty_pcf WITH UNIQUE KEY clave.

    METHODS procesar_registro
      IMPORTING is_ejec   TYPE zarba_ret_ejec
                is_record TYPE zcl_arba_ret_er_parser=>ty_record
      CHANGING  ct_dup    TYPE ty_cuit_dup_tt
                ct_log    TYPE ty_log_tt
                cs_kpi    TYPE ty_kpi.

    METHODS procesar_fuera_padron
      IMPORTING is_ejec        TYPE zarba_ret_ejec
                it_cuit_padron TYPE ty_cuit_set
      CHANGING  ct_log         TYPE ty_log_tt
                cs_kpi         TYPE ty_kpi.

    METHODS alic
      IMPORTING iv_tipo        TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_ind         TYPE zcl_arba_ret_determinador=>ty_wht_code
      RETURNING VALUE(rv_alic) TYPE zcl_arba_ret_determinador=>ty_alicuota.

    METHODS firma
      IMPORTING is_record     TYPE zcl_arba_ret_er_parser=>ty_record
      RETURNING VALUE(rv_fir) TYPE string.

    METHODS sumar_pcf
      IMPORTING is_record TYPE zcl_arba_ret_er_parser=>ty_record.

    METHODS resumen_pcf
      RETURNING VALUE(rv_txt) TYPE string.

    CLASS-METHODS cortar
      IMPORTING iv_txt        TYPE string
      RETURNING VALUE(rv_txt) TYPE string.

    "! Error de UUID sube al CATCH de procesar: ROLLBACK + FALLIDA (nunca un log parcial "OK").
    METHODS persistir_log
      IMPORTING iv_uuid TYPE sysuuid_x16
                it_log  TYPE ty_log_tt
      RAISING   cx_uuid_error.

    METHODS finalizar
      IMPORTING iv_uuid    TYPE sysuuid_x16
                iv_estado  TYPE ty_estado_ejec
                is_kpi     TYPE ty_kpi
                iv_simular TYPE abap_boolean
                iv_archivo TYPE xstring
                iv_pend    TYPE string OPTIONAL.
ENDCLASS.



CLASS ZCL_ARBA_RET_ER_PROC IMPLEMENTATION.


  METHOD constructor.
    mo_parser       = COND #( WHEN io_parser IS BOUND THEN io_parser ELSE NEW zcl_arba_ret_er_parser( ) ).
    mo_determinador = COND #( WHEN io_determinador IS BOUND THEN io_determinador ELSE NEW zcl_arba_ret_er_determinador( ) ).
    mo_bp           = COND #( WHEN io_bp_updater IS BOUND THEN io_bp_updater ELSE NEW zcl_arba_ret_bp_updater( ) ).
  ENDMETHOD.


  METHOD procesar.
    CLEAR mt_pcf.

    IF xstrlen( is_ejec-archivo ) = 0.
      finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                 iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
      RETURN.
    ENDIF.

    DATA ls_kpi TYPE ty_kpi.
    TRY.
        DATA lt_rec    TYPE zcl_arba_ret_er_parser=>ty_record_tt.
        DATA lv_vacias TYPE i.
        DATA lv_encab  TYPE abap_boolean.
        mo_parser->parse_file( EXPORTING iv_archivo       = is_ejec-archivo
                               IMPORTING et_records       = lt_rec
                                         ev_lineas_vacias = lv_vacias
                                         ev_encabezado    = lv_encab ).

        ls_kpi-leidos = lines( lt_rec ).   " sin encabezado ni lineas vacias
        IF ls_kpi-leidos = 0.
          finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                     iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
          RETURN.
        ENDIF.

        " Precarga: CUIT -> proveedor, ampliados a la sociedad y retencion actual del tipo.
        mo_bp->preparar( iv_sociedad = is_ejec-sociedad iv_tipo_ret = is_ejec-tipo_retencion ).

        " Duplicados en el archivo: misma firma -> 1ra se procesa, resto OMI; distinta -> REV en todas.
        DATA lt_dup TYPE ty_cuit_dup_tt.
        FIELD-SYMBOLS <ls_d> TYPE ty_cuit_dup.
        LOOP AT lt_rec INTO DATA(ls_r) WHERE es_valido = abap_true.
          DATA(lv_firma) = firma( ls_r ).
          ASSIGN lt_dup[ cuit = ls_r-cuit ] TO <ls_d>.
          IF sy-subrc <> 0.
            INSERT VALUE #( cuit = ls_r-cuit firma = lv_firma ) INTO TABLE lt_dup.
          ELSEIF <ls_d>-firma <> lv_firma.
            <ls_d>-contradictorio = abap_true.
          ENDIF.
        ENDLOOP.

        DATA lt_log TYPE ty_log_tt.

        " Aviso informativo (no suma KPI, no entra en Errores): lineas ignoradas por vacias.
        IF lv_vacias > 0.
          APPEND VALUE #( estado  = 'OMI'
                          mensaje = |Aviso: { lv_vacias } lineas vacias o solo ';' ignoradas| &&
                                    |{ COND string( WHEN lv_encab = abap_true THEN ` (y el encabezado)` ) }| )
                 TO lt_log.
        ENDIF.

        LOOP AT lt_rec INTO DATA(ls_rec).
          procesar_registro( EXPORTING is_ejec   = is_ejec
                                       is_record = ls_rec
                             CHANGING  ct_dup    = lt_dup
                                       ct_log    = lt_log
                                       cs_kpi    = ls_kpi ).
        ENDLOOP.

        " Fuera de padron (molde zcl_arba_ret_sal_proc.clas.abap:178-197). Todo CUIT del archivo (validos,
        " B, REV por duplicado, fuera de filtro) cuenta como "en padron": nunca recibe el 03 ni un alta caso 4.
        IF is_ejec-actualizar_solo_padron = abap_false AND NOT line_exists( lt_rec[ es_valido = abap_true ] ).
          APPEND VALUE #( caso    = '3'
                          estado  = 'OMI'
                          mensaje = `Fuera de padron NO ejecutado: el archivo no tiene registros validos (';', 12 columnas). Se conservan los titulares actuales.` )
                 TO lt_log.
          ls_kpi-omitidos += 1.
        ELSEIF is_ejec-actualizar_solo_padron = abap_false.
          DATA lt_cuit_padron TYPE ty_cuit_set.
          LOOP AT lt_rec INTO DATA(ls_pr) WHERE cuit IS NOT INITIAL.
            INSERT ls_pr-cuit INTO TABLE lt_cuit_padron.
          ENDLOOP.
          procesar_fuera_padron( EXPORTING is_ejec        = is_ejec
                                           it_cuit_padron = lt_cuit_padron
                                 CHANGING  ct_log         = lt_log
                                           cs_kpi         = ls_kpi ).
        ENDIF.

        persistir_log( iv_uuid = is_ejec-ejecucion_uuid it_log = lt_log ).

      CATCH cx_root.
        ROLLBACK WORK.
        finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = ls_kpi
                   iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
        RETURN.
    ENDTRY.

    DATA(lv_estado) = COND ty_estado_ejec( WHEN ls_kpi-error_tecnico > 0 THEN 'OK_CON_ERRORES' ELSE 'OK' ).
    finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = lv_estado is_kpi = ls_kpi
               iv_simular = iv_simular iv_archivo = is_ejec-archivo iv_pend = resumen_pcf( ) ).
  ENDMETHOD.


  METHOD procesar_registro.
    " tipo_ret no se informa: ALTA, BAdI y export toman el tipo de la cabecera (como Salta).
    " tipo_contribuyente y marca_alta_baja viajan al .txt en layout ARBA (cols 6 y 7,
    " zcl_arba_ret_exporter.clas.abap:121-122), donde B = BAJA y A / P no existen. Se graban
    " neutralizados (P -> D, A/B -> N); el valor original del archivo queda en el mensaje (lv_arch).
    DATA(ls_row) = VALUE ty_log_row( nro_linea          = is_record-nro_linea
                                     cuit               = is_record-cuit
                                     tipo_contribuyente = COND #( WHEN is_record-tipo = zcl_arba_ret_er_parser=>c_tipo-prof
                                                                  THEN zcl_arba_ret_er_parser=>c_tipo-directo
                                                                  ELSE is_record-tipo )
                                     marca_alta_baja    = COND #( WHEN is_record-marca_alta = zcl_arba_ret_er_parser=>c_marca_baja
                                                                    OR is_record-marca_alta = 'A'
                                                                  THEN 'N'
                                                                  ELSE is_record-marca_alta )
                                     marca_cambio_alic  = is_record-marca_alic
                                     nro_grupo          = is_record-grupo_ret
                                     fecha_publicacion  = is_record-fecha_pub
                                     vigencia_desde     = is_record-vig_desde
                                     vigencia_hasta     = is_record-vig_hasta ).
    DATA(lv_arch) = |tipo { is_record-tipo } marca { is_record-marca_alta } alicuota { is_record-alic_txt }|.

    " 1) Validacion del archivo
    IF is_record-es_valido = abap_false.
      ls_row-estado  = is_record-estado.
      ls_row-mensaje = is_record-mensaje.
      APPEND ls_row TO ct_log.
      cs_kpi-rechazados += 1.
      RETURN.
    ENDIF.

    " 2) Duplicados en el archivo
    ASSIGN ct_dup[ cuit = is_record-cuit ] TO FIELD-SYMBOL(<ls_d>).
    IF sy-subrc = 0.
      IF <ls_d>-contradictorio = abap_true.
        ls_row-estado  = 'REV'.
        ls_row-mensaje = |Rechazado: CUIT repetido en el archivo con datos distintos (informado: { is_record-tipo }/{ is_record-marca_alta }/{ is_record-alic_txt })|.
        APPEND ls_row TO ct_log.
        cs_kpi-rechazados += 1.
        RETURN.
      ENDIF.
      IF <ls_d>-procesado = abap_true.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = 'Omitido: CUIT repetido en el archivo (mismos datos)'.
        APPEND ls_row TO ct_log.
        cs_kpi-omitidos += 1.
        RETURN.
      ENDIF.
      <ls_d>-procesado = abap_true.
    ENDIF.

    " 3) Matching por CUIT. NOE no se guarda (solo cuenta).
    DATA lt_sup TYPE zcl_arba_ret_bp_updater=>ty_supplier_tt.
    mo_bp->buscar_proveedor( EXPORTING iv_cuit = is_record-cuit IMPORTING et_suppliers = lt_sup ).
    IF lines( lt_sup ) = 0.
      cs_kpi-no_encontrados += 1.
      RETURN.
    ELSEIF lines( lt_sup ) > 1.
      ls_row-estado  = 'DUP'.
      ls_row-mensaje = 'Rechazado: CUIT presente en mas de un proveedor en SAP'.
      APPEND ls_row TO ct_log.
      cs_kpi-rechazados += 1.
      RETURN.
    ENDIF.
    DATA(lv_sup) = lt_sup[ 1 ].
    ls_row-proveedor = lv_sup.

    " 4) Retencion actual del tipo
    DATA(ls_act) = mo_bp->leer_retencion_actual(
      iv_supplier = lv_sup iv_sociedad = is_ejec-sociedad iv_tipo_ret = is_ejec-tipo_retencion ).
    ls_row-indicador_anterior  = ls_act-indicador.
    ls_row-sujeto_ret_anterior = COND #( WHEN ls_act-es_sujeto = abap_true THEN 'X' ELSE '' ).
    IF ls_act-existe = abap_true.
      ls_row-alicuota_anterior = alic( iv_tipo = is_ejec-tipo_retencion iv_ind = ls_act-indicador ).
    ENDIF.

    " 5) Filtro por rango de proveedor: un titular se conserva SIN CAMBIO (fila exportable).
    IF ( is_ejec-prov_desde IS NOT INITIAL AND lv_sup < is_ejec-prov_desde )
    OR ( is_ejec-prov_hasta IS NOT INITIAL AND lv_sup > is_ejec-prov_hasta ).
      IF ls_act-existe = abap_true.
        ls_row-caso             = '2'.
        ls_row-indicador_nuevo  = ls_act-indicador.
        ls_row-alicuota_nueva   = ls_row-alicuota_anterior.
        ls_row-sujeto_ret_nuevo = ls_row-sujeto_ret_anterior.
        ls_row-estado           = 'SCB'.
        ls_row-mensaje          = 'Fuera del filtro de proveedor: se conserva el indicador actual'.
        APPEND ls_row TO ct_log.
        cs_kpi-sin_cambios += 1.
      ELSE.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = 'Omitido: proveedor fuera del filtro'.
        APPEND ls_row TO ct_log.
        cs_kpi-omitidos += 1.
      ENDIF.
      RETURN.
    ENDIF.

    " 6) Marca B (decision funcional 27/10): no se determina indicador (el 6 % del archivo se ignora).
    "    Con registro -> destildar "sujeto a retencion" (caso 'X'); sin registro -> nada.
    "    caso 'X' deja la fila fuera de ALTA (caso 1/4/3) y del job de partidas (caso 1).
    IF is_record-marca_alta = zcl_arba_ret_er_parser=>c_marca_baja.
      IF ls_act-existe = abap_false.
        ls_row-estado  = 'OMI'.        " OMI y no SCB: el export levanta los SCB y no hay nada que conservar
        ls_row-mensaje = 'ER marca B sin registro de retencion: no se hace nada'.
        APPEND ls_row TO ct_log.
        cs_kpi-omitidos += 1.
        RETURN.
      ENDIF.
      ls_row-caso             = 'X'.
      ls_row-indicador_nuevo  = ls_act-indicador.           " el codigo NO cambia (la BAdI aplica el mismo)
      ls_row-alicuota_nueva   = ls_row-alicuota_anterior.   " alicuota del codigo actual: sin diferencia en la grilla
      ls_row-sujeto_ret_nuevo = ''.
      IF ls_act-es_sujeto = abap_true.
        ls_row-estado  = 'ACT'.
        ls_row-mensaje = |ER marca B: destildar "sujeto a retencion" (se aplica con el boton Aplicar Exenciones) ({ lv_arch })|.
        APPEND ls_row TO ct_log.
        cs_kpi-actualizados += 1.
      ELSE.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = |ER marca B: el sujeto a retencion ya esta destildado ({ lv_arch })|.
        APPEND ls_row TO ct_log.
        cs_kpi-sin_cambios += 1.
      ENDIF.
      RETURN.
    ENDIF.

    " 7) "Solo proveedores con datos de retencion existentes"
    IF is_ejec-solo_con_retencion = abap_true AND ls_act-existe = abap_false.
      ls_row-estado  = 'OMI'.
      ls_row-mensaje = 'Omitido: proveedor sin datos de retencion (filtro activo)'.
      APPEND ls_row TO ct_log.
      cs_kpi-omitidos += 1.
      RETURN.
    ENDIF.

    " 8) Determinacion por tipo de contribuyente + alicuota de retencion (ZTFI_RET_TUC)
    DATA lv_ind  TYPE zcl_arba_ret_determinador=>ty_wht_code.
    DATA lv_alic TYPE zcl_arba_ret_determinador=>ty_alicuota.
    DATA lv_est  TYPE c LENGTH 3.
    DATA lv_msg  TYPE string.
    mo_determinador->determinar( EXPORTING iv_tipo_ret     = is_ejec-tipo_retencion
                                           iv_tipo_contrib = is_record-tipo
                                           iv_alicuota     = is_record-alic_ret
                                 IMPORTING ev_indicador    = lv_ind
                                           ev_alicuota     = lv_alic
                                           ev_estado       = lv_est
                                           ev_mensaje      = lv_msg ).
    IF lv_est = 'PCF'.
      " Titular (caso 2): el export lo conserva a la alicuota de su codigo actual
      " (zbp_i_arba_ret_ejecucion.clas.locals_imp.abap:618-643); no titular (caso 1): fuera del export.
      ls_row-caso           = COND #( WHEN ls_act-existe = abap_true THEN '2' ELSE '1' ).
      ls_row-alicuota_nueva = is_record-alic_ret.   " informativa (redondeo a 2 dec); el detalle va en el mensaje
      ls_row-estado         = 'PCF'.
      ls_row-mensaje        = lv_msg.
      APPEND ls_row TO ct_log.
      cs_kpi-pendiente_config += 1.
      sumar_pcf( is_record ).
      RETURN.
    ENDIF.

    ls_row-indicador_nuevo  = lv_ind.
    ls_row-alicuota_nueva   = lv_alic.   " % del codigo (SPRO), no la del archivo: CM 3 -> 01 al 1,5
    ls_row-sujeto_ret_nuevo = 'X'.

    " 9) Alta (caso 1): ALTA por API crea el registro con sujeto tildado (zcl_arba_ret_alta.clas.abap:156).
    IF ls_act-existe = abap_false.
      ls_row-caso = '1'.
      IF mo_bp->esta_ampliado( lv_sup ) = abap_false.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = |Omitido: proveedor no ampliado a la sociedad { is_ejec-sociedad } (no se puede dar de alta la retencion)|.
        APPEND ls_row TO ct_log.
        cs_kpi-omitidos += 1.
        RETURN.
      ENDIF.
      ls_row-estado  = 'ACT'.
      ls_row-mensaje = |Archivo { lv_arch } -> indicador { lv_ind }: alta del tipo (la crea Ejecutar por API)|.
      APPEND ls_row TO ct_log.
      cs_kpi-actualizados += 1.
      RETURN.
    ENDIF.

    " 10) Titular (caso 2). A diferencia de Salta/generico, se compara codigo Y sujeto (EF: tildar si no esta).
    ls_row-caso = '2'.
    IF ls_act-indicador = lv_ind AND ls_act-es_sujeto = abap_true.
      ls_row-estado  = 'SCB'.
      ls_row-mensaje = |Sin cambios: el indicador ya coincide ({ lv_arch })|.
      APPEND ls_row TO ct_log.
      cs_kpi-sin_cambios += 1.
      RETURN.
    ENDIF.

    ls_row-estado = 'ACT'.
    IF ls_act-indicador = lv_ind.
      " mismo codigo, sujeto destildado: ACT (no SCB) para que lo tome ZCL_ARBA_RET_ER_SUJETO y Errores
      ls_row-mensaje = |ER: mantiene el codigo { lv_ind } ({ lv_arch }); tildar "sujeto a retencion" (se aplica con el boton Aplicar Exenciones)|.
    ELSEIF ls_act-es_sujeto = abap_false.
      ls_row-mensaje = |ER: cambio de indicador { ls_act-indicador } -> { lv_ind } ({ lv_arch }); tildar "sujeto a retencion" (boton Aplicar Exenciones)|.
    ELSE.
      ls_row-mensaje = |Archivo { lv_arch } -> indicador { lv_ind }|.
    ENDIF.
    APPEND ls_row TO ct_log.
    cs_kpi-actualizados += 1.
  ENDMETHOD.


  METHOD procesar_fuera_padron.
    DATA(lv_tipo) = CONV zcl_arba_ret_determinador=>ty_wht_type( is_ejec-tipo_retencion ).
    DATA(lv_ind)  = CONV zcl_arba_ret_determinador=>ty_wht_code( is_ejec-indicador_fuera_padron ).
    DATA lv_alic_fp TYPE zcl_arba_ret_determinador=>ty_alicuota.
    DATA lv_est     TYPE c LENGTH 3.
    DATA lv_motivo  TYPE string.

    " Parametro (la pantalla ya lo exige, impl:1267-1279; blindaje para corridas viejas).
    IF lv_ind IS INITIAL.
      lv_motivo = 'falta el "Indicador Fuera de Padron"'.
    ELSE.
      mo_determinador->alicuota( EXPORTING iv_tipo_ret = lv_tipo iv_indicador = lv_ind
                                 IMPORTING ev_alicuota = lv_alic_fp ev_estado = lv_est ).
      IF lv_est IS NOT INITIAL.
        lv_motivo = |indicador { lv_ind } no existe en el tipo { lv_tipo }|.
      ENDIF.
    ENDIF.

    " Region 05. Solo un ERROR de lectura bloquea (zcl_arba_ret_bp_updater.clas.abap:291-300).
    DATA lt_reg     TYPE zcl_arba_ret_bp_updater=>ty_sup_ret_tt.
    DATA lv_reg_err TYPE abap_boolean.
    DATA lv_reg_msg TYPE string.
    IF lv_motivo IS INITIAL.
      mo_bp->get_proveedores_por_region( EXPORTING iv_region  = zcl_arba_ret_er_param=>c_region
                                         IMPORTING et_sup     = lt_reg
                                                   ev_error   = lv_reg_err
                                                   ev_mensaje = lv_reg_msg ).
      IF lv_reg_err = abap_true.
        lv_motivo = |region { zcl_arba_ret_er_param=>c_region } no disponible: { lv_reg_msg }|.
      ENDIF.
    ENDIF.

    " Proveedores AR ampliados a la sociedad (zcl_arba_ret_sal_proc.clas.abap:435-446).
    DATA lt_soc_ar TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.
    IF lv_motivo IS INITIAL.
      SELECT DISTINCT c~supplier
        FROM i_suppliercompany AS c
        INNER JOIN i_supplier AS s ON s~supplier = c~supplier
        WHERE c~companycode = @is_ejec-sociedad
          AND s~country     = 'AR'
        INTO TABLE @lt_soc_ar.
      IF lt_soc_ar IS INITIAL.
        lv_motivo = |sin proveedores AR ampliados legibles en la sociedad { is_ejec-sociedad }|.
      ENDIF.
    ENDIF.

    DATA(lv_ejecutar) = xsdbool( lv_motivo IS INITIAL ).
    IF lv_ejecutar = abap_false.
      " Texto alineado con el filtro de Errores ('Fuera de padron%NO ejecutado%', zi_arba_ret_err_r.ddls:41).
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = |Fuera de padron NO ejecutado: { lv_motivo }. Se conservan los titulares actuales.| )
             TO ct_log.
      cs_kpi-omitidos += 1.
    ELSEIF lt_reg IS INITIAL.
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = |Aviso: region { zcl_arba_ret_er_param=>c_region } sin proveedores con CUIT; los titulares fuera de padron se conservan| )
             TO ct_log.
    ENDIF.

    DATA lt_reg05 TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.
    LOOP AT lt_reg INTO DATA(ls_rg).
      IF line_exists( lt_soc_ar[ table_line = ls_rg-supplier ] ).
        INSERT ls_rg-supplier INTO TABLE lt_reg05.
      ENDIF.
    ENDLOOP.

    " (A) Titulares del tipo que NO vinieron en el archivo: siempre una fila exportable (ACT/SCB).
    DATA ls_row TYPE ty_log_row.
    LOOP AT mo_bp->get_proveedores_con_retencion( ) INTO DATA(ls_t).
      IF ls_t-cuit IS NOT INITIAL AND line_exists( it_cuit_padron[ table_line = ls_t-cuit ] ).
        CONTINUE.
      ENDIF.

      CLEAR ls_row.
      ls_row-cuit                = ls_t-cuit.
      ls_row-proveedor           = ls_t-supplier.
      ls_row-caso                = '3'.
      ls_row-indicador_anterior  = ls_t-indicador.
      ls_row-sujeto_ret_anterior = COND #( WHEN ls_t-es_sujeto = abap_true THEN 'X' ELSE '' ).
      ls_row-alicuota_anterior   = alic( iv_tipo = lv_tipo iv_ind = ls_t-indicador ).
      ls_row-indicador_nuevo     = ls_t-indicador.
      ls_row-alicuota_nueva      = ls_row-alicuota_anterior.
      ls_row-sujeto_ret_nuevo    = ls_row-sujeto_ret_anterior.

      IF ls_t-cuit IS INITIAL.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = 'Fuera de padron NO ejecutado para el proveedor: sin CUIT (AR1A), no se puede exportar'.
        APPEND ls_row TO ct_log.
        cs_kpi-omitidos += 1.
        CONTINUE.
      ENDIF.

      IF ( is_ejec-prov_desde IS NOT INITIAL AND ls_t-supplier < is_ejec-prov_desde )
      OR ( is_ejec-prov_hasta IS NOT INITIAL AND ls_t-supplier > is_ejec-prov_hasta ).
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = 'Fuera del filtro de proveedor: se conserva el indicador actual'.
        APPEND ls_row TO ct_log.
        cs_kpi-sin_cambios += 1.
        CONTINUE.
      ENDIF.

      IF lv_ejecutar = abap_false.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = 'Fuera de padron no ejecutado: se conserva el indicador actual'.
        APPEND ls_row TO ct_log.
        cs_kpi-sin_cambios += 1.
        CONTINUE.
      ENDIF.

      " Regla 16/10 (todos los padrones): region vacia/distinta, no AR o no ampliado -> keeper sin cambio.
      IF NOT line_exists( lt_reg05[ table_line = ls_t-supplier ] ).
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = |Fuera de padron: region vacia o distinta de { zcl_arba_ret_er_param=>c_region }: se conserva el indicador { ls_t-indicador }|.
        APPEND ls_row TO ct_log.
        cs_kpi-sin_cambios += 1.
        CONTINUE.
      ENDIF.

      " R6 (pendiente funcional): si Marcelo decide tildar tambien en fuera de padron, esta condicion pasa a
      " "ls_t-indicador = lv_ind AND ls_t-es_sujeto = abap_true"; el resto (mismo 03, destildado) va a ACT
      " con sujeto_ret_nuevo = 'X' y mensaje "ER: mantiene el codigo 03 ...", y ER_SUJETO suma '3' a su IN.
      IF ls_t-indicador = lv_ind.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = |Fuera de padron (region { zcl_arba_ret_er_param=>c_region }): ya tiene el indicador { lv_ind } (se conserva)|.
        APPEND ls_row TO ct_log.
        cs_kpi-sin_cambios += 1.
        CONTINUE.
      ENDIF.

      " Cambio de codigo (caso 3 con indicador anterior: lo aplica la app estandar + BAdI, no ALTA).
      ls_row-indicador_nuevo  = lv_ind.
      ls_row-alicuota_nueva   = lv_alic_fp.
      ls_row-sujeto_ret_nuevo = 'X'.   " informativo: ER_SUJETO no toma caso 3 (pendiente funcional)
      ls_row-estado           = 'ACT'.
      ls_row-mensaje          = |Fuera de padron (region { zcl_arba_ret_er_param=>c_region }): Indicador Fuera de Padron { lv_ind }|.
      APPEND ls_row TO ct_log.
      cs_kpi-actualizados += 1.
    ENDLOOP.

    " (B) Alta fuera de padron: region 05, AR, ampliado, sin el tipo, CUIT fuera del archivo (caso 4).
    IF lv_ejecutar = abap_false OR is_ejec-solo_con_retencion = abap_true.
      RETURN.
    ENDIF.

    LOOP AT lt_reg INTO DATA(ls_r).
      IF NOT line_exists( lt_reg05[ table_line = ls_r-supplier ] ).
        CONTINUE.
      ENDIF.
      IF mo_bp->leer_retencion_actual( iv_supplier = ls_r-supplier iv_sociedad = is_ejec-sociedad
                                       iv_tipo_ret = lv_tipo )-existe = abap_true.
        CONTINUE.
      ENDIF.
      IF line_exists( it_cuit_padron[ table_line = ls_r-cuit ] ).
        CONTINUE.   " en el archivo (incluye marca B sin registro: no recibe alta)
      ENDIF.
      IF ( is_ejec-prov_desde IS NOT INITIAL AND ls_r-supplier < is_ejec-prov_desde )
      OR ( is_ejec-prov_hasta IS NOT INITIAL AND ls_r-supplier > is_ejec-prov_hasta ).
        CONTINUE.
      ENDIF.

      CLEAR ls_row.
      ls_row-cuit             = ls_r-cuit.
      ls_row-proveedor        = ls_r-supplier.
      ls_row-caso             = '4'.
      ls_row-indicador_nuevo  = lv_ind.
      ls_row-alicuota_nueva   = lv_alic_fp.
      ls_row-sujeto_ret_nuevo = 'X'.
      ls_row-estado           = 'ACT'.
      ls_row-mensaje          = |Fuera de padron (region { zcl_arba_ret_er_param=>c_region }): alta del tipo con el Indicador Fuera de Padron { lv_ind } (la crea Ejecutar por API)|.
      APPEND ls_row TO ct_log.
      cs_kpi-actualizados += 1.
    ENDLOOP.
  ENDMETHOD.


  METHOD alic.
    mo_determinador->alicuota( EXPORTING iv_tipo_ret = iv_tipo iv_indicador = iv_ind
                               IMPORTING ev_alicuota = rv_alic ).
  ENDMETHOD.


  METHOD firma.
    rv_fir = |{ is_record-tipo }/{ is_record-marca_alta }/{ is_record-alic_ret }|.
  ENDMETHOD.


  METHOD sumar_pcf.
    DATA(lv_clave) = |{ is_record-tipo } { is_record-alic_txt }|.
    ASSIGN mt_pcf[ clave = lv_clave ] TO FIELD-SYMBOL(<ls_pcf>).
    IF sy-subrc = 0.
      <ls_pcf>-cnt += 1.
    ELSE.
      INSERT VALUE #( clave = lv_clave cnt = 1 ) INTO TABLE mt_pcf.
    ENDIF.
  ENDMETHOD.


  METHOD resumen_pcf.
    " "Pendiente Configuracion" por tipo + alicuota del archivo, p. ej. "C 0,25 (859); D 0,5 (2059)".
    LOOP AT mt_pcf INTO DATA(ls).
      rv_txt = |{ rv_txt }{ COND string( WHEN rv_txt IS NOT INITIAL THEN `; ` ) }{ ls-clave } ({ ls-cnt })|.
    ENDLOOP.
  ENDMETHOD.


  METHOD cortar.
    rv_txt = COND #( WHEN strlen( iv_txt ) > 255 THEN substring( val = iv_txt off = 0 len = 255 ) ELSE iv_txt ).
  ENDMETHOD.


  METHOD persistir_log.
    " Copia de zcl_arba_ret_sal_proc.clas.abap:594-628 + campos informativos (como zcl_arba_ret_job.clas.abap:474-498).
    IF it_log IS INITIAL.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD DATA(lv_now).
    DATA lt_db TYPE STANDARD TABLE OF zarba_ret_log WITH EMPTY KEY.
    LOOP AT it_log INTO DATA(ls_log) WHERE estado <> 'NOE'.
      APPEND VALUE #(
        ejecucion_uuid      = iv_uuid
        log_uuid            = cl_system_uuid=>create_uuid_x16_static( )
        nro_linea           = ls_log-nro_linea
        cuit                = ls_log-cuit
        proveedor           = ls_log-proveedor
        caso                = ls_log-caso
        indicador_anterior  = ls_log-indicador_anterior
        indicador_nuevo     = ls_log-indicador_nuevo
        alicuota_anterior   = ls_log-alicuota_anterior
        alicuota_nueva      = ls_log-alicuota_nueva
        sujeto_ret_anterior = ls_log-sujeto_ret_anterior
        sujeto_ret_nuevo    = ls_log-sujeto_ret_nuevo
        estado              = ls_log-estado
        mensaje             = cortar( ls_log-mensaje )
        tipo_contribuyente  = ls_log-tipo_contribuyente
        marca_alta_baja     = ls_log-marca_alta_baja
        marca_cambio_alic   = ls_log-marca_cambio_alic
        nro_grupo           = ls_log-nro_grupo
        fecha_publicacion   = ls_log-fecha_publicacion
        vigencia_desde      = ls_log-vigencia_desde
        vigencia_hasta      = ls_log-vigencia_hasta
        last_changed_at     = lv_now ) TO lt_db.
      IF lines( lt_db ) >= c_lote.
        INSERT zarba_ret_log FROM TABLE @lt_db.
        CLEAR lt_db.
      ENDIF.
    ENDLOOP.

    IF lt_db IS NOT INITIAL.
      INSERT zarba_ret_log FROM TABLE @lt_db.
    ENDIF.
    COMMIT WORK.
  ENDMETHOD.


  METHOD finalizar.
    " Copia de zcl_arba_ret_sal_proc.clas.abap:631-657.
    GET TIME STAMP FIELD DATA(lv_now).
    DATA(lv_archivo) = COND xstring( WHEN iv_simular = abap_true THEN iv_archivo ELSE VALUE #( ) ).
    DATA(lv_size)    = xstrlen( iv_archivo ).
    DATA(lv_pend)    = CONV zarba_ret_ejec-alicuotas_pend( cortar( iv_pend ) ).

    UPDATE zarba_ret_ejec
      SET estado_ejecucion       = @iv_estado,
          modo_simulacion        = @iv_simular,
          archivo                = @lv_archivo,
          tamanio_archivo        = @lv_size,
          tipo_ret_fuera         = @space,
          alicuotas_pend         = @lv_pend,
          total_leidos           = @is_kpi-leidos,
          total_actualizados     = @is_kpi-actualizados,
          total_sin_cambios      = @is_kpi-sin_cambios,
          total_no_encontrados   = @is_kpi-no_encontrados,
          total_rechazados       = @is_kpi-rechazados,
          total_error_tecnico    = @is_kpi-error_tecnico,
          total_pendiente_config = @is_kpi-pendiente_config,
          total_omitidos         = @is_kpi-omitidos,
          last_changed_at        = @lv_now
      WHERE ejecucion_uuid = @iv_uuid.
    COMMIT WORK.
  ENDMETHOD.
ENDCLASS.
