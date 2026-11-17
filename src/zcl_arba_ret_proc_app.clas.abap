CLASS zcl_arba_ret_proc_app DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Fila de log de auditoria por registro procesado (EF seccion 11).
    TYPES: BEGIN OF ty_log_row,
             nro_linea           TYPE i,
             cuit                TYPE c LENGTH 11,
             proveedor           TYPE c LENGTH 10,
             caso                TYPE c LENGTH 1,
             " Tipo de retencion de la fila (24 padron / TN fuera de padron en Tucuman). Vacio en el
             " resto: se interpreta como el tipo de la ejecucion.
             tipo_ret            TYPE c LENGTH 2,
             indicador_anterior  TYPE c LENGTH 2,
             indicador_nuevo     TYPE c LENGTH 2,
             alicuota_anterior   TYPE p LENGTH 5 DECIMALS 2,
             alicuota_nueva      TYPE p LENGTH 5 DECIMALS 2,
             sujeto_ret_anterior TYPE c LENGTH 1,
             sujeto_ret_nuevo    TYPE c LENGTH 1,
             estado              TYPE c LENGTH 3,
             mensaje             TYPE string,
             estado_tecnico      TYPE c LENGTH 1,
             tipo_contribuyente  TYPE c LENGTH 1,
             marca_alta_baja     TYPE c LENGTH 1,
             marca_cambio_alic   TYPE c LENGTH 1,
             nro_grupo           TYPE c LENGTH 2,
             fecha_publicacion   TYPE d,
             vigencia_desde      TYPE d,
             vigencia_hasta      TYPE d,
             " Tucuman - Coeficientes: exencion a aplicar por API (coef < 1). Vacio si no aplica.
             exencion_pct        TYPE p LENGTH 5 DECIMALS 2,
             exencion_desde      TYPE d,
             exencion_hasta      TYPE d,
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

    "! Estado final de la ejecucion (EN_PROCESO / OK / OK_CON_ERRORES / FALLIDA).
    TYPES ty_estado_ejec TYPE c LENGTH 15.

    "! CUIT y estructuras de deduplicacion (EF seccion 7). Publicas para que el
    "! Application Job las construya en streaming y las reutilice por lote.
    TYPES ty_cuit TYPE c LENGTH 11.
    TYPES: BEGIN OF ty_cuit_info,
             cuit           TYPE c LENGTH 11,
             veces          TYPE i,
             primera_alic   TYPE p LENGTH 5 DECIMALS 2,
             contradictorio TYPE abap_boolean,
           END OF ty_cuit_info.
    TYPES ty_cuit_info_tt TYPE HASHED TABLE OF ty_cuit_info WITH UNIQUE KEY cuit.
    TYPES ty_cuit_set     TYPE SORTED TABLE OF ty_cuit WITH UNIQUE KEY table_line.
    "! Set de proveedores YA tratados desde el padron (para excluirlos del recorrido fuera de padron).
    TYPES ty_sup_set      TYPE SORTED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.

    METHODS constructor
      IMPORTING io_parser       TYPE REF TO zcl_arba_ret_parser       OPTIONAL
                io_validator    TYPE REF TO zcl_arba_ret_validator    OPTIONAL
                io_determinador TYPE REF TO zcl_arba_ret_determinador OPTIONAL
                io_bp_updater   TYPE REF TO zcl_arba_ret_bp_updater   OPTIONAL.

    "! Procesamiento en memoria (volumen chico / pruebas). Para volumen real, el
    "! Application Job usa preparar + acumular_cuit_info + procesar_registros por lote.
    METHODS procesar
      IMPORTING iv_content      TYPE xstring
                iv_sociedad     TYPE bukrs
                iv_tipo_ret     TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_provincia    TYPE c DEFAULT 'ARBA'
                iv_solo_padron  TYPE abap_boolean DEFAULT abap_true
                iv_ind_fuera    TYPE zcl_arba_ret_determinador=>ty_wht_code OPTIONAL
                iv_prov_desde   TYPE zcl_arba_ret_bp_updater=>ty_supplier OPTIONAL
                iv_prov_hasta   TYPE zcl_arba_ret_bp_updater=>ty_supplier OPTIONAL
                iv_solo_con_ret TYPE abap_boolean DEFAULT abap_false
                iv_simular      TYPE abap_boolean DEFAULT abap_true
      EXPORTING et_log          TYPE ty_log_tt
                es_kpi          TYPE ty_kpi
                ev_estado_ejec  TYPE ty_estado_ejec.

    "! Precarga en memoria del universo (EF seccion 12). Se ejecuta UNA vez por ejecucion.
    METHODS preparar
      IMPORTING iv_sociedad TYPE bukrs
                iv_tipo_ret TYPE zcl_arba_ret_determinador=>ty_wht_type.

    "! Acumula un registro en el mapa de deduplicacion por CUIT (pase 1 del streaming).
    METHODS acumular_cuit_info
      IMPORTING is_record    TYPE zcl_arba_ret_parser=>ty_record
      CHANGING  ct_cuit_info TYPE ty_cuit_info_tt.

    "! Procesa un LOTE de registros ya parseados: validacion + dedup + matching +
    "! determinacion + clasificacion de caso. Reutilizable en memoria y desde el job.
    "! ct_hechos preserva los CUIT ya procesados entre lotes (idempotencia de duplicados).
    METHODS procesar_registros
      IMPORTING it_records      TYPE zcl_arba_ret_parser=>ty_record_tt
                it_cuit_info    TYPE ty_cuit_info_tt
                iv_sociedad     TYPE bukrs
                iv_tipo_ret     TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_prov_desde   TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_prov_hasta   TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_solo_con_ret TYPE abap_boolean
                iv_simular      TYPE abap_boolean
                iv_universo     TYPE c DEFAULT space
      CHANGING  ct_hechos        TYPE ty_cuit_set
                ct_otro_universo TYPE ty_cuit_set
                ct_log           TYPE ty_log_tt
                cs_kpi           TYPE ty_kpi.

    "! Sincronizacion completa (EF 6.3): proveedores con el tipo pero fuera del padron
    "! -> Caso 3 (indicador de alicuota maxima / iv_ind_fuera).
    METHODS procesar_fuera_padron
      IMPORTING iv_sociedad       TYPE bukrs
                iv_tipo_ret       TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_ind_fuera      TYPE zcl_arba_ret_determinador=>ty_wht_code
                iv_prov_desde     TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_prov_hasta     TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_simular        TYPE abap_boolean
                it_sup_procesados TYPE ty_sup_set
                iv_provincia      TYPE c            DEFAULT space
                it_otro_universo  TYPE ty_cuit_set  OPTIONAL
                iv_solo_con_ret   TYPE abap_boolean DEFAULT abap_false
                it_cuit_archivo   TYPE ty_cuit_info_tt OPTIONAL
      CHANGING  ct_log            TYPE ty_log_tt
                cs_kpi            TYPE ty_kpi.

    "! Codigo de universo (col 5 del padron): 'C' (Convenio Multilateral), 'D' (Local) o vacio.
    TYPES ty_universo TYPE c LENGTH 1.

    "! Universo (col 5 del padron) que procesa esta corrida. Santa Fe trae CM (C) y Local (D) en un
    "! mismo archivo: tipo 21 -> 'C', tipo SF -> 'D'. ARBA/CABA -> '' (sin filtro de universo).
    METHODS universo_esperado
      IMPORTING iv_provincia       TYPE c
                iv_tipo_ret        TYPE zcl_arba_ret_determinador=>ty_wht_type
      RETURNING VALUE(rv_universo) TYPE ty_universo.

  PRIVATE SECTION.
    DATA mo_parser       TYPE REF TO zcl_arba_ret_parser.
    DATA mo_validator    TYPE REF TO zcl_arba_ret_validator.
    DATA mo_determinador TYPE REF TO zcl_arba_ret_determinador.
    DATA mo_bp_updater   TYPE REF TO zcl_arba_ret_bp_updater.

    "! Procesa un registro valido y unico (matching + determinacion + caso).
    METHODS procesar_registro
      IMPORTING is_record       TYPE zcl_arba_ret_parser=>ty_record
                iv_alicuota     TYPE zcl_arba_ret_determinador=>ty_alicuota
                iv_sociedad     TYPE bukrs
                iv_tipo_ret     TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_prov_desde   TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_prov_hasta   TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_solo_con_ret TYPE abap_boolean
                iv_simular      TYPE abap_boolean
      CHANGING  ct_log          TYPE ty_log_tt
                cs_kpi          TYPE ty_kpi.

    METHODS conv_fecha
      IMPORTING iv_txt          TYPE c
      RETURNING VALUE(rv_fecha) TYPE d.

    METHODS base_log_row
      IMPORTING is_record     TYPE zcl_arba_ret_parser=>ty_record
      RETURNING VALUE(rs_row) TYPE ty_log_row.
