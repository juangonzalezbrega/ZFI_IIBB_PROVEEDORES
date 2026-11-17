CLASS zcl_arba_ret_alta DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_sup_tt TYPE STANDARD TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH EMPTY KEY.
    TYPES: BEGIN OF ty_result,
             altas_ok       TYPE i,
             errores        TYPE i,
             omitidos       TYPE i,   " no ampliados a la sociedad (no se puede crear)
             mensaje        TYPE string,
             proveedores_ok TYPE ty_sup_tt,   " dados de alta OK (para el ajuste de partidas)
             bajas_ok       TYPE i,           " bajas del tipo aplicadas (aplicar_bajas)
           END OF ty_result.

    "! Recorta un texto al largo del campo mensaje del log (char 255). Un texto mas largo en el UPDATE
    "! cancela el job (SAPSQL_DATA_LOSS).
    CLASS-METHODS cortar
      IMPORTING iv_txt        TYPE string
      RETURNING VALUE(rv_txt) TYPE string.

    "! Crea por API el registro de retencion de las filas Caso 1 (estado 'ACT') de una ejecucion y deja
    "! el resultado por fila en el log. Devuelve los contadores para que el caller marque el estado.
    METHODS aplicar
      IMPORTING iv_ejecucion_uuid TYPE sysuuid_x16
      RETURNING VALUE(rs_result)  TYPE ty_result.

    "! Borra por API el registro de retencion de las filas de baja (estado 'BAJ'; Tucuman, Redmine 33748
    "! nota #57) y deja el resultado por fila. Antes de borrar un tipo distinto del de padron verifica que el
    "! proveedor tenga el tipo de padron en el maestro: si no, quedaria sin ningun tipo (alta fallida u
    "! omitida) y la baja no se aplica. Las partidas de los proveedores OK las ajusta el job del caller.
    METHODS aplicar_bajas
      IMPORTING iv_ejecucion_uuid TYPE sysuuid_x16
      RETURNING VALUE(rs_result)  TYPE ty_result.

  PRIVATE SECTION.
    " --- Config de la llamada (mismo Communication Arrangement de escritura BP que las exenciones) ---
    CONSTANTS c_comm_scenario TYPE c LENGTH 30 VALUE 'ZCS_ARBA_RET_BP_OUT'.
    CONSTANTS c_service_id    TYPE c LENGTH 40 VALUE 'ZARBA_RET_BP_OUT_REST'.
    CONSTANTS c_base_path     TYPE string VALUE '/sap/opu/odata/sap/API_BUSINESS_PARTNER'.
    CONSTANTS c_entity        TYPE string VALUE 'A_SupplierWithHoldingTax'.

    DATA mo_client TYPE REF TO if_web_http_client.
    DATA mv_token  TYPE string.

    METHODS abrir_conexion RAISING cx_static_check.
    METHODS csrf_token     RETURNING VALUE(rv_token) TYPE string RAISING cx_static_check.

    "! POST (create OData V2) del registro de retencion. Devuelve ok + el detalle (para el log de errores).
    METHODS crear_entidad
      IMPORTING iv_supplier   TYPE c
                iv_sociedad   TYPE c
                iv_tipo       TYPE c
                iv_codigo     TYPE c
                iv_es_sujeto  TYPE abap_boolean
      EXPORTING ev_ok         TYPE abap_boolean
                ev_detalle    TYPE string
      RAISING   cx_static_check.

    "! DELETE (OData V2) del registro de retencion por clave. ev_ok solo si el registro ya no esta en el
    "! maestro despues del DELETE (un 2xx no garantiza el borrado). 404 = ya no existia = OK.
    METHODS borrar_entidad
      IMPORTING iv_supplier TYPE zcl_arba_ret_bp_updater=>ty_supplier
                iv_sociedad TYPE bukrs
                iv_tipo     TYPE zarba_ret_log-tipo_ret
      EXPORTING ev_ok       TYPE abap_boolean
                ev_detalle  TYPE string
      RAISING   cx_static_check.

    METHODS escapar
      IMPORTING iv_in     TYPE c
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_ALTA IMPLEMENTATION.


  METHOD aplicar.
    " 1) Cabecera de la ejecucion: sociedad + tipo de retencion (el tipo de padron por defecto).
    SELECT SINGLE sociedad, tipo_retencion
      FROM zarba_ret_ejec
      WHERE ejecucion_uuid = @iv_ejecucion_uuid
      INTO @DATA(ls_ejec).
    IF sy-subrc <> 0.
      rs_result-mensaje = 'No se encontro la ejecucion.'.
      RETURN.
    ENDIF.

    " 2) Filas de ALTA con estado 'ACT' y proveedor. tipo_ret por fila (Tucuman 24/TN); vacio en
    "    el resto -> se usa el tipo de padron de la ejecucion (mismo fallback que la BAdI). Son altas:
    "    - Caso 1: proveedor del archivo sin el tipo.
    "    - Caso 4: fuera de padron por REGION sin el tipo (ARBA/CABA/SF; Redmine 33756, 05/10).
    "    - Caso 3 de Tucuman sin indicador anterior: candidato por region 14 sin el tipo TN (lo arma
    "      ZCL_ARBA_RET_TUC_PROC con tipo_ret informado; el resto de los Caso 3 ya tienen el tipo).
    SELECT log_uuid, proveedor, caso, tipo_ret, indicador_nuevo, sujeto_ret_nuevo
      FROM zarba_ret_log
      WHERE ejecucion_uuid    = @iv_ejecucion_uuid
        AND ( caso = '1' OR caso = '4'
              OR ( caso = '3' AND indicador_anterior = @space AND tipo_ret <> @space ) )
        AND estado            = 'ACT'
        AND proveedor        <> @space
        AND indicador_nuevo  <> @space
      INTO TABLE @DATA(lt_rows).
    IF lt_rows IS INITIAL.
      rs_result-mensaje = 'No hay altas (Caso 1) para aplicar en esta ejecucion.'.
      RETURN.
    ENDIF.

    " 3) Abrir conexion y obtener token CSRF una vez.
    TRY.
        abrir_conexion( ).
        mv_token = csrf_token( ).
      CATCH cx_root INTO DATA(lx_conn).
        rs_result-errores = lines( lt_rows ).
        rs_result-mensaje = cortar( |No se pudo abrir la conexion a la API BP: { lx_conn->get_text( ) }| ).
        " Sin conexion, ninguna alta se aplico: cada fila pasa a 'ETE' (error tecnico, rojo) para que el
        " log NO la muestre como actualizada. Queda fuera del export (ACT/SCB/PCF): aun no es titular.
        UPDATE zarba_ret_log
          SET mensaje        = @rs_result-mensaje,
              estado         = 'ETE',
              estado_tecnico = 'X'
          WHERE ejecucion_uuid = @iv_ejecucion_uuid AND estado = 'ACT'
            AND ( caso = '1' OR caso = '4'
              OR ( caso = '3' AND indicador_anterior = @space AND tipo_ret <> @space ) )
            AND proveedor <> @space AND indicador_nuevo <> @space.
        COMMIT WORK.
        RETURN.
    ENDTRY.

    " 4) Crear fila por fila y dejar el resultado en el log.
    LOOP AT lt_rows INTO DATA(ls).
      DATA(lv_tipo) = COND #( WHEN ls-tipo_ret IS NOT INITIAL THEN ls-tipo_ret ELSE ls_ejec-tipo_retencion ).
      DATA lv_ok      TYPE abap_boolean.
      DATA lv_detalle TYPE string.
      DATA lv_msg     TYPE string.

      " Idempotente: si el proveedor YA tiene el tipo (p. ej. alta previa o cargado a mano), no se vuelve a
      " crear (la API daria error y la fila saldria del export -> la estandar le borraria el tipo).
      SELECT SINGLE @abap_true FROM i_supplierwithholdingtax
        WHERE supplier = @ls-proveedor AND companycode = @ls_ejec-sociedad AND withholdingtaxtype = @lv_tipo
        INTO @DATA(lv_ya_existe).
      IF sy-subrc = 0 AND lv_ya_existe = abap_true.
        " Tucuman (Caso 3 por region): titular TN con indicador vacio -> no es un alta, se deja como esta.
        IF ls-caso = '3'.
          CONTINUE.
        ENDIF.
        rs_result-altas_ok = rs_result-altas_ok + 1.
        APPEND ls-proveedor TO rs_result-proveedores_ok.
        lv_msg = cortar( |Retencion tipo { lv_tipo } ya existente en el maestro: no se crea.| ).
        UPDATE zarba_ret_log SET mensaje = @lv_msg WHERE log_uuid = @ls-log_uuid.
        CONTINUE.
      ENDIF.

      " Sin datos en la sociedad la API rechaza el alta: se omite (no es error). Cubre los candidatos por
      " region de Tucuman, que su motor no filtra por sociedad.
      SELECT SINGLE @abap_true FROM i_suppliercompany
        WHERE supplier = @ls-proveedor AND companycode = @ls_ejec-sociedad
        INTO @DATA(lv_ampliado).
      IF sy-subrc <> 0 OR lv_ampliado = abap_false.
        rs_result-omitidos = rs_result-omitidos + 1.
        lv_msg = cortar( |Omitido: proveedor no ampliado a la sociedad { ls_ejec-sociedad } (no se puede dar de alta la retencion)| ).
        UPDATE zarba_ret_log SET mensaje = @lv_msg, estado = 'OMI' WHERE log_uuid = @ls-log_uuid.
        CONTINUE.
      ENDIF.

      TRY.
          crear_entidad(
            EXPORTING iv_supplier  = ls-proveedor
                      iv_sociedad  = ls_ejec-sociedad
                      iv_tipo      = lv_tipo
                      iv_codigo    = ls-indicador_nuevo
                      iv_es_sujeto = xsdbool( ls-sujeto_ret_nuevo = 'X' )
            IMPORTING ev_ok        = lv_ok
                      ev_detalle   = lv_detalle ).
        CATCH cx_root INTO DATA(lx).
          lv_ok      = abap_false.
          lv_detalle = lx->get_text( ).
      ENDTRY.

      IF lv_ok = abap_true.
        rs_result-altas_ok = rs_result-altas_ok + 1.
        APPEND ls-proveedor TO rs_result-proveedores_ok.
        lv_msg = |Alta de retencion creada en el maestro (API, tipo { lv_tipo } codigo { ls-indicador_nuevo }).|.
      ELSE.
        rs_result-errores = rs_result-errores + 1.
        lv_msg = |Alta de retencion NO aplicada (API): { lv_detalle }|.
      ENDIF.
      lv_msg = cortar( lv_msg ).

      IF lv_ok = abap_true.
        UPDATE zarba_ret_log SET mensaje = @lv_msg WHERE log_uuid = @ls-log_uuid.
      ELSE.
        " Alta rechazada por la API: 'ETE' (rojo) en lugar de 'ACT' (verde), igual que sin conexion.
        UPDATE zarba_ret_log
          SET mensaje        = @lv_msg,
              estado         = 'ETE',
              estado_tecnico = 'X'
          WHERE log_uuid = @ls-log_uuid.
      ENDIF.
    ENDLOOP.

    IF mo_client IS BOUND.
      TRY.
          mo_client->close( ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
    ENDIF.

    COMMIT WORK.

    rs_result-mensaje = |Altas creadas: { rs_result-altas_ok } Errores: { rs_result-errores }|.
  ENDMETHOD.


  METHOD cortar.
    rv_txt = COND #( WHEN strlen( iv_txt ) > 255 THEN substring( val = iv_txt off = 0 len = 255 ) ELSE iv_txt ).
  ENDMETHOD.


  METHOD abrir_conexion.
    DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
                      comm_scenario = c_comm_scenario
                      service_id    = c_service_id ).
    mo_client = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).
  ENDMETHOD.


  METHOD csrf_token.
    DATA(lo_req) = mo_client->get_http_request( ).
    lo_req->set_uri_path( i_uri_path = |{ c_base_path }/| ).
    lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'Fetch' ).
    DATA(lo_resp) = mo_client->execute( i_method = if_web_http_client=>get ).
    rv_token = lo_resp->get_header_field( 'x-csrf-token' ).
  ENDMETHOD.


  METHOD crear_entidad.
    CLEAR: ev_ok, ev_detalle.

    DATA(lv_subject) = COND string( WHEN iv_es_sujeto = abap_true THEN 'true' ELSE 'false' ).
    DATA(lv_body) = |\{ "Supplier":"{ escapar( iv_supplier ) }",|
                 && |"CompanyCode":"{ escapar( iv_sociedad ) }",|
                 && |"WithholdingTaxType":"{ escapar( iv_tipo ) }",|
                 && |"WithholdingTaxCode":"{ escapar( iv_codigo ) }",|
                 && |"IsWithholdingTaxSubject":{ lv_subject } \}|.

    " POST al entity SET (sin clave) = create en OData V2.
    DATA(lo_req) = mo_client->get_http_request( ).
    lo_req->set_uri_path( i_uri_path = |{ c_base_path }/{ c_entity }| ).
    lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = mv_token ).
    lo_req->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
    lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
    lo_req->set_text( i_text = lv_body ).

    DATA(lo_resp) = mo_client->execute( i_method = if_web_http_client=>post ).
    DATA(lv_code) = lo_resp->get_status( )-code.
    " 201 = created (caso normal). Se toleran otros 2xx por robustez.
    ev_ok = xsdbool( lv_code >= 200 AND lv_code < 300 ).
    IF ev_ok = abap_false.
      DATA(lv_txt) = lo_resp->get_text( ).
      " Texto del error de la API (ej. proveedor bloqueado por otro usuario) en lugar del JSON crudo:
      " la solapa "Errores" lo agrupa y reconoce el bloqueo por este texto (Redmine 33756, 07/10).
      FIND FIRST OCCURRENCE OF PCRE `"value"\s*:\s*"([^"]*)"` IN lv_txt SUBMATCHES DATA(lv_err).
      IF lv_err IS NOT INITIAL.
        lv_txt = lv_err.
      ENDIF.
      ev_detalle = |HTTP { lv_code }: { COND #( WHEN strlen( lv_txt ) > 300
                                                THEN substring( val = lv_txt off = 0 len = 300 ) ELSE lv_txt ) }|.
    ENDIF.
  ENDMETHOD.


  METHOD aplicar_bajas.
    SELECT SINGLE sociedad, tipo_retencion
      FROM zarba_ret_ejec
      WHERE ejecucion_uuid = @iv_ejecucion_uuid
      INTO @DATA(ls_ejec).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SELECT log_uuid, proveedor, tipo_ret
      FROM zarba_ret_log
      WHERE ejecucion_uuid = @iv_ejecucion_uuid
        AND estado         = 'BAJ'
        AND proveedor     <> @space
        AND tipo_ret      <> @space
      INTO TABLE @DATA(lt_rows).
    IF lt_rows IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        abrir_conexion( ).
        mv_token = csrf_token( ).
      CATCH cx_root INTO DATA(lx_conn).
        rs_result-errores = lines( lt_rows ).
        rs_result-mensaje = cortar( |Baja del tipo NO aplicada: no se pudo abrir la conexion a la API BP: { lx_conn->get_text( ) }| ).
        UPDATE zarba_ret_log
          SET mensaje        = @rs_result-mensaje,
              estado         = 'ETE',
              estado_tecnico = 'X'
          WHERE ejecucion_uuid = @iv_ejecucion_uuid AND estado = 'BAJ'.
        COMMIT WORK.
        RETURN.
    ENDTRY.

    LOOP AT lt_rows INTO DATA(ls).
      DATA lv_ok      TYPE abap_boolean.
      DATA lv_detalle TYPE string.
      DATA lv_msg     TYPE string.
      CLEAR: lv_ok, lv_detalle, lv_msg.

      " Idempotente: si ya no tiene el tipo (borrado antes, a mano o por la estandar), no hay nada que borrar.
      SELECT SINGLE @abap_true FROM i_supplierwithholdingtax
        WHERE supplier = @ls-proveedor AND companycode = @ls_ejec-sociedad AND withholdingtaxtype = @ls-tipo_ret
        INTO @DATA(lv_tiene).
      IF sy-subrc <> 0 OR lv_tiene = abap_false.
        rs_result-bajas_ok = rs_result-bajas_ok + 1.
        lv_msg = cortar( |Baja del tipo { ls-tipo_ret }: el proveedor ya no tenia el tipo en el maestro.| ).
        UPDATE zarba_ret_log SET mensaje = @lv_msg WHERE log_uuid = @ls-log_uuid.
        CONTINUE.
      ENDIF.

      " Sin el tipo de padron en el maestro (su alta fallo o se omitio) no se le saca el otro tipo.
      IF ls-tipo_ret <> ls_ejec-tipo_retencion.
        SELECT SINGLE @abap_true FROM i_supplierwithholdingtax
          WHERE supplier = @ls-proveedor AND companycode = @ls_ejec-sociedad
            AND withholdingtaxtype = @ls_ejec-tipo_retencion
          INTO @DATA(lv_tiene_padron).
        IF sy-subrc <> 0 OR lv_tiene_padron = abap_false.
          rs_result-omitidos = rs_result-omitidos + 1.
          lv_msg = cortar( |Baja del tipo { ls-tipo_ret } NO aplicada: el proveedor no tiene el tipo { ls_ejec-tipo_retencion } en el maestro (quedaria sin ningun tipo).| ).
          UPDATE zarba_ret_log SET mensaje = @lv_msg, estado = 'OMI' WHERE log_uuid = @ls-log_uuid.
          CONTINUE.
        ENDIF.
      ENDIF.

      TRY.
          borrar_entidad( EXPORTING iv_supplier = ls-proveedor
                                    iv_sociedad = ls_ejec-sociedad
                                    iv_tipo     = ls-tipo_ret
                          IMPORTING ev_ok       = lv_ok
                                    ev_detalle  = lv_detalle ).
        CATCH cx_root INTO DATA(lx).
          lv_ok      = abap_false.
          lv_detalle = lx->get_text( ).
      ENDTRY.

      IF lv_ok = abap_true.
        rs_result-bajas_ok = rs_result-bajas_ok + 1.
        APPEND ls-proveedor TO rs_result-proveedores_ok.
        lv_msg = cortar( |Baja del tipo { ls-tipo_ret } aplicada en el maestro (API).| ).
        UPDATE zarba_ret_log SET mensaje = @lv_msg WHERE log_uuid = @ls-log_uuid.
      ELSE.
        rs_result-errores = rs_result-errores + 1.
        lv_msg = cortar( |Baja del tipo { ls-tipo_ret } NO aplicada (API): { lv_detalle }| ).
        UPDATE zarba_ret_log
          SET mensaje        = @lv_msg,
              estado         = 'ETE',
              estado_tecnico = 'X'
          WHERE log_uuid = @ls-log_uuid.
      ENDIF.
    ENDLOOP.

    IF mo_client IS BOUND.
      TRY.
          mo_client->close( ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
    ENDIF.

    COMMIT WORK.

    rs_result-mensaje = |Bajas aplicadas: { rs_result-bajas_ok } Errores: { rs_result-errores } Omitidas: { rs_result-omitidos }|.
  ENDMETHOD.


  METHOD borrar_entidad.
    CLEAR: ev_ok, ev_detalle.

    DATA(lo_req) = mo_client->get_http_request( ).
    lo_req->set_uri_path( i_uri_path = |{ c_base_path }/{ c_entity }(Supplier='{ escapar( iv_supplier ) }',| &&
                                       |CompanyCode='{ escapar( iv_sociedad ) }',WithholdingTaxType='{ escapar( iv_tipo ) }')| ).
    lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = mv_token ).
    lo_req->set_header_field( i_name = 'If-Match'     i_value = '*' ).
    lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
    lo_req->set_text( i_text = `` ).

    DATA(lo_resp) = mo_client->execute( i_method = if_web_http_client=>delete ).
    DATA(lv_code) = lo_resp->get_status( )-code.

    IF ( lv_code >= 200 AND lv_code < 300 ) OR lv_code = 404.
      " Verificacion: el registro ya no tiene que estar en el maestro.
      SELECT SINGLE @abap_true FROM i_supplierwithholdingtax
        WHERE supplier = @iv_supplier AND companycode = @iv_sociedad AND withholdingtaxtype = @iv_tipo
        INTO @DATA(lv_sigue).
      IF sy-subrc <> 0 OR lv_sigue = abap_false.
        ev_ok = abap_true.
        RETURN.
      ENDIF.
      ev_detalle = |El DELETE respondio HTTP { lv_code } pero el registro sigue en el maestro.|.
      RETURN.
    ENDIF.

    DATA(lv_txt) = lo_resp->get_text( ).
    FIND FIRST OCCURRENCE OF PCRE `"value"\s*:\s*"([^"]*)"` IN lv_txt SUBMATCHES DATA(lv_err).
    IF lv_err IS NOT INITIAL.
      lv_txt = lv_err.
    ENDIF.
    ev_detalle = |HTTP { lv_code }: { COND #( WHEN strlen( lv_txt ) > 300
                                              THEN substring( val = lv_txt off = 0 len = 300 ) ELSE lv_txt ) }|.
  ENDMETHOD.


  METHOD escapar.
    " Comilla doble y backslash en el valor JSON se escapan; se recorta el valor.
    DATA(lv) = condense( CONV string( iv_in ) ).
    lv = replace( val = lv sub = `\` with = `\\` occ = 0 ).
    lv = replace( val = lv sub = `"` with = `\"` occ = 0 ).
    rv = lv.
  ENDMETHOD.
ENDCLASS.
