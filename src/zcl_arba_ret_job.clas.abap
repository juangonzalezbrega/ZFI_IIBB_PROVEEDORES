CLASS zcl_arba_ret_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.   " diseno: parametros del job
    INTERFACES if_apj_rt_exec_object.   " runtime: metodo execute

  PRIVATE SECTION.
    "! Tamanio de lote (registros por paquete). Parametrizable (EF seccion 12).
    CONSTANTS c_batch_size TYPE i VALUE 500.

    "! Orquestacion completa en background: streaming + lotes + persistencia + cierre.
    METHODS procesar_padron
      IMPORTING is_ejec    TYPE zarba_ret_ejec
                iv_simular TYPE abap_boolean.

    "! Procesa un lote (reusa proc_app), persiste su log y limpia el buffer.
    METHODS procesar_lote
      IMPORTING io_proc      TYPE REF TO zcl_arba_ret_proc_app
                is_ejec      TYPE zarba_ret_ejec
                it_cuit_info TYPE zcl_arba_ret_proc_app=>ty_cuit_info_tt
                iv_simular   TYPE abap_boolean
                iv_universo  TYPE c
      CHANGING  ct_hechos        TYPE zcl_arba_ret_proc_app=>ty_cuit_set
                ct_otro_universo TYPE zcl_arba_ret_proc_app=>ty_cuit_set
                cs_kpi           TYPE zcl_arba_ret_proc_app=>ty_kpi
                ct_batch         TYPE zcl_arba_ret_parser=>ty_record_tt
                ct_sup_proc      TYPE zcl_arba_ret_proc_app=>ty_sup_set.

    "! Devuelve la siguiente linea desde cv_off (sin construir la tabla completa).
    METHODS siguiente_linea
      IMPORTING iv_text        TYPE string
      CHANGING  cv_off         TYPE i
      RETURNING VALUE(rv_line) TYPE string.

    "! Persiste un bloque de log por SQL directo (INSERT masivo) + COMMIT WORK.
    METHODS persistir_log
      IMPORTING iv_uuid TYPE sysuuid_x16
                it_log  TYPE zcl_arba_ret_proc_app=>ty_log_tt.

    "! Programa el job estandar "Ajuste de la informacion de retencion a los tipos importantes"
    "! (SAP_FIN_TAX_ADJUST_WHT) para los proveedores + sociedad dados: agrega a sus PARTIDAS ABIERTAS el
    "! tipo que se les dio de alta en el maestro, con el indicador del maestro. iv_test = modo test.
    "! Deja el job en la cabecera (Job Ajuste Partidas) y el resultado en el log de esas filas.
    METHODS programar_ajuste_partidas
      IMPORTING iv_uuid     TYPE sysuuid_x16
                iv_id_ejec  TYPE c
                iv_sociedad TYPE bukrs
                it_sup      TYPE zcl_arba_ret_alta=>ty_sup_tt
                iv_test     TYPE abap_boolean.

    "! Cierra la ejecucion: KPIs + estado + limpieza del archivo + disparo del ajuste de partidas.
    METHODS finalizar
      IMPORTING iv_uuid       TYPE sysuuid_x16
                iv_estado     TYPE zcl_arba_ret_proc_app=>ty_estado_ejec
                is_kpi        TYPE zcl_arba_ret_proc_app=>ty_kpi
                iv_simular    TYPE abap_boolean
                iv_archivo    TYPE xstring
                iv_sociedad   TYPE bukrs
                iv_prov_desde TYPE zcl_arba_ret_bp_updater=>ty_supplier OPTIONAL
                iv_prov_hasta TYPE zcl_arba_ret_bp_updater=>ty_supplier OPTIONAL.
ENDCLASS.