ENDCLASS.



CLASS ZCL_ARBA_RET_PROC_APP IMPLEMENTATION.


  METHOD constructor.
    mo_parser       = COND #( WHEN io_parser IS BOUND THEN io_parser ELSE NEW zcl_arba_ret_parser( ) ).
    mo_validator    = COND #( WHEN io_validator IS BOUND THEN io_validator ELSE NEW zcl_arba_ret_validator( ) ).
    mo_determinador = COND #( WHEN io_determinador IS BOUND THEN io_determinador ELSE NEW zcl_arba_ret_determinador( ) ).
    mo_bp_updater   = COND #( WHEN io_bp_updater IS BOUND THEN io_bp_updater ELSE NEW zcl_arba_ret_bp_updater( ) ).
  ENDMETHOD.


  METHOD preparar.
    mo_bp_updater->preparar( iv_sociedad = iv_sociedad iv_tipo_ret = iv_tipo_ret ).
  ENDMETHOD.


  METHOD procesar.
    CLEAR: et_log, es_kpi, ev_estado_ejec.
    mo_parser->set_provincia( iv_provincia ).

    " 1) Archivo vacio -> rechazo total (EF seccion 10)
    IF xstrlen( iv_content ) = 0.
      ev_estado_ejec = 'FALLIDA'.
      RETURN.
    ENDIF.

    " Padron ARBA/CABA en ISO-8859-1 (Latin-1), no UTF-8 (evita dump CONVT_CODEPAGE por Ñ/acentos).
    DATA(lv_content) = cl_abap_conv_codepage=>create_in( codepage = 'ISO-8859-1' )->convert( source = iv_content ).

    " 2) Parseo completo (en memoria)
    DATA lt_records TYPE zcl_arba_ret_parser=>ty_record_tt.
    mo_parser->parse_file( EXPORTING iv_content = lv_content
                           IMPORTING et_records = lt_records ).
    es_kpi-leidos = lines( lt_records ).
    IF es_kpi-leidos = 0.
      ev_estado_ejec = 'FALLIDA'.
      RETURN.
    ENDIF.

    " 3) Mapa de deduplicacion por CUIT (EF seccion 7)
    DATA lt_cuit_info TYPE ty_cuit_info_tt.
    LOOP AT lt_records ASSIGNING FIELD-SYMBOL(<rec>).
      acumular_cuit_info( EXPORTING is_record = <rec> CHANGING ct_cuit_info = lt_cuit_info ).
    ENDLOOP.

    " 4) Precarga del universo en memoria (EF seccion 12)
    preparar( iv_sociedad = iv_sociedad iv_tipo_ret = iv_tipo_ret ).

    " 5) Procesamiento (un unico lote con todos los registros)
    DATA(lv_universo) = universo_esperado( iv_provincia = iv_provincia iv_tipo_ret = iv_tipo_ret ).
    DATA lt_hechos        TYPE ty_cuit_set.
    DATA lt_otro_universo TYPE ty_cuit_set.
    procesar_registros(
      EXPORTING it_records      = lt_records
                it_cuit_info    = lt_cuit_info
                iv_sociedad     = iv_sociedad
                iv_tipo_ret     = iv_tipo_ret
                iv_prov_desde   = iv_prov_desde
                iv_prov_hasta   = iv_prov_hasta
                iv_solo_con_ret = iv_solo_con_ret
                iv_simular      = iv_simular
                iv_universo     = lv_universo
      CHANGING  ct_hechos        = lt_hechos
                ct_otro_universo = lt_otro_universo
                ct_log           = et_log
                cs_kpi           = es_kpi ).

    " 6) Sincronizacion completa (EF 6.3): Caso 3 fuera de padron
    IF iv_solo_padron = abap_false.
      " Set de proveedores ya tratados desde el padron (aca et_log ya tiene TODO el log).
      DATA lt_sup_proc TYPE ty_sup_set.
      LOOP AT et_log INTO DATA(ls_lp) WHERE proveedor IS NOT INITIAL.
        INSERT ls_lp-proveedor INTO TABLE lt_sup_proc.
      ENDLOOP.
      procesar_fuera_padron(
        EXPORTING iv_sociedad       = iv_sociedad
                  iv_tipo_ret       = iv_tipo_ret
                  iv_ind_fuera      = iv_ind_fuera
                  iv_prov_desde     = iv_prov_desde
                  iv_prov_hasta     = iv_prov_hasta
                  iv_simular        = iv_simular
                  it_sup_procesados = lt_sup_proc
                  iv_provincia      = iv_provincia
                  it_otro_universo  = lt_otro_universo
                  iv_solo_con_ret   = iv_solo_con_ret
                  it_cuit_archivo   = lt_cuit_info
        CHANGING  ct_log            = et_log
                  cs_kpi            = es_kpi ).
    ENDIF.

    " 7) Estado final (EF seccion 9)
    ev_estado_ejec = COND #( WHEN es_kpi-error_tecnico > 0 THEN 'OK_CON_ERRORES' ELSE 'OK' ).
  ENDMETHOD.


  METHOD acumular_cuit_info.
    " Solo los registros VALIDOS cuentan para la deteccion de duplicados
    DATA(ls_val) = mo_validator->validate_record( is_record ).
    IF ls_val-es_valido = abap_false.
      RETURN.
    ENDIF.

    READ TABLE ct_cuit_info ASSIGNING FIELD-SYMBOL(<info>) WITH KEY cuit = is_record-cuit.
    IF sy-subrc <> 0.
      INSERT VALUE #( cuit = is_record-cuit veces = 1 primera_alic = ls_val-alicuota )
             INTO TABLE ct_cuit_info.
    ELSE.
      ADD 1 TO <info>-veces.
      IF ls_val-alicuota <> <info>-primera_alic.
        <info>-contradictorio = abap_true.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD procesar_registros.
    LOOP AT it_records ASSIGNING FIELD-SYMBOL(<rec>).
      " Filtro de universo (Santa Fe): esta corrida procesa un solo universo (C o D, col 5). Los del
      " OTRO universo se saltean; si tienen CUIT valido se guardan para detectar cambio de regimen.
      " (Ademas saltea la linea de encabezado del CSV, cuya col 5 no es ni C ni D.)
      IF iv_universo IS NOT INITIAL AND <rec>-tipo_contribuyente <> iv_universo.
        IF matches( val = <rec>-cuit regex = `\d{11}` ).
          INSERT <rec>-cuit INTO TABLE ct_otro_universo.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Validacion (EF seccion 10)
      DATA(ls_val) = mo_validator->validate_record( <rec> ).
      IF ls_val-es_valido = abap_false.
        DATA(ls_rej) = base_log_row( <rec> ).
        ls_rej-estado  = ls_val-estado.
        ls_rej-mensaje = ls_val-mensaje.
        APPEND ls_rej TO ct_log.
        ADD 1 TO cs_kpi-rechazados.
        CONTINUE.
      ENDIF.

      DATA(ls_info) = VALUE ty_cuit_info( it_cuit_info[ cuit = <rec>-cuit ] OPTIONAL ).

      " Duplicado contradictorio: rechazo de todas las lineas del CUIT (EF seccion 7)
      IF ls_info-contradictorio = abap_true.
        DATA(ls_dup) = base_log_row( <rec> ).
        ls_dup-estado  = 'REV'.
        ls_dup-mensaje = 'Duplicado contradictorio: mismo CUIT con distinta alicuota'.
        APPEND ls_dup TO ct_log.
        ADD 1 TO cs_kpi-rechazados.
        CONTINUE.
      ENDIF.

      " Duplicado identico: se procesa una vez, el resto se omite
      IF ls_info-veces > 1 AND line_exists( ct_hechos[ table_line = <rec>-cuit ] ).
        DATA(ls_omi) = base_log_row( <rec> ).
        ls_omi-estado  = 'OMI'.
        ls_omi-mensaje = 'Omitido por regla funcional: duplicado identico en el archivo'.
        APPEND ls_omi TO ct_log.
        ADD 1 TO cs_kpi-omitidos.
        CONTINUE.
      ENDIF.
      INSERT <rec>-cuit INTO TABLE ct_hechos.

      procesar_registro(
        EXPORTING is_record       = <rec>
                  iv_alicuota     = ls_val-alicuota
                  iv_sociedad     = iv_sociedad
                  iv_tipo_ret     = iv_tipo_ret
                  iv_prov_desde   = iv_prov_desde
                  iv_prov_hasta   = iv_prov_hasta
                  iv_solo_con_ret = iv_solo_con_ret
                  iv_simular      = iv_simular
        CHANGING  ct_log          = ct_log
                  cs_kpi          = cs_kpi ).
    ENDLOOP.
  ENDMETHOD.


  METHOD procesar_registro.
    DATA(ls_row) = base_log_row( is_record ).
    ls_row-alicuota_nueva = iv_alicuota.

    " Matching de proveedor por CUIT (EF seccion 9)
    DATA lt_sup TYPE zcl_arba_ret_bp_updater=>ty_supplier_tt.
    mo_bp_updater->buscar_proveedor( EXPORTING iv_cuit      = is_record-cuit
                                     IMPORTING et_suppliers = lt_sup ).

    IF lines( lt_sup ) = 0.
      ls_row-estado  = 'NOE'.
      ls_row-mensaje = 'CUIT sin proveedor en SAP (fuera del universo)'.
      APPEND ls_row TO ct_log.
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

    " Filtro opcional de proveedores (EF seccion 8)
    IF ( iv_prov_desde IS NOT INITIAL AND lv_sup < iv_prov_desde )
    OR ( iv_prov_hasta IS NOT INITIAL AND lv_sup > iv_prov_hasta ).
      ls_row-estado  = 'OMI'.
      ls_row-mensaje = 'Omitido: proveedor fuera del filtro'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
      RETURN.
    ENDIF.

    " Lectura del registro de retencion actual
    DATA(ls_act) = mo_bp_updater->leer_retencion_actual(
      iv_supplier = lv_sup iv_sociedad = iv_sociedad iv_tipo_ret = iv_tipo_ret ).
    ls_row-indicador_anterior  = ls_act-indicador.
    ls_row-sujeto_ret_anterior = COND #( WHEN ls_act-es_sujeto = abap_true THEN 'X' ELSE '' ).

    " Filtro "solo proveedores con datos de retencion existentes"
    IF iv_solo_con_ret = abap_true AND ls_act-existe = abap_false.
      ls_row-estado  = 'OMI'.
      ls_row-mensaje = 'Omitido: proveedor sin datos de retencion (filtro activo)'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
      RETURN.
    ENDIF.

    " Determinacion del indicador por alicuota (EF seccion 5)
    DATA lv_ind_nuevo TYPE zcl_arba_ret_determinador=>ty_wht_code.
    DATA lv_estado_det TYPE c LENGTH 3.
    DATA lv_msg_det TYPE string.
    mo_determinador->determinar_indicador(
      EXPORTING iv_tipo_ret  = iv_tipo_ret iv_alicuota = iv_alicuota
      IMPORTING ev_indicador = lv_ind_nuevo ev_estado = lv_estado_det ev_mensaje = lv_msg_det ).

    " DESAMBIGUACION por GRUPO del padron (HIPOTESIS a validar; funcional no disponible): si la
    " determinacion por alicuota es ambigua / sin match (PCF) y el padron trae un GRUPO RETEN
    " (is_record-nro_grupo) que ES un codigo valido del tipo Y cuya alicuota configurada coincide con la
    " del archivo, se toma ESE codigo. O sea: se asume que la columna GRUPO RETEN = codigo de retencion,
    " y sirve para elegir entre varios codigos a la misma alicuota (ej. ARBA tipo 02: 2 codigos a 1,75%).
    " El GRUPO RETEN se parsea por provincia: ARBA col 10, CABA/SF col 11 (ambas -> is_record-nro_grupo).
    " Reversible: si el funcional define otra regla, se ajusta o se quita.
    IF lv_estado_det = 'PCF' AND is_record-nro_grupo IS NOT INITIAL.
      DATA lv_alic_g TYPE zcl_arba_ret_determinador=>ty_alicuota.
      DATA lv_est_g  TYPE c LENGTH 3.
      DATA lv_msg_g  TYPE string.
      mo_determinador->obtener_alicuota_indicador(
        EXPORTING iv_tipo_ret  = iv_tipo_ret
                  iv_indicador = is_record-nro_grupo
        IMPORTING ev_alicuota  = lv_alic_g
                  ev_estado    = lv_est_g
                  ev_mensaje   = lv_msg_g ).
      IF lv_est_g IS INITIAL AND lv_alic_g = iv_alicuota.
        lv_ind_nuevo  = is_record-nro_grupo.
        lv_estado_det = ''.
        lv_msg_det    = ''.
      ENDIF.
    ENDIF.

    IF lv_estado_det = 'PCF'.
      ls_row-estado  = 'PCF'.
      " Caso: '2' = titular del tipo -> sigue en el export con su codigo ACTUAL (si no, la estandar se lo
      " borraria por ausencia); '1' = sin el tipo -> NO va al export (la estandar no puede darle un indicador
      " que no existe) ni se da de alta (ALTA y partidas filtran estado 'ACT').
      ls_row-caso    = COND #( WHEN ls_act-existe = abap_true THEN '2' ELSE '1' ).
      ls_row-mensaje = |{ lv_msg_det }. | && COND string(
                         WHEN ls_act-existe = abap_true THEN |Se mantiene el indicador actual { ls_act-indicador }.|
                         ELSE `No se da de alta la retención.` ).
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-pendiente_config.
      RETURN.
    ENDIF.

    ls_row-indicador_nuevo  = lv_ind_nuevo.
    ls_row-sujeto_ret_nuevo = 'X'.

    " Clasificacion de caso y accion (EF seccion 6)
    IF ls_act-existe = abap_false.
      ls_row-caso = '1'.
      " Sin datos en la sociedad no se puede crear la retencion (la API la rechaza): se informa y se omite.
      IF mo_bp_updater->esta_ampliado( lv_sup ) = abap_false.
        ls_row-estado  = 'OMI'.
        ls_row-mensaje = |Omitido: proveedor no ampliado a la sociedad { iv_sociedad } (no se puede dar de alta la retencion)|.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-omitidos.
        RETURN.
      ENDIF.
    ELSE.
      ls_row-caso = '2'.
      IF ls_act-indicador = lv_ind_nuevo.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = 'Sin cambios: el indicador ya coincide con la alicuota'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        RETURN.
      ENDIF.
    ENDIF.

    " El RAP determina el indicador y lo deja en el log. El apply del maestro difiere segun el caso:
    "   Caso 2 (cambio de codigo): maestro + PARTIDAS ABIERTAS los hace integramente la app estandar
    "     "Update Withholding Tax Codes and Open Items" + BAdI ES_FIWTAR_UPDATE_TAXCODE con el .txt.
    "   Caso 1 (alta): la estandar NO crea el tipo que el proveedor no tiene -> el ALTA del maestro la
    "     crea "Ejecutar" (modo real) por API (A_SupplierWithHoldingTax), en el job y DESPUES de
    "     determinar (ZCL_ARBA_RET_ALTA, llamada desde ZCL_ARBA_RET_JOB); ese paso REESCRIBE el mensaje
    "     de esta fila con el resultado real. Las PARTIDAS del alta las ajusta luego la estandar (al
    "     correr el .txt el proveedor ya tiene el tipo y entra como titular). En Simulacion no se crea nada.
    ls_row-estado = 'ACT'.
    DATA(lv_verbo) = COND string(
      WHEN ls_row-caso = '1'
      THEN 'alta de retencion (Ejecutar la crea en el maestro y programa el ajuste de partidas)'
      ELSE 'cambio de indicador (el apply lo hace la app estandar + BAdI)' ).
    ls_row-mensaje = |{ COND string( WHEN iv_simular = abap_true THEN 'Simulacion' ELSE 'Determinado' ) }: { lv_verbo }|.
    APPEND ls_row TO ct_log.
    ADD 1 TO cs_kpi-actualizados.
  ENDMETHOD.


  METHOD procesar_fuera_padron.
    " Indicador "fuera de padron": override manual o, por defecto, el de alicuota maxima.
    DATA lv_ind_fuera  TYPE zcl_arba_ret_determinador=>ty_wht_code.
    DATA lv_alic_fuera TYPE p LENGTH 5 DECIMALS 2.
    DATA lv_est        TYPE c LENGTH 3.
    DATA lv_msg        TYPE string.

    IF iv_ind_fuera IS NOT INITIAL.
      lv_ind_fuera = iv_ind_fuera.
    ELSE.
      mo_determinador->obtener_indicador_maximo(
        EXPORTING iv_tipo_ret  = iv_tipo_ret
        IMPORTING ev_indicador = lv_ind_fuera
                  ev_estado    = lv_est
                  ev_mensaje   = lv_msg ).
      IF lv_est = 'PCF'.
        " Max ambiguo y SIN "Indicador Fuera de Padron" informado -> no se puede resolver el indicador.
        " Antes abortaba en silencio (los fuera de padron "no aparecian"); ahora deja una nota visible.
        APPEND VALUE #( caso    = '3'
                        estado  = 'OMI'
                        mensaje = |Fuera de padron NO ejecutado: { lv_msg }. Informe "Indicador Fuera de Padron".| )
               TO ct_log.
        RETURN.
      ENDIF.
    ENDIF.

    " Alicuota del indicador aplicado -> el LOG (y por ende el .txt del EXPORT de cambios) debe llevar
    " la alicuota REAL del indicador fuera de padron (ej. indicador 28 -> 4,00), NO 0,00. Bug previo:
    " en el path del indicador MANUAL, lv_alic_fuera quedaba en 0 -> el .txt salia con "0,00" y la BAdI
    " recalculaba mal el indicador (alicuota 0 en vez de la de fuera-de-padron / maxima).
    mo_determinador->obtener_alicuota_indicador(
      EXPORTING iv_tipo_ret  = iv_tipo_ret
                iv_indicador = lv_ind_fuera
      IMPORTING ev_alicuota  = lv_alic_fuera ).

    " Region del dato maestro de la provincia: CABA 00, ARBA 01, Santa Fe 12 (Tucuman 14 en su motor).
    " La usan el Caso 3 (titulares fuera del archivo) y el Caso 4 (altas por region).
    DATA lv_region TYPE c LENGTH 3.
    lv_region = SWITCH #( iv_provincia WHEN 'CABA' THEN '00'
                                     WHEN 'ARBA' THEN '01'
                                     WHEN 'SF'   THEN '12' ).
    DATA lt_region  TYPE zcl_arba_ret_bp_updater=>ty_sup_ret_tt.
    DATA lv_reg_err TYPE abap_boolean.
    DATA lv_reg_msg TYPE string.
    IF lv_region IS NOT INITIAL.
      mo_bp_updater->get_proveedores_por_region( EXPORTING iv_region  = lv_region
                                                 IMPORTING et_sup     = lt_region
                                                           ev_error   = lv_reg_err
                                                           ev_mensaje = lv_reg_msg ).
    ENDIF.
    DATA lt_sup_region TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.
    LOOP AT lt_region INTO DATA(ls_rg0).
      INSERT ls_rg0-supplier INTO TABLE lt_sup_region.
    ENDLOOP.
    " Universo ESTRICTO: proveedores ampliados a la sociedad y de pais AR (la vista de region no filtra
    " pais: un proveedor del exterior con region '01'/'12' no debe recibir una retencion provincial).
    DATA lt_soc_ar TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.
    SELECT DISTINCT c~supplier
      FROM i_suppliercompany AS c
      INNER JOIN i_supplier AS s ON s~supplier = c~supplier
      WHERE c~companycode = @iv_sociedad
        AND s~country     = 'AR'
      INTO TABLE @lt_soc_ar.

    " Proveedores ya tratados desde el padron: se reciben del caller (it_sup_procesados).
    " NO derivar de ct_log: el Application Job persiste y descarta el log por lote, con lo
    " cual ct_log llegaria vacio y TODOS los proveedores con el tipo recibirian el "fuera de
    " padron" (incluidos los que SI estan en el padron). Por eso el set viaja explicito.
    LOOP AT mo_bp_updater->get_proveedores_con_retencion( ) INTO DATA(ls_sup).
      IF line_exists( it_sup_procesados[ table_line = ls_sup-supplier ] ).
        CONTINUE.
      ENDIF.
      IF ( iv_prov_desde IS NOT INITIAL AND ls_sup-supplier < iv_prov_desde )
      OR ( iv_prov_hasta IS NOT INITIAL AND ls_sup-supplier > iv_prov_hasta ).
        CONTINUE.
      ENDIF.

      " CAMBIO DE REGIMEN (Santa Fe): el proveedor tiene este tipo pero aparece en el OTRO universo del
      " archivo (paso de CM<->Local). El Z NO toca el maestro: solo DETECTA y marca 'REG', y -clave- lo
      " EXCLUYE del export (el handler lee 'ACT'/'SCB', no 'REG'). Como al subir el padron a la app
      " estandar este proveedor NO esta en el archivo, la estandar le BORRA el tipo viejo (maestro Y
      " partidas abiertas). El tipo NUEVO se lo asigna la corrida del OTRO universo (alta -> export ->
      " estandar). Antes se borraba por API (opcion A), pero la API no ajustaba partidas -> se delega
      " todo el borrado (maestro + PAs) a la app estandar via la ausencia en el snapshot.
      IF iv_provincia = 'SF' AND line_exists( it_otro_universo[ table_line = ls_sup-cuit ] ).
        DATA ls_reg TYPE ty_log_row.
        CLEAR ls_reg.
        ls_reg-cuit               = ls_sup-cuit.
        ls_reg-proveedor          = ls_sup-supplier.
        ls_reg-caso               = 'R'.
        ls_reg-indicador_anterior = ls_sup-indicador.
        ls_reg-estado             = 'REG'.
        ls_reg-mensaje            = |Cambio de regimen: el tipo { iv_tipo_ret } lo BORRA la app estandar | &&
                                    |(se EXCLUYE del export; el tipo nuevo lo asigna la corrida del otro universo).|.
        ADD 1 TO cs_kpi-actualizados.
        APPEND ls_reg TO ct_log.
        CONTINUE.
      ENDIF.

      DATA ls_row TYPE ty_log_row.
      CLEAR ls_row.
      ls_row-cuit                = ls_sup-cuit.
      ls_row-proveedor           = ls_sup-supplier.
      ls_row-caso                = '3'.
      ls_row-indicador_anterior  = ls_sup-indicador.
      ls_row-indicador_nuevo     = lv_ind_fuera.
      ls_row-alicuota_nueva      = lv_alic_fuera.
      ls_row-sujeto_ret_anterior = COND #( WHEN ls_sup-es_sujeto = abap_true THEN 'X' ELSE '' ).
      ls_row-sujeto_ret_nuevo    = 'X'.

      " Redmine 33756 (15/10): fuera del archivo solo se toma al titular con la Region de la provincia
      " (pais AR). Region vacia u otra -> se conserva SIN CAMBIO con su indicador actual (SCB: va al export
      " como keeper, la estandar no le borra el tipo). Region no legible -> se conservan todos.
      IF lv_reg_err = abap_true
      OR NOT line_exists( lt_sup_region[ table_line = ls_sup-supplier ] )
      OR NOT line_exists( lt_soc_ar[ table_line = ls_sup-supplier ] ).
        DATA lv_alic_act TYPE zcl_arba_ret_determinador=>ty_alicuota.
        CLEAR lv_alic_act.
        mo_determinador->obtener_alicuota_indicador(
          EXPORTING iv_tipo_ret  = iv_tipo_ret
                    iv_indicador = ls_sup-indicador
          IMPORTING ev_alicuota  = lv_alic_act ).
        ls_row-indicador_nuevo  = ls_sup-indicador.
        ls_row-alicuota_nueva   = lv_alic_act.
        ls_row-sujeto_ret_nuevo = ls_row-sujeto_ret_anterior.
        ls_row-estado           = 'SCB'.
        ls_row-mensaje          = COND #(
          WHEN lv_reg_err = abap_true
          THEN zcl_arba_ret_alta=>cortar( |Fuera de padron: no se pudo leer la region ({ lv_reg_msg }); se conserva el indicador { ls_sup-indicador }| )
          ELSE |Fuera de padron: region del proveedor vacia o distinta de { lv_region }; se conserva el indicador { ls_sup-indicador }| ).
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      IF ls_sup-indicador = lv_ind_fuera.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = |Fuera de padron: ya tiene el indicador { lv_ind_fuera }|.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      " El RAP NO actualiza el maestro: solo determina y deja la fila en el log para exportar.
      " El apply (maestro + PAs) lo hace la app estandar + BAdI con el .txt exportado.
      ls_row-estado  = 'ACT'.
      ls_row-mensaje = |{ COND string( WHEN iv_simular = abap_true THEN `Simulacion` ELSE `Determinado` ) }: | &&
                       |fuera de padron -> indicador { lv_ind_fuera } (aplica la app estandar + BAdI)|.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
    ENDLOOP.

    " Caso 4 - ALTA fuera de padron por REGION (Redmine 33756, 05/10): proveedores ampliados a la sociedad,
    " con domicilio en la provincia del padron, que NO tienen el tipo y NO vinieron en el archivo -> se les
    " crea el tipo con el Indicador Fuera de Padron (maestro por API + partidas, en Ejecutar, igual que el
    " Caso 1). Region del dato maestro: CABA 00, ARBA 01, Santa Fe 12. Tucuman (14) lo arma su propio motor.
    " (lv_region / lt_region / lt_soc_ar se leen arriba, antes del Caso 3)
    " "Solo con retencion existente": no se da de alta a nadie (mismo criterio que el Caso 1).
    IF lv_region IS INITIAL OR iv_solo_con_ret = abap_true.
      RETURN.
    ENDIF.
    IF lv_reg_err = abap_true.
      APPEND VALUE #( caso    = '4'
                      estado  = 'OMI'
                      mensaje = zcl_arba_ret_alta=>cortar( |Alta fuera de padron por region { lv_region } NO ejecutada: { lv_reg_msg }| ) )
             TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
      RETURN.
    ENDIF.

    " Si la lectura de region viene vacia (p. ej. sin autorizacion) no se da de alta a nadie.
    LOOP AT lt_region INTO DATA(ls_rg).
      " Vino en el archivo (por proveedor o por CUIT: tambien los rechazados/duplicados del archivo) / ya
      " tiene el tipo (lo cubre el recorrido de arriba) / no ampliado a la sociedad o no AR -> no aplica.
      IF line_exists( it_sup_procesados[ table_line = ls_rg-supplier ] )
      OR line_exists( it_cuit_archivo[ cuit = ls_rg-cuit ] )
      OR mo_bp_updater->leer_retencion_actual( iv_supplier = ls_rg-supplier iv_sociedad = iv_sociedad
                                               iv_tipo_ret = iv_tipo_ret )-existe = abap_true
      OR NOT line_exists( lt_soc_ar[ table_line = ls_rg-supplier ] ).
        CONTINUE.
      ENDIF.
      IF ( iv_prov_desde IS NOT INITIAL AND ls_rg-supplier < iv_prov_desde )
      OR ( iv_prov_hasta IS NOT INITIAL AND ls_rg-supplier > iv_prov_hasta ).
        CONTINUE.
      ENDIF.
      " Santa Fe: si el CUIT figura en el OTRO universo del archivo (CM <-> Local), lo da de alta esa corrida.
      IF iv_provincia = 'SF' AND line_exists( it_otro_universo[ table_line = ls_rg-cuit ] ).
        CONTINUE.
      ENDIF.

      DATA ls_alta TYPE ty_log_row.
      CLEAR ls_alta.
      ls_alta-cuit             = ls_rg-cuit.
      ls_alta-proveedor        = ls_rg-supplier.
      ls_alta-caso             = '4'.
      ls_alta-indicador_nuevo  = lv_ind_fuera.
      ls_alta-alicuota_nueva   = lv_alic_fuera.
      ls_alta-sujeto_ret_nuevo = 'X'.
      ls_alta-estado           = 'ACT'.
      ls_alta-mensaje          = |{ COND string( WHEN iv_simular = abap_true THEN `Simulacion` ELSE `Determinado` ) }: | &&
                                 |fuera de padron (region { lv_region }) sin la retencion -> alta con indicador | &&
                                 |{ lv_ind_fuera } (Ejecutar la crea en el maestro y ajusta las partidas)|.
      APPEND ls_alta TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
    ENDLOOP.
  ENDMETHOD.


  METHOD universo_esperado.
    " Santa Fe: un archivo con dos universos en la col 5 -> tipo 21 procesa 'C' (Convenio Multilateral),
    " tipo SF procesa 'D' (Local). ARBA/CABA: sin filtro de universo.
    rv_universo = COND #( WHEN iv_provincia = 'SF'
                          THEN COND #( WHEN iv_tipo_ret = '21' THEN 'C'
                                       WHEN iv_tipo_ret = 'SF' THEN 'D'
                                       ELSE '' )
                          ELSE '' ).
  ENDMETHOD.


  METHOD base_log_row.
    rs_row-nro_linea          = is_record-nro_linea.
    rs_row-cuit               = is_record-cuit.
    rs_row-tipo_contribuyente = is_record-tipo_contribuyente.
    rs_row-marca_alta_baja    = is_record-marca_alta_baja.
    rs_row-marca_cambio_alic  = is_record-marca_cambio_alic.
    rs_row-nro_grupo          = is_record-nro_grupo.
    rs_row-fecha_publicacion  = conv_fecha( is_record-fecha_publicacion ).
    rs_row-vigencia_desde     = conv_fecha( is_record-vigencia_desde ).
    rs_row-vigencia_hasta     = conv_fecha( is_record-vigencia_hasta ).
  ENDMETHOD.


  METHOD conv_fecha.
    CLEAR rv_fecha.
    IF strlen( iv_txt ) = 8 AND matches( val = iv_txt regex = `\d{8}` ).
      rv_fecha = |{ iv_txt+4(4) }{ iv_txt+2(2) }{ iv_txt+0(2) }|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
