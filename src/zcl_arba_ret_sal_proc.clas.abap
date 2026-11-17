"! Motor del padron IIBB Salta (DGR). Autocontenido (tipos propios; no depende de PROC_APP ni de clases TUC).
"! Lo invoca el Application Job para provincia 'SAL'. Persiste el log con los estados/casos del flujo
"! generico, asi ALTA por API, job de partidas, export, BAdI y Errores funcionan sin cambios.
"!   JU/CM/EX -> indicador por customizing ZARBA_RET_SALC ; EXC -> excluido: no se procesa, se conserva el
"!   actual y cuenta como "en padron" (nunca cae en fuera de padron).
"! Fuera de padron (sin "Actualizar Solo Padron"):
"!   (A) titulares del tipo fuera del archivo: region 09 (y proveedor AR ampliado) -> Indicador Fuera de
"!       Padron Salta ; resto (otra region, vacia o extranjero) -> Indicador Fuera de Padron No Salta.
"!   (B) no titulares region 09, AR y ampliados -> alta (caso 4) con el indicador Salta. Otra region: nada.
"!   Lectura de region con error -> no se ejecuta fuera de padron (se conservan todos los titulares).
CLASS zcl_arba_ret_sal_proc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
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
      IMPORTING io_parser       TYPE REF TO zcl_arba_ret_sal_parser       OPTIONAL
                io_determinador TYPE REF TO zcl_arba_ret_sal_determinador OPTIONAL
                io_bp_updater   TYPE REF TO zcl_arba_ret_bp_updater       OPTIONAL.

    "! Punto de entrada desde el job: procesa la ejecucion completa.
    METHODS procesar
      IMPORTING is_ejec    TYPE zarba_ret_ejec
                iv_simular TYPE abap_boolean.

  PRIVATE SECTION.
    "! Region (domicilio) de Salta en el pais AR (T005S: 09 = Salta).
    CONSTANTS c_region_sal TYPE c LENGTH 3 VALUE '09'.
    CONSTANTS c_lote       TYPE i VALUE 1000.

    TYPES: BEGIN OF ty_cuit_dup,
             cuit           TYPE ty_cuit,
             condicion      TYPE zcl_arba_ret_sal_parser=>ty_condicion,
             contradictorio TYPE abap_boolean,
             procesado      TYPE abap_boolean,
           END OF ty_cuit_dup.
    TYPES ty_cuit_dup_tt TYPE HASHED TABLE OF ty_cuit_dup WITH UNIQUE KEY cuit.

    TYPES: BEGIN OF ty_pcf,
             condicion TYPE zcl_arba_ret_sal_parser=>ty_condicion,
             cnt       TYPE i,
           END OF ty_pcf.

    DATA mo_parser       TYPE REF TO zcl_arba_ret_sal_parser.
    DATA mo_determinador TYPE REF TO zcl_arba_ret_sal_determinador.
    DATA mo_bp           TYPE REF TO zcl_arba_ret_bp_updater.
    DATA mt_pcf          TYPE HASHED TABLE OF ty_pcf WITH UNIQUE KEY condicion.

    METHODS procesar_registro
      IMPORTING is_ejec   TYPE zarba_ret_ejec
                is_record TYPE zcl_arba_ret_sal_parser=>ty_record
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