CLASS ZCL_ARBA_RET_JOB IMPLEMENTATION.


  METHOD if_apj_dt_exec_object~get_parameters.
    " Diseno: parametros del Application Job (ID_EJEC + SIMULAR)
    et_parameter_def = VALUE #(
      ( selname = 'ID_EJEC' kind = if_apj_dt_exec_object=>parameter
        datatype = 'C' length = 32 param_text = 'ID Ejecucion' changeable_ind = abap_true )
      ( selname = 'SIMULAR' kind = if_apj_dt_exec_object=>parameter
        datatype = 'C' length = 1  param_text = 'Simulacion (X)' changeable_ind = abap_true ) ).
  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.
    " Runtime: punto de entrada del job
    DATA lv_id      TYPE c LENGTH 32.
    DATA lv_simular TYPE abap_boolean.

    LOOP AT it_parameters INTO DATA(ls_p).
      CASE ls_p-selname.
        WHEN 'ID_EJEC'. lv_id = ls_p-low.
        WHEN 'SIMULAR'. lv_simular = COND #( WHEN ls_p-low = 'X' THEN abap_true ELSE abap_false ).
      ENDCASE.
    ENDLOOP.

    SELECT SINGLE * FROM zarba_ret_ejec WHERE id_ejecucion = @lv_id INTO @DATA(ls_ejec).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Cada corrida REEMPLAZA el log de la ejecucion: el flujo es Simular -> Ejecutar sobre la MISMA
    " ejecucion y persistir_log solo inserta. Sin esto quedaban las filas de la simulacion junto a las
    " de la corrida real (export con lineas duplicadas y altas Caso 1 repetidas -> 2do POST fallido).
    " Re-correr una ejecucion ya procesada en REAL esta bloqueado en el handler (Simular/Ejecutar).
    DELETE FROM zarba_ret_log WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid.
    " El job de ajuste de partidas de una corrida anterior no aplica a esta.
    UPDATE zarba_ret_ejec SET job_partidas = @space, alicuotas_pend = @space
      WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid.
    COMMIT WORK.

    procesar_padron( is_ejec = ls_ejec iv_simular = lv_simular ).

    " Detalle de "Pendiente Configuracion" para el Resumen: alicuotas del archivo sin indicador configurado
    " y cuantos proveedores las tienen (p. ej. "0,70 (9); 1,25 (2)"). Tucuman tiene sus propios PCF.
    IF ls_ejec-provincia <> 'TUC'
   AND ls_ejec-provincia <> zcl_arba_ret_sal_param=>c_provincia
   AND ls_ejec-provincia <> zcl_arba_ret_er_param=>c_provincia.
    "IF ls_ejec-provincia <> 'TUC' AND ls_ejec-provincia <> zcl_arba_ret_sal_param=>c_provincia.
      SELECT alicuota_nueva, COUNT(*) AS cnt FROM zarba_ret_log
        WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid AND estado = 'PCF'
        GROUP BY alicuota_nueva
        ORDER BY alicuota_nueva
        INTO TABLE @DATA(lt_pcf).
      IF lt_pcf IS NOT INITIAL.
        DATA lv_pend_s TYPE string.
        LOOP AT lt_pcf INTO DATA(ls_pcf).
          lv_pend_s = |{ lv_pend_s }{ COND string( WHEN lv_pend_s IS NOT INITIAL THEN `; ` ) }| &&
                      |{ replace( val = |{ ls_pcf-alicuota_nueva DECIMALS = 2 }| sub = `.` with = `,` ) } ({ ls_pcf-cnt })|.
        ENDLOOP.
        DATA(lv_pend) = CONV zarba_ret_ejec-alicuotas_pend(
          COND string( WHEN strlen( lv_pend_s ) > 255 THEN substring( val = lv_pend_s len = 252 ) && `...`
                       ELSE lv_pend_s ) ).
        UPDATE zarba_ret_ejec SET alicuotas_pend = @lv_pend WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid.
        COMMIT WORK.
      ENDIF.
    ENDIF.

    " ALTA (Caso 1) por API: la app estandar NO crea el tipo que el proveedor no tiene -> se crea aca en
    " el maestro (A_SupplierWithHoldingTax) para que, al correr luego "Actualizar Codigos y Partidas", el
    " proveedor ya sea titular y la estandar le ajuste las PARTIDAS. Solo en corrida REAL y DESPUES de
    " determinar/persistir (el log ya esta commiteado). Aplica a TODAS las provincias (lee del log, cubre
    " tambien el path de Tucuman que sale por procesar_padron). El resultado queda por fila en el log; si
    " alguna alta falla (p.ej. Communication Arrangement ZCS_ARBA_RET_BP_OUT sin configurar), la ejecucion
    " pasa a OK_CON_ERRORES. Si no hay altas (Caso 1), no abre conexion (no molesta al resto de padrones).
    " Solo si el procesamiento termino (OK / OK_CON_ERRORES); con FALLIDA no hay altas validas.
    SELECT SINGLE estado_ejecucion FROM zarba_ret_ejec
      WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid
      INTO @DATA(lv_estado_fin).
    IF lv_estado_fin <> 'OK' AND lv_estado_fin <> 'OK_CON_ERRORES'.
      RETURN.
    ENDIF.

    " Simulacion: el ajuste de partidas de las altas se programa en MODO TEST (no graba). Como la
    " simulacion no crea el tipo en el maestro, el test solo muestra otros ajustes pendientes de esos
    " proveedores; el alta de partidas real ocurre al Ejecutar.
    IF lv_simular = abap_true.
      SELECT DISTINCT proveedor FROM zarba_ret_log
        WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid AND caso = '1' AND estado = 'ACT'
          AND proveedor <> @space
        INTO TABLE @DATA(lt_sim_sup).
      IF lt_sim_sup IS NOT INITIAL.
        programar_ajuste_partidas( iv_uuid = ls_ejec-ejecucion_uuid iv_id_ejec = ls_ejec-id_ejecucion
                                   iv_sociedad = ls_ejec-sociedad iv_test = abap_true
                                   it_sup = VALUE #( FOR s IN lt_sim_sup ( s-proveedor ) ) ).
      ENDIF.
      RETURN.
    ENDIF.

    IF lv_simular = abap_false.
      DATA(ls_alta) = NEW zcl_arba_ret_alta( )->aplicar( iv_ejecucion_uuid = ls_ejec-ejecucion_uuid ).
      " Bajas del tipo (Tucuman, Redmine 33748 nota #57): DESPUES de las altas, porque la baja del tipo de
      " fuera de padron exige que el proveedor ya tenga el tipo de padron en el maestro. Sin filas 'BAJ'
      " (resto de provincias) no abre conexion.
      DATA(ls_baja) = NEW zcl_arba_ret_alta( )->aplicar_bajas( iv_ejecucion_uuid = ls_ejec-ejecucion_uuid ).
      " Partidas abiertas de los proveedores dados de alta o de baja: un solo programado de ajuste en REAL,
      " despues de altas y bajas (el job alinea las partidas con el maestro: agrega y borra tipos).
      DATA(lt_sup_part) = ls_alta-proveedores_ok.
      APPEND LINES OF ls_baja-proveedores_ok TO lt_sup_part.
      SORT lt_sup_part BY table_line.
      DELETE ADJACENT DUPLICATES FROM lt_sup_part COMPARING table_line.
      IF lt_sup_part IS NOT INITIAL.
        programar_ajuste_partidas( iv_uuid = ls_ejec-ejecucion_uuid iv_id_ejec = ls_ejec-id_ejecucion
                                   iv_sociedad = ls_ejec-sociedad iv_test = abap_false
                                   it_sup = lt_sup_part ).
      ENDIF.
      " Bajas no aplicadas: las omitidas (sin el tipo de padron) pasan a Omitidos y las fallidas a Error
      " tecnico, igual que las altas.
      ls_alta-omitidos = ls_alta-omitidos + ls_baja-omitidos.
      ls_alta-errores  = ls_alta-errores + ls_baja-errores.
      " Altas omitidas (proveedor no ampliado a la sociedad): de Actualizados a Omitidos.
      IF ls_alta-omitidos > 0.
        UPDATE zarba_ret_ejec
          SET total_actualizados = total_actualizados - @ls_alta-omitidos,
              total_omitidos     = total_omitidos + @ls_alta-omitidos
          WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid
            AND total_actualizados >= @ls_alta-omitidos.
        COMMIT WORK.
      ENDIF.
      IF ls_alta-errores > 0.
        UPDATE zarba_ret_ejec SET estado_ejecucion = 'OK_CON_ERRORES'
          WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid AND estado_ejecucion = 'OK'.
        " Las altas fallidas quedaron 'ETE' en el log: se pasan de Actualizados a Error tecnico.
        UPDATE zarba_ret_ejec
          SET total_actualizados  = total_actualizados - @ls_alta-errores,
              total_error_tecnico = total_error_tecnico + @ls_alta-errores
          WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid
            AND total_actualizados >= @ls_alta-errores.
        COMMIT WORK.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD programar_ajuste_partidas.
    " La plantilla SAP_FIN_TAX_ADJUST_WHT no esta liberada para cl_apj_rt_api (C1): se programa por la API
    " de jobs externa (SAP_COM_0326, BC_EXT_APPJOB_MANAGEMENT) llamando al propio tenant con la misma
    " conexion de salida que el alta de retenciones (ZCS_ARBA_RET_BP_OUT). El job SAP corre con el usuario
    " que ejecuta el padron (JobUser = sy-uname: debe tener el rol de Cuentas a Pagar).
    CONSTANTS c_svc  TYPE string VALUE '/sap/opu/odata/sap/BC_EXT_APPJOB_MANAGEMENT;v=0002/'.
    CONSTANTS c_lote TYPE i VALUE 50.

    " La lista de proveedores viaja en la URL: con muchos (altas por region) se programa en lotes.
    IF lines( it_sup ) > c_lote.
      DATA lt_lote TYPE zcl_arba_ret_alta=>ty_sup_tt.
      DATA lv_n    TYPE i.
      LOOP AT it_sup INTO DATA(lv_s).
        lv_n += 1.
        APPEND lv_s TO lt_lote.
        IF lines( lt_lote ) = c_lote OR lv_n = lines( it_sup ).
          programar_ajuste_partidas( iv_uuid = iv_uuid iv_id_ejec = iv_id_ejec iv_sociedad = iv_sociedad
                                     it_sup = lt_lote iv_test = iv_test ).
          CLEAR lt_lote.
        ENDIF.
      ENDLOOP.
      RETURN.
    ENDIF.

    " Parametros de la plantilla (todos explicitos: sin TEST la plantilla queda en modo test por defecto).
    DATA(lv_lifnr) = ``.
    LOOP AT it_sup INTO DATA(lv_sup).
      lv_lifnr = |{ lv_lifnr }{ COND string( WHEN lv_lifnr IS NOT INITIAL THEN `,` ) }| &&
                 |\{"SIGN":"I","OPTION":"EQ","LOW":"{ lv_sup }","HIGH":""\}|.
    ENDLOOP.
    DATA(lv_test) = COND string( WHEN iv_test = abap_true THEN `X` ELSE `` ).
    DATA(lv_json) = |\{"VALUES":[| &&
      |\{"NAME":"VENDOR","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"X","HIGH":""\}]\},| &&
      |\{"NAME":"I_LIFNR","T_VALUE":[{ lv_lifnr }]\},| &&
      |\{"NAME":"CUSTOMER","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"","HIGH":""\}]\},| &&
      |\{"NAME":"I_BUKRS","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"{ iv_sociedad }","HIGH":""\}]\},| &&
      |\{"NAME":"NORMAL","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"X","HIGH":""\}]\},| &&
      |\{"NAME":"PARKED","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"","HIGH":""\}]\},| &&
      |\{"NAME":"RECURR","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"","HIGH":""\}]\},| &&
      |\{"NAME":"TEST","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"{ lv_test }","HIGH":""\}]\},| &&
      |\{"NAME":"DOWN_PAY","T_VALUE":[\{"SIGN":"I","OPTION":"EQ","LOW":"","HIGH":""\}]\}| &&
      |]\}|.
    DATA(lv_text) = |Ajuste partidas padron { iv_id_ejec }{ COND string( WHEN iv_test = abap_true THEN ` (test)` ) }|.

    DATA lv_msg     TYPE string.
    DATA lv_jobname TYPE zarba_ret_ejec-job_partidas.
    TRY.
        DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
                          comm_scenario = 'ZCS_ARBA_RET_BP_OUT'
                          service_id    = 'ZARBA_RET_BP_OUT_REST' ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
        DATA(lo_req) = lo_client->get_http_request( ).
        lo_req->set_header_field( i_name = 'Accept' i_value = 'application/json' ).

        " 1) Token CSRF (misma instancia de cliente -> conserva la sesion/cookies para el POST).
        lo_req->set_uri_path( i_uri_path = c_svc ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'Fetch' ).
        DATA(lv_token) = lo_client->execute( i_method = if_web_http_client=>get )->get_header_field( 'x-csrf-token' ).

        " 2) JobSchedule (function import: parametros en la query string, literales entre comillas simples).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = lv_token ).
        lo_req->set_uri_path( i_uri_path =
          |{ c_svc }JobSchedule?JobTemplateName='SAP_FIN_TAX_ADJUST_WHT'| &&
          |&JobText={ cl_web_http_utility=>escape_url( |'{ lv_text }'| ) }| &&
          |&JobUser='{ sy-uname }'&TestModeInd=false| &&
          |&JobParameterValues={ cl_web_http_utility=>escape_url( |'{ lv_json }'| ) }| ).
        DATA(lo_resp) = lo_client->execute( i_method = if_web_http_client=>post ).
        DATA(lv_code) = lo_resp->get_status( )-code.
        DATA(lv_body) = lo_resp->get_text( ).
        lo_client->close( ).

        IF lv_code >= 200 AND lv_code < 300.
          FIND FIRST OCCURRENCE OF PCRE `"JobName"\s*:\s*"([^"]*)"` IN lv_body SUBMATCHES DATA(lv_jn).
          lv_jobname = lv_jn.
          lv_msg = |Partidas: job de ajuste { COND string( WHEN iv_test = abap_true THEN `en modo test ` ) }programado ({ lv_jobname }).|.
        ELSE.
          FIND FIRST OCCURRENCE OF PCRE `"value"\s*:\s*"([^"]*)"` IN lv_body SUBMATCHES DATA(lv_err).
          lv_msg = |Partidas: no se pudo programar el job de ajuste (HTTP { lv_code }): { COND string( WHEN lv_err IS NOT INITIAL THEN lv_err ELSE lv_body ) }|.
        ENDIF.
      CATCH cx_root INTO DATA(lx).
        lv_msg = |Partidas: no se pudo programar el job de ajuste: { lx->get_text( ) }|.
    ENDTRY.

    " Con varios lotes queda el primer job (la ejecucion arranca con job_partidas vacio).
    UPDATE zarba_ret_ejec SET job_partidas = @lv_jobname
      WHERE ejecucion_uuid = @iv_uuid AND job_partidas = @space.
    " Nota del ajuste en las filas Caso 1 de esos proveedores (sin pasar el largo del campo).
    DATA lt_r_sup TYPE RANGE OF zarba_ret_log-proveedor.
    lt_r_sup = VALUE #( FOR x IN it_sup ( sign = 'I' option = 'EQ' low = x ) ).
    SELECT log_uuid, mensaje FROM zarba_ret_log
      WHERE ejecucion_uuid = @iv_uuid
        AND proveedor IN @lt_r_sup
        AND ( ( estado = 'ACT'
                AND ( caso = '1' OR caso = '4'
                      OR ( caso = '3' AND indicador_anterior = @space AND tipo_ret <> @space ) ) )
              OR estado = 'BAJ' )
      INTO TABLE @DATA(lt_rows).
    LOOP AT lt_rows INTO DATA(ls_r).
      DATA(lv_new) = zcl_arba_ret_alta=>cortar( |{ ls_r-mensaje } { lv_msg }| ).
      UPDATE zarba_ret_log SET mensaje = @lv_new WHERE log_uuid = @ls_r-log_uuid.
    ENDLOOP.
    COMMIT WORK.
  ENDMETHOD.


  METHOD procesar_padron.
    " Tucuman: motor propio (parseo por posicion fija + Acreditan/Coeficientes). No pasa por el
    " flujo de ARBA/CABA/SF; delega y sale, dejando ese flujo intacto.
    " Salta: motor propio (ZCL_ARBA_RET_SAL_PROC). Delega y sale; no toca ARBA/CABA/SF ni TUC.
    IF is_ejec-provincia = zcl_arba_ret_sal_param=>c_provincia.
      NEW zcl_arba_ret_sal_proc( )->procesar( is_ejec = is_ejec iv_simular = iv_simular ).
      RETURN.
    ENDIF.
" Entre Rios: motor propio
IF is_ejec-provincia = zcl_arba_ret_er_param=>c_provincia.
  NEW zcl_arba_ret_er_proc( )->procesar(
    is_ejec    = is_ejec
    iv_simular = iv_simular ).
  RETURN.
ENDIF.

    IF is_ejec-provincia = 'TUC'.
      NEW zcl_arba_ret_tuc_proc( )->procesar( is_ejec = is_ejec iv_simular = iv_simular ).
      RETURN.
    ENDIF.

    DATA(lo_proc)   = NEW zcl_arba_ret_proc_app( ).
    DATA(lo_parser) = NEW zcl_arba_ret_parser( ).
    lo_parser->set_provincia( is_ejec-provincia ).

    " 1) Precarga de caches (proveedores + indicadores). Una sola vez (EF seccion 12).
    lo_proc->preparar( iv_sociedad = is_ejec-sociedad iv_tipo_ret = is_ejec-tipo_retencion ).

    " 2) Archivo vacio -> FALLIDA
    IF xstrlen( is_ejec-archivo ) = 0.
      finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                 iv_simular = iv_simular iv_archivo = is_ejec-archivo iv_sociedad = is_ejec-sociedad ).
      RETURN.
    ENDIF.

    " ARBA/CABA generan el padron en ISO-8859-1 (Latin-1), NO UTF-8: nombres con Ñ/acentos son bytes
    " invalidos como UTF-8 y hacian dump CONVT_CODEPAGE. ISO-8859-1 mapea los 256 bytes (nunca falla)
    " y las columnas que usa el RAP (CUIT/alicuota/fechas) son ASCII -> se leen bien igual.
    DATA(lv_text) = cl_abap_conv_codepage=>create_in( codepage = 'ISO-8859-1' )->convert( source = is_ejec-archivo ).
    DATA(lv_len)  = strlen( lv_text ).

    " 3) PASE 1: mapa de deduplicacion por CUIT + conteo de lineas
    DATA lt_cuit_info TYPE zcl_arba_ret_proc_app=>ty_cuit_info_tt.
    DATA lv_off    TYPE i.
    DATA lv_leidos TYPE i.
    WHILE lv_off < lv_len.
      DATA(lv_line) = siguiente_linea( EXPORTING iv_text = lv_text CHANGING cv_off = lv_off ).
      IF lv_line IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_leidos += 1.
      lo_proc->acumular_cuit_info(
        EXPORTING is_record    = lo_parser->parse_line( iv_line = lv_line iv_nro_linea = lv_leidos )
        CHANGING  ct_cuit_info = lt_cuit_info ).
    ENDWHILE.

    IF lv_leidos = 0.
      finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                 iv_simular = iv_simular iv_archivo = is_ejec-archivo iv_sociedad = is_ejec-sociedad ).
      RETURN.
    ENDIF.

    " 4) PASE 2: procesar por lotes de c_batch_size con COMMIT por lote
    DATA ls_kpi TYPE zcl_arba_ret_proc_app=>ty_kpi.
    ls_kpi-leidos = lv_leidos.
    DATA(lv_universo) = lo_proc->universo_esperado(
                          iv_provincia = is_ejec-provincia iv_tipo_ret = is_ejec-tipo_retencion ).
    DATA lt_hechos        TYPE zcl_arba_ret_proc_app=>ty_cuit_set.
    DATA lt_otro_universo TYPE zcl_arba_ret_proc_app=>ty_cuit_set.
    DATA lt_sup_proc      TYPE zcl_arba_ret_proc_app=>ty_sup_set.
    DATA lt_batch         TYPE zcl_arba_ret_parser=>ty_record_tt.
    DATA lv_nro           TYPE i.

    lv_off = 0.
    WHILE lv_off < lv_len.
      lv_line = siguiente_linea( EXPORTING iv_text = lv_text CHANGING cv_off = lv_off ).
      IF lv_line IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_nro += 1.
      APPEND lo_parser->parse_line( iv_line = lv_line iv_nro_linea = lv_nro ) TO lt_batch.
      IF lines( lt_batch ) >= c_batch_size.
        procesar_lote( EXPORTING io_proc = lo_proc is_ejec = is_ejec it_cuit_info = lt_cuit_info
                                 iv_simular = iv_simular iv_universo = lv_universo
                       CHANGING  ct_hechos = lt_hechos ct_otro_universo = lt_otro_universo
                                 cs_kpi = ls_kpi ct_batch = lt_batch ct_sup_proc = lt_sup_proc ).
      ENDIF.
    ENDWHILE.
    " ultimo lote parcial
    IF lt_batch IS NOT INITIAL.
      procesar_lote( EXPORTING io_proc = lo_proc is_ejec = is_ejec it_cuit_info = lt_cuit_info
                               iv_simular = iv_simular iv_universo = lv_universo
                     CHANGING  ct_hechos = lt_hechos ct_otro_universo = lt_otro_universo
                               cs_kpi = ls_kpi ct_batch = lt_batch ct_sup_proc = lt_sup_proc ).
    ENDIF.

    " 5) Sincronizacion completa (EF 6.3): Caso 3 fuera de padron
    IF is_ejec-actualizar_solo_padron = abap_false.
      DATA lt_log_fuera TYPE zcl_arba_ret_proc_app=>ty_log_tt.
      lo_proc->procesar_fuera_padron(
        EXPORTING iv_sociedad       = is_ejec-sociedad
                  iv_tipo_ret       = is_ejec-tipo_retencion
                  iv_ind_fuera      = is_ejec-indicador_fuera_padron
                  iv_prov_desde     = is_ejec-prov_desde
                  iv_prov_hasta     = is_ejec-prov_hasta
                  iv_simular        = iv_simular
                  it_sup_procesados = lt_sup_proc
                  iv_provincia      = is_ejec-provincia
                  iv_solo_con_ret   = is_ejec-solo_con_retencion
                  it_cuit_archivo   = lt_cuit_info
                  it_otro_universo  = lt_otro_universo
        CHANGING  ct_log            = lt_log_fuera
                  cs_kpi            = ls_kpi ).
      persistir_log( iv_uuid = is_ejec-ejecucion_uuid it_log = lt_log_fuera ).
    ENDIF.

    " 6) Cierre: estado final + KPIs + ajuste de partidas
    DATA(lv_estado) = COND zcl_arba_ret_proc_app=>ty_estado_ejec(
      WHEN ls_kpi-error_tecnico > 0 THEN 'OK_CON_ERRORES' ELSE 'OK' ).
    finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = lv_estado is_kpi = ls_kpi
               iv_simular = iv_simular iv_archivo = is_ejec-archivo iv_sociedad = is_ejec-sociedad
               iv_prov_desde = is_ejec-prov_desde iv_prov_hasta = is_ejec-prov_hasta ).
  ENDMETHOD.


  METHOD procesar_lote.
    DATA lt_log TYPE zcl_arba_ret_proc_app=>ty_log_tt.
    io_proc->procesar_registros(
      EXPORTING it_records      = ct_batch
                it_cuit_info    = it_cuit_info
                iv_sociedad     = is_ejec-sociedad
                iv_tipo_ret     = is_ejec-tipo_retencion
                iv_prov_desde   = is_ejec-prov_desde
                iv_prov_hasta   = is_ejec-prov_hasta
                iv_solo_con_ret = is_ejec-solo_con_retencion
                iv_simular      = iv_simular
                iv_universo     = iv_universo
      CHANGING  ct_hechos        = ct_hechos
                ct_otro_universo = ct_otro_universo
                ct_log           = lt_log
                cs_kpi           = cs_kpi ).

    " Acumula los proveedores tratados desde el padron. El log se persiste y se descarta por
    " lote, pero este set debe SOBREVIVIR entre lotes para excluir a esos proveedores del
    " recorrido "fuera de padron" (Caso 3). Set acotado (~proveedores del universo).
    LOOP AT lt_log INTO DATA(ls_log) WHERE proveedor IS NOT INITIAL.
      INSERT ls_log-proveedor INTO TABLE ct_sup_proc.
    ENDLOOP.

    persistir_log( iv_uuid = is_ejec-ejecucion_uuid it_log = lt_log ).
    CLEAR ct_batch.   " liberar estructuras temporales del lote
  ENDMETHOD.


  METHOD siguiente_linea.
    DATA(lv_len) = strlen( iv_text ).
    DATA(lv_pos) = find( val = iv_text sub = cl_abap_char_utilities=>newline off = cv_off ).
    IF lv_pos < 0.
      rv_line = substring( val = iv_text off = cv_off len = lv_len - cv_off ).
      cv_off  = lv_len.
    ELSE.
      rv_line = substring( val = iv_text off = cv_off len = lv_pos - cv_off ).
      cv_off  = lv_pos + 1.
    ENDIF.
    " quitar CR final (archivos CRLF de ARBA)
    rv_line = replace( val = rv_line regex = `\r` with = `` occ = 0 ).
  ENDMETHOD.


  METHOD persistir_log.
    IF it_log IS INITIAL.
      RETURN.
    ENDIF.

    " Persistencia DIRECTA (proceso de fondo): INSERT masivo + COMMIT por lote.
    " No se usa EML porque los campos calculados del root son readonly (y "IN LOCAL MODE"
    " solo existe dentro de un handler); ademas el volumen (EF seccion 12) exige insercion
    " masiva eficiente. El log_uuid se genera aqui (numeracion no gestionada por RAP).
    GET TIME STAMP FIELD DATA(lv_now).
    DATA lt_db TYPE STANDARD TABLE OF zarba_ret_log.
    TRY.
        " Redmine 33756 (13/10): las filas NOE (CUIT del archivo sin proveedor en SAP) no se graban:
        " no le sirven al usuario y llenaban el Log de Auditoria. Quedan contadas en Total No Encontrados.
        LOOP AT it_log INTO DATA(ls_log) WHERE estado <> 'NOE'.
          APPEND VALUE #(
            ejecucion_uuid      = iv_uuid
            log_uuid            = cl_system_uuid=>create_uuid_x16_static( )
            nro_linea           = ls_log-nro_linea
            cuit                = ls_log-cuit
            proveedor           = ls_log-proveedor
            caso                = ls_log-caso
            tipo_ret            = ls_log-tipo_ret
            indicador_anterior  = ls_log-indicador_anterior
            indicador_nuevo     = ls_log-indicador_nuevo
            alicuota_anterior   = ls_log-alicuota_anterior
            alicuota_nueva      = ls_log-alicuota_nueva
            sujeto_ret_anterior = ls_log-sujeto_ret_anterior
            sujeto_ret_nuevo    = ls_log-sujeto_ret_nuevo
            estado              = ls_log-estado
            mensaje             = ls_log-mensaje
            estado_tecnico      = ls_log-estado_tecnico
            tipo_contribuyente  = ls_log-tipo_contribuyente
            marca_alta_baja     = ls_log-marca_alta_baja
            marca_cambio_alic   = ls_log-marca_cambio_alic
            nro_grupo           = ls_log-nro_grupo
            fecha_publicacion   = ls_log-fecha_publicacion
            vigencia_desde      = ls_log-vigencia_desde
            vigencia_hasta      = ls_log-vigencia_hasta
            last_changed_at     = lv_now ) TO lt_db.
        ENDLOOP.
      CATCH cx_uuid_error.
        RETURN.
    ENDTRY.

    INSERT zarba_ret_log FROM TABLE @lt_db.
    COMMIT WORK.
  ENDMETHOD.


  METHOD finalizar.
    " EF 6.5 (ajuste de partidas abiertas): se hace con la app estandar "Update Withholding Tax
    " Codes and Open Items" (+ BAdI ZCL_ARBA_RET_BADI_TAXCODE), NO desde el job. Aca no se
    " planifica nada ni se deja nota en el log.
    DATA lv_job_partidas TYPE c LENGTH 32.

    " Cierre por SQL directo (mismo motivo que persistir_log: campos calculados readonly).
    GET TIME STAMP FIELD DATA(lv_now).
    " EF: el archivo no se almacena tras la ejecucion real
    DATA(lv_archivo) = COND xstring( WHEN iv_simular = abap_true THEN iv_archivo ELSE VALUE #( ) ).
    DATA(lv_size)    = xstrlen( iv_archivo ).

    UPDATE zarba_ret_ejec
      SET estado_ejecucion       = @iv_estado,
          modo_simulacion        = @iv_simular,
          archivo                = @lv_archivo,
          tamanio_archivo        = @lv_size,
          total_leidos           = @is_kpi-leidos,
          total_actualizados     = @is_kpi-actualizados,
          total_sin_cambios      = @is_kpi-sin_cambios,
          total_no_encontrados   = @is_kpi-no_encontrados,
          total_rechazados       = @is_kpi-rechazados,
          total_error_tecnico    = @is_kpi-error_tecnico,
          total_pendiente_config = @is_kpi-pendiente_config,
          total_omitidos         = @is_kpi-omitidos,
          job_partidas           = @lv_job_partidas,
          last_changed_at        = @lv_now
      WHERE ejecucion_uuid = @iv_uuid.
    COMMIT WORK.
  ENDMETHOD.
ENDCLASS.