CLASS ZCL_ARBA_RET_SAL_PROC IMPLEMENTATION.


  METHOD constructor.
    mo_parser       = COND #( WHEN io_parser IS BOUND THEN io_parser ELSE NEW zcl_arba_ret_sal_parser( ) ).
    mo_determinador = COND #( WHEN io_determinador IS BOUND THEN io_determinador ELSE NEW zcl_arba_ret_sal_determinador( ) ).
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
        DATA lt_rec TYPE zcl_arba_ret_sal_parser=>ty_record_tt.
        mo_parser->parse_file( EXPORTING iv_content = mo_parser->decodificar( is_ejec-archivo )
                               IMPORTING et_records = lt_rec ).

        ls_kpi-leidos = lines( lt_rec ).
        IF ls_kpi-leidos = 0.
          finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                     iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
          RETURN.
        ENDIF.

        " Precarga: CUIT -> proveedor, ampliados a la sociedad y retencion actual del tipo.
        mo_bp->preparar( iv_sociedad = is_ejec-sociedad iv_tipo_ret = is_ejec-tipo_retencion ).

        " Duplicados en el archivo: misma condicion -> 1ra se procesa, resto OMI; distinta -> REV en todas.
        DATA lt_dup TYPE ty_cuit_dup_tt.
        FIELD-SYMBOLS <ls_d> TYPE ty_cuit_dup.
        LOOP AT lt_rec INTO DATA(ls_r) WHERE es_valido = abap_true.
          ASSIGN lt_dup[ cuit = ls_r-cuit ] TO <ls_d>.
          IF sy-subrc <> 0.
            INSERT VALUE #( cuit = ls_r-cuit condicion = ls_r-condicion ) INTO TABLE lt_dup.
          ELSEIF <ls_d>-condicion <> ls_r-condicion.
            <ls_d>-contradictorio = abap_true.
          ENDIF.
        ENDLOOP.

        DATA lt_log TYPE ty_log_tt.
        LOOP AT lt_rec INTO DATA(ls_rec).
          procesar_registro( EXPORTING is_ejec   = is_ejec
                                       is_record = ls_rec
                             CHANGING  ct_dup    = lt_dup
                                       ct_log    = lt_log
                                       cs_kpi    = ls_kpi ).
        ENDLOOP.

        " Fuera de padron. Todo CUIT del archivo (incluye EXC, REV por duplicado y fuera de filtro) cuenta
        " como "en padron" y nunca recibe un indicador fuera de padron.
        " Sin ningun registro valido (archivo con otro separador / formato) NO se ejecuta fuera de padron:
        " todos los titulares quedarian como "fuera del archivo" y recibirian un indicador (y altas region 09).
        IF is_ejec-actualizar_solo_padron = abap_false AND NOT line_exists( lt_rec[ es_valido = abap_true ] ).
          APPEND VALUE #( caso    = '3'
                          estado  = 'OMI'
                          mensaje = `Fuera de padron NO ejecutado: el archivo no tiene registros validos (TAB, CUIT, CONDICION). Se conservan los titulares actuales.` )
                 TO lt_log.
          ADD 1 TO ls_kpi-omitidos.
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
        " Descarta lo insertado sin commit y nunca deja la ejecucion EN_PROCESO ni "OK" con log parcial.
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
    " tipo_ret no se informa: ALTA, BAdI y export toman el tipo de la cabecera.
    DATA(ls_row) = VALUE ty_log_row( nro_linea = is_record-nro_linea cuit = is_record-cuit ).

    " 1) Validacion del archivo
    IF is_record-es_valido = abap_false.
      ls_row-estado  = is_record-estado.
      ls_row-mensaje = is_record-mensaje.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-rechazados.
      RETURN.
    ENDIF.

    " 2) Duplicados en el archivo
    ASSIGN ct_dup[ cuit = is_record-cuit ] TO FIELD-SYMBOL(<ls_d>).
    IF sy-subrc = 0.
      IF <ls_d>-contradictorio = abap_true.
        ls_row-estado  = 'REV'.
        ls_row-mensaje = |Rechazado: CUIT repetido en el archivo con condiciones distintas (informado: { is_record-condicion })|.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-rechazados.
        RETURN.
      ENDIF.
      IF <ls_d>-procesado = abap_true.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = 'Omitido: CUIT repetido en el archivo (misma condicion)'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-omitidos.
        RETURN.
      ENDIF.
      <ls_d>-procesado = abap_true.
    ENDIF.

    " 3) Matching por CUIT. NOE no se guarda en memoria (no se graba; solo cuenta).
    DATA lt_sup TYPE zcl_arba_ret_bp_updater=>ty_supplier_tt.
    mo_bp->buscar_proveedor( EXPORTING iv_cuit = is_record-cuit IMPORTING et_suppliers = lt_sup ).
    IF lines( lt_sup ) = 0.
      ADD 1 TO cs_kpi-no_encontrados.
      RETURN.
    ELSEIF lines( lt_sup ) > 1.
      ls_row-estado  = 'DUP'.
      ls_row-mensaje = 'Rechazado: CUIT presente en mas de un proveedor en SAP'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-rechazados.
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
        ADD 1 TO cs_kpi-sin_cambios.
      ELSE.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = 'Omitido: proveedor fuera del filtro'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-omitidos.
      ENDIF.
      RETURN.
    ENDIF.

    " 6) EXC: excluido, no se procesa; esta en padron.
    IF is_record-condicion = zcl_arba_ret_sal_parser=>c_cond-exc.
      IF ls_act-existe = abap_true.
        ls_row-caso             = '2'.
        ls_row-indicador_nuevo  = ls_act-indicador.
        ls_row-alicuota_nueva   = ls_row-alicuota_anterior.
        ls_row-sujeto_ret_nuevo = ls_row-sujeto_ret_anterior.
        ls_row-estado           = 'SCB'.
        ls_row-mensaje          = 'Excluido (EXC): no se procesa, se conserva el indicador actual'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
      ELSE.
        ls_row-caso    = '1'.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = 'Excluido (EXC): no se procesa (el proveedor no tiene el tipo)'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-omitidos.
      ENDIF.
      RETURN.
    ENDIF.

    " 7) "Solo proveedores con datos de retencion existentes"
    IF is_ejec-solo_con_retencion = abap_true AND ls_act-existe = abap_false.
      ls_row-estado  = 'OMI'.
      ls_row-mensaje = 'Omitido: proveedor sin datos de retencion (filtro activo)'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
      RETURN.
    ENDIF.

    " 8) Determinacion por condicion
    DATA lv_ind  TYPE zcl_arba_ret_determinador=>ty_wht_code.
    DATA lv_alic TYPE zcl_arba_ret_determinador=>ty_alicuota.
    DATA lv_est  TYPE c LENGTH 3.
    DATA lv_msg  TYPE string.
    mo_determinador->determinar( EXPORTING iv_tipo_ret  = is_ejec-tipo_retencion
                                           iv_condicion = is_record-condicion
                                 IMPORTING ev_indicador = lv_ind
                                           ev_alicuota  = lv_alic
                                           ev_estado    = lv_est
                                           ev_mensaje   = lv_msg ).
    IF lv_est = 'PCF'.
      " Titular (caso 2): el export lo conserva a la alicuota de su codigo actual; no titular: fuera del export.
      ls_row-caso    = COND #( WHEN ls_act-existe = abap_true THEN '2' ELSE '1' ).
      ls_row-estado  = 'PCF'.
      ls_row-mensaje = lv_msg.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-pendiente_config.
      ASSIGN mt_pcf[ condicion = is_record-condicion ] TO FIELD-SYMBOL(<ls_pcf>).
      IF sy-subrc = 0.
        ADD 1 TO <ls_pcf>-cnt.
      ELSE.
        INSERT VALUE #( condicion = is_record-condicion cnt = 1 ) INTO TABLE mt_pcf.
      ENDIF.
      RETURN.
    ENDIF.

    ls_row-indicador_nuevo  = lv_ind.
    ls_row-alicuota_nueva   = lv_alic.
    ls_row-sujeto_ret_nuevo = 'X'.

    " 9) Caso y estado
    IF ls_act-existe = abap_false.
      ls_row-caso = '1'.
      " Sin datos en la sociedad la API rechaza el alta: se informa ya en la simulacion (texto = Errores).
      IF mo_bp->esta_ampliado( lv_sup ) = abap_false.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = |Omitido: proveedor no ampliado a la sociedad { is_ejec-sociedad } (no se puede dar de alta la retencion)|.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-omitidos.
        RETURN.
      ENDIF.
      ls_row-estado  = 'ACT'.
      ls_row-mensaje = |Condicion { is_record-condicion } -> indicador { lv_ind }: alta del tipo (la crea Ejecutar por API)|.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
      RETURN.
    ENDIF.

    ls_row-caso = '2'.
    " Solo se compara el codigo (la app estandar + BAdI solo cambian el codigo), igual que el generico.
    IF ls_act-indicador = lv_ind.
      ls_row-sujeto_ret_nuevo = ls_row-sujeto_ret_anterior.
      ls_row-estado  = 'SCB'.
      ls_row-mensaje = `Sin cambios: el indicador ya coincide`.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-sin_cambios.
      RETURN.
    ENDIF.

    ls_row-estado  = 'ACT'.
    ls_row-mensaje = |Condicion { is_record-condicion } -> indicador { lv_ind }|.
    APPEND ls_row TO ct_log.
    ADD 1 TO cs_kpi-actualizados.
  ENDMETHOD.


  METHOD procesar_fuera_padron.
    DATA(lv_tipo)       = CONV zcl_arba_ret_determinador=>ty_wht_type( is_ejec-tipo_retencion ).
    DATA(lv_ind_sal)    = CONV zcl_arba_ret_determinador=>ty_wht_code( is_ejec-indicador_fuera_padron ).
    DATA(lv_ind_no_sal) = CONV zcl_arba_ret_determinador=>ty_wht_code( is_ejec-ind_fuera_no_sal ).
    DATA lv_alic_sal    TYPE zcl_arba_ret_determinador=>ty_alicuota.
    DATA lv_alic_no_sal TYPE zcl_arba_ret_determinador=>ty_alicuota.
    DATA lv_est         TYPE c LENGTH 3.
    DATA lv_motivo      TYPE string.

    " Parametros (la pantalla ya los exige; blindaje para corridas viejas).
    IF lv_ind_sal IS INITIAL OR lv_ind_no_sal IS INITIAL.
      lv_motivo = 'faltan "Indicador Fuera de Padron" y/o "Indicador Fuera de Padron No Salta"'.
    ELSE.
      mo_determinador->alicuota( EXPORTING iv_tipo_ret = lv_tipo iv_indicador = lv_ind_sal
                                 IMPORTING ev_alicuota = lv_alic_sal ev_estado = lv_est ).
      IF lv_est IS NOT INITIAL.
        lv_motivo = |indicador { lv_ind_sal } no existe en el tipo { lv_tipo }|.
      ELSE.
        mo_determinador->alicuota( EXPORTING iv_tipo_ret = lv_tipo iv_indicador = lv_ind_no_sal
                                   IMPORTING ev_alicuota = lv_alic_no_sal ev_estado = lv_est ).
        IF lv_est IS NOT INITIAL.
          lv_motivo = |indicador { lv_ind_no_sal } no existe en el tipo { lv_tipo }|.
        ENDIF.
      ENDIF.
    ENDIF.

    " Region 09. Solo un ERROR de lectura bloquea (ZI_ARBA_RET_SUP_REGION no tiene DCL: no hay filtrado
    " silencioso). Vacia = no hay proveedores de Salta: (A) sigue (todos NO Salta) y se deja un aviso.
    DATA lt_reg     TYPE zcl_arba_ret_bp_updater=>ty_sup_ret_tt.
    DATA lv_reg_err TYPE abap_boolean.
    DATA lv_reg_msg TYPE string.
    IF lv_motivo IS INITIAL.
      mo_bp->get_proveedores_por_region( EXPORTING iv_region  = c_region_sal
                                         IMPORTING et_sup     = lt_reg
                                                   ev_error   = lv_reg_err
                                                   ev_mensaje = lv_reg_msg ).
      IF lv_reg_err = abap_true.
        lv_motivo = |region { c_region_sal } no disponible: { lv_reg_msg }|.
      ENDIF.
    ENDIF.

    " Proveedores AR ampliados a la sociedad (una sola lectura): una region '09' solo es Salta si el
    " proveedor es AR, y es el universo de altas de (B). Lectura vacia = problema de lectura (hay titulares):
    " no se ejecuta fuera de padron (sino todos irian a No Salta).
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
      " Texto alineado con el filtro de Errores ('Fuera de padron%NO ejecutado%').
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = |Fuera de padron NO ejecutado: { lv_motivo }. Se conservan los titulares actuales.| )
             TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
    ELSEIF lt_reg IS INITIAL.
      " Aviso (no entra en Errores): sin proveedores en Salta todos los titulares fuera de padron van a No Salta.
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = |Aviso: region { c_region_sal } sin proveedores con CUIT; los titulares fuera de padron reciben el Indicador Fuera de Padron No Salta| )
             TO ct_log.
    ENDIF.

    DATA lt_reg09 TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.
    LOOP AT lt_reg INTO DATA(ls_rg).
      IF line_exists( lt_soc_ar[ table_line = ls_rg-supplier ] ).
        INSERT ls_rg-supplier INTO TABLE lt_reg09.
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
        ADD 1 TO cs_kpi-omitidos.
        CONTINUE.
      ENDIF.

      IF ( is_ejec-prov_desde IS NOT INITIAL AND ls_t-supplier < is_ejec-prov_desde )
      OR ( is_ejec-prov_hasta IS NOT INITIAL AND ls_t-supplier > is_ejec-prov_hasta ).
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = 'Fuera del filtro de proveedor: se conserva el indicador actual'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      IF lv_ejecutar = abap_false.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = 'Fuera de padron no ejecutado: se conserva el indicador actual'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      DATA(lv_en_09) = xsdbool( line_exists( lt_reg09[ table_line = ls_t-supplier ] ) ).
      DATA(lv_dest)  = COND zcl_arba_ret_determinador=>ty_wht_code( WHEN lv_en_09 = abap_true THEN lv_ind_sal ELSE lv_ind_no_sal ).
      DATA(lv_alic)  = COND zcl_arba_ret_determinador=>ty_alicuota( WHEN lv_en_09 = abap_true THEN lv_alic_sal ELSE lv_alic_no_sal ).
      DATA(lv_txt)   = COND string( WHEN lv_en_09 = abap_true THEN |region { c_region_sal }| ELSE |region distinta de { c_region_sal }| ).

      IF ls_t-indicador = lv_dest.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = |Fuera de padron ({ lv_txt }): ya tiene el indicador { lv_dest } (se conserva)|.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      " Cambio de codigo (caso 3 con indicador anterior: lo aplica la app estandar + BAdI, no ALTA).
      ls_row-indicador_nuevo  = lv_dest.
      ls_row-alicuota_nueva   = lv_alic.
      ls_row-sujeto_ret_nuevo = 'X'.
      ls_row-estado           = 'ACT'.
      ls_row-mensaje          = COND #( WHEN lv_en_09 = abap_true
                                        THEN |Fuera de padron ({ lv_txt }): Indicador Fuera de Padron Salta { lv_dest }|
                                        ELSE |Fuera de padron ({ lv_txt }): Indicador Fuera de Padron No Salta { lv_dest }| ).
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
    ENDLOOP.

    " (B) Alta fuera de padron: region 09, AR, ampliado, sin el tipo (caso 4). Otra region: nada.
    IF lv_ejecutar = abap_false OR is_ejec-solo_con_retencion = abap_true.
      RETURN.
    ENDIF.

    LOOP AT lt_reg INTO DATA(ls_r).
      IF NOT line_exists( lt_reg09[ table_line = ls_r-supplier ] ).
        CONTINUE.   " no AR o no ampliado a la sociedad
      ENDIF.
      IF mo_bp->leer_retencion_actual( iv_supplier = ls_r-supplier iv_sociedad = is_ejec-sociedad
                                       iv_tipo_ret = lv_tipo )-existe = abap_true.
        CONTINUE.   " titular: ya tratado en (A)
      ENDIF.
      IF line_exists( it_cuit_padron[ table_line = ls_r-cuit ] ).
        CONTINUE.
      ENDIF.
      IF ( is_ejec-prov_desde IS NOT INITIAL AND ls_r-supplier < is_ejec-prov_desde )
      OR ( is_ejec-prov_hasta IS NOT INITIAL AND ls_r-supplier > is_ejec-prov_hasta ).
        CONTINUE.
      ENDIF.

      CLEAR ls_row.
      ls_row-cuit             = ls_r-cuit.
      ls_row-proveedor        = ls_r-supplier.
      ls_row-caso             = '4'.
      ls_row-indicador_nuevo  = lv_ind_sal.
      ls_row-alicuota_nueva   = lv_alic_sal.
      ls_row-sujeto_ret_nuevo = 'X'.
      ls_row-estado           = 'ACT'.
      ls_row-mensaje          = |Fuera de padron (region { c_region_sal }): alta del tipo con el Indicador Fuera de Padron Salta { lv_ind_sal } (la crea Ejecutar por API)|.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
    ENDLOOP.
  ENDMETHOD.


  METHOD alic.
    mo_determinador->alicuota( EXPORTING iv_tipo_ret = iv_tipo iv_indicador = iv_ind
                               IMPORTING ev_alicuota = rv_alic ).
  ENDMETHOD.


  METHOD resumen_pcf.
    " "Pendiente Configuracion" por condicion, p. ej. "EX sin indicador (12)".
    LOOP AT mt_pcf INTO DATA(ls).
      rv_txt = |{ rv_txt }{ COND string( WHEN rv_txt IS NOT INITIAL THEN `; ` ) }{ ls-condicion } sin indicador ({ ls-cnt })|.
    ENDLOOP.
  ENDMETHOD.


  METHOD cortar.
    rv_txt = COND #( WHEN strlen( iv_txt ) > 255 THEN substring( val = iv_txt off = 0 len = 255 ) ELSE iv_txt ).
  ENDMETHOD.


  METHOD persistir_log.
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
    GET TIME STAMP FIELD DATA(lv_now).
    DATA(lv_archivo) = COND xstring( WHEN iv_simular = abap_true THEN iv_archivo ELSE VALUE #( ) ).
    DATA(lv_size)    = xstrlen( iv_archivo ).
    DATA(lv_pend)    = CONV zarba_ret_ejec-alicuotas_pend( cortar( iv_pend ) ).

    " tipo_ret_fuera se limpia: un valor residual (p. ej. de TUC) haria que la BAdI tome esta corrida
    " como la ultima de ese otro tipo.
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
