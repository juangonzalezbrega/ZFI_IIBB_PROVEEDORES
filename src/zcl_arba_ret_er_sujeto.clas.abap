"! Entre Rios: aplica por API (API_BUSINESS_PARTNER, A_SupplierWithHoldingTax) el flag "sujeto a retencion"
"! que la app estandar no toca: destildar (marca B, caso 'X') y tildar (marca A/S/N titular con el flag
"! destildado, caso '2'). Lee el log de una ejecucion REAL y deja el resultado en el mensaje de cada fila
"! ("APLICADO: ..." / "NO APLICADO: ..." -> solapa Errores, zi_arba_ret_err_r.ddls:43-44).
"! Copia de ZCL_ARBA_RET_TUC_EXENCION (zcl_arba_ret_tuc_exencion.clas.abap) sin la rama de exencion, con
"! body true/false, control de token vacio, re-lectura previa del maestro, idempotencia y solo sobre la
"! corrida real mas reciente de la sociedad + tipo (la misma que usa la BAdI). Mismo
"! Communication Arrangement que ALTA y EXENCION (ZCS_ARBA_RET_BP_OUT / ZARBA_RET_BP_OUT_REST).
"! Se llama desde la accion AplicarExenciones (despacho por provincia en ZBP_I_ARBA_RET_EJECUCION).
CLASS zcl_arba_ret_er_sujeto DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_result,
             tildes_ok    TYPE i,
             destildes_ok TYPE i,
             sin_cambio   TYPE i,
             errores      TYPE i,
             mensaje      TYPE string,
           END OF ty_result.

    METHODS aplicar
      IMPORTING iv_ejecucion_uuid TYPE sysuuid_x16
      RETURNING VALUE(rs_result)  TYPE ty_result.

  PRIVATE SECTION.
    CONSTANTS c_comm_scenario TYPE c LENGTH 30 VALUE 'ZCS_ARBA_RET_BP_OUT'.
    CONSTANTS c_service_id    TYPE c LENGTH 40 VALUE 'ZARBA_RET_BP_OUT_REST'.
    CONSTANTS c_base_path     TYPE string VALUE '/sap/opu/odata/sap/API_BUSINESS_PARTNER'.
    CONSTANTS c_entity        TYPE string VALUE 'A_SupplierWithHoldingTax'.
    CONSTANTS c_fld_subject   TYPE string VALUE 'IsWithholdingTaxSubject'.

    DATA mo_client TYPE REF TO if_web_http_client.
    DATA mv_token  TYPE string.

    METHODS abrir_conexion RAISING cx_static_check.
    METHODS csrf_token     RETURNING VALUE(rv_token) TYPE string RAISING cx_static_check.

    METHODS patch_entidad
      IMPORTING iv_supplier  TYPE c
                iv_sociedad  TYPE c
                iv_tipo      TYPE c
                iv_body_json TYPE string
      EXPORTING ev_detalle   TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_boolean
      RAISING   cx_static_check.

    "! Quita un prefijo "APLICADO: ...maestro." / "NO APLICADO: ..." de un intento anterior.
    METHODS sin_prefijo
      IMPORTING iv_msg    TYPE string
      RETURNING VALUE(rv) TYPE string.

    METHODS escapar
      IMPORTING iv_in     TYPE c
      RETURNING VALUE(rv) TYPE string.

    METHODS cortar
      IMPORTING iv_txt    TYPE string
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_ER_SUJETO IMPLEMENTATION.


  METHOD aplicar.
    " 1) Cabecera: solo corridas REALES finalizadas (zcl_arba_ret_tuc_exencion.clas.abap:80-92).
    SELECT SINGLE sociedad, tipo_retencion, modo_simulacion, estado_ejecucion
      FROM zarba_ret_ejec
      WHERE ejecucion_uuid = @iv_ejecucion_uuid
      INTO @DATA(ls_ejec).
    IF sy-subrc <> 0.
      rs_result-mensaje = 'No se encontró la corrida.'.
      RETURN.
    ENDIF.
    IF ls_ejec-modo_simulacion = abap_true
    OR NOT ( ls_ejec-estado_ejecucion = 'OK' OR ls_ejec-estado_ejecucion = 'OK_CON_ERRORES' ).
      rs_result-mensaje = 'El sujeto a retención se aplica solo a una corrida ejecutada (botón Ejecutar), no a una simulación.'.
      RETURN.
    ENDIF.

    " 1b) Solo la corrida REAL mas reciente de la sociedad + tipo: es la que usa la BAdI para los codigos
    "     (mismo criterio, tipo de padron O de fuera de padron, zcl_arba_ret_badi_taxcode.clas.abap:64-72).
    "     Aplicar una corrida vieja volveria a tildar / destildar segun un padron anterior.
    SELECT ejecucion_uuid, id_ejecucion
      FROM zarba_ret_ejec
      WHERE sociedad         = @ls_ejec-sociedad
        AND ( tipo_retencion = @ls_ejec-tipo_retencion OR tipo_ret_fuera = @ls_ejec-tipo_retencion )
        AND modo_simulacion  = @abap_false
        AND estado_ejecucion IN ( 'OK', 'OK_CON_ERRORES' )
      ORDER BY fecha_hora DESCENDING
      INTO @DATA(ls_ultima)
      UP TO 1 ROWS.
    ENDSELECT.
    IF sy-subrc = 0 AND ls_ultima-ejecucion_uuid <> iv_ejecucion_uuid.
      rs_result-mensaje = |Hay una corrida real posterior para la sociedad { ls_ejec-sociedad } y el tipo { ls_ejec-tipo_retencion } | &&
                          |(ID { ls_ultima-id_ejecucion }): aplicar el sujeto a retención sobre esa.|.
      RETURN.
    ENDIF.

    " 2) Filas: ACT, caso 2 o X (no altas 1/4 ni fuera de padron 3) y con algo que cambiar en el flag.
    "    Caso 2 ACT y caso X solo se generan para titulares del tipo (ER_PROC reglas 6b y 10), aunque el
    "    titular tenga el codigo VACIO (zcl_arba_ret_alta.clas.abap:127): por eso no se filtra por
    "    indicador_anterior. El paso 3 controla que el registro siga existiendo en el maestro.
SELECT log_uuid, proveedor, caso, mensaje,
       sujeto_ret_anterior, sujeto_ret_nuevo
  FROM zarba_ret_log AS log
  WHERE log~ejecucion_uuid   =  @iv_ejecucion_uuid
    AND log~estado           =  'ACT'
    AND log~proveedor        <> @space
    AND log~caso             IN ( '2', 'X' )
    AND log~sujeto_ret_nuevo <> log~sujeto_ret_anterior
  INTO TABLE @DATA(lt_rows).

    IF lt_rows IS INITIAL.
      rs_result-mensaje = 'Esta corrida no tiene cambios de "sujeto a retención" para aplicar.'.
      RETURN.
    ENDIF.

    " 3) Flag actual en el maestro (re-lectura: la estandar pudo haber borrado el registro por ausencia).
    SELECT supplier, iswithholdingtaxsubject AS es_sujeto
      FROM i_supplierwithholdingtax
      WHERE companycode        = @ls_ejec-sociedad
        AND withholdingtaxtype = @ls_ejec-tipo_retencion
      INTO TABLE @DATA(lt_maestro).
    SORT lt_maestro BY supplier.

    " 4) Conexion + token una vez; token vacio = abortar (criterio de zcl_arba_ret_bp_updater.clas.abap:400-407).
    TRY.
        abrir_conexion( ).
        mv_token = csrf_token( ).
      CATCH cx_root INTO DATA(lx_conn).
        rs_result-errores = lines( lt_rows ).
        rs_result-mensaje = |No se pudo conectar con SAP para aplicar el sujeto a retención: { lx_conn->get_text( ) }|.
        RETURN.
    ENDTRY.
    IF mv_token IS INITIAL.
      rs_result-errores = lines( lt_rows ).
      rs_result-mensaje = 'No se obtuvo el token CSRF de API_BUSINESS_PARTNER (revisar el Communication Arrangement).'.
      RETURN.
    ENDIF.

    " 5) Fila por fila. Dentro de la accion RAP no se puede UPDATE/COMMIT directo: el mensaje va por EML
    "    (zcl_arba_ret_tuc_exencion.clas.abap:118-121, 180-187).
    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion\\Log.
    DATA lv_primer_error TYPE string.
    LOOP AT lt_rows INTO DATA(ls).
      DATA lv_ok      TYPE abap_boolean.
      DATA lv_detalle TYPE string.
      DATA lv_res     TYPE string.
      CLEAR: lv_ok, lv_detalle, lv_res.

      DATA(lv_tildar) = xsdbool( ls-sujeto_ret_nuevo = 'X' ).
      DATA(lv_accion) = COND string( WHEN lv_tildar = abap_true THEN `tildado` ELSE `destildado` ).

      READ TABLE lt_maestro INTO DATA(ls_m) WITH KEY supplier = ls-proveedor BINARY SEARCH.
      IF sy-subrc <> 0.
        rs_result-errores += 1.
        lv_res = |NO APLICADO: el proveedor ya no tiene la retencion { ls_ejec-tipo_retencion } en el maestro.|.
      ELSEIF xsdbool( ls_m-es_sujeto = abap_true ) = lv_tildar.
        rs_result-sin_cambio += 1.
        lv_res = |APLICADO: sin cambio (el maestro ya estaba { lv_accion }).|.
      ELSE.
        DATA(lv_body) = COND string( WHEN lv_tildar = abap_true THEN |\{ "{ c_fld_subject }": true \}|
                                                                 ELSE |\{ "{ c_fld_subject }": false \}| ).
        TRY.
            lv_ok = patch_entidad( EXPORTING iv_supplier  = ls-proveedor
                                             iv_sociedad  = ls_ejec-sociedad
                                             iv_tipo      = ls_ejec-tipo_retencion
                                             iv_body_json = lv_body
                                   IMPORTING ev_detalle   = lv_detalle ).
          CATCH cx_root INTO DATA(lx).
            lv_ok      = abap_false.
            lv_detalle = lx->get_text( ).
        ENDTRY.
        IF lv_ok = abap_true.
          IF lv_tildar = abap_true.
            rs_result-tildes_ok += 1.
          ELSE.
            rs_result-destildes_ok += 1.
          ENDIF.
          lv_res = |APLICADO: sujeto a retencion { lv_accion } en el maestro.|.
        ELSE.
          rs_result-errores += 1.
          lv_res = |NO APLICADO: { lv_detalle }|.
          IF lv_primer_error IS INITIAL.
            lv_primer_error = lv_detalle.
          ENDIF.
        ENDIF.
      ENDIF.

      APPEND VALUE #( %is_draft     = if_abap_behv=>mk-off
                      EjecucionUUID = iv_ejecucion_uuid
                      LogUUID       = ls-log_uuid
                      Mensaje       = cortar( |{ lv_res } { sin_prefijo( CONV string( ls-mensaje ) ) }| ) ) TO lt_upd.
    ENDLOOP.

    IF lt_upd IS NOT INITIAL.
      MODIFY ENTITIES OF zi_arba_ret_ejecucion
        ENTITY Log
          UPDATE FIELDS ( Mensaje )
          WITH lt_upd
        FAILED DATA(lf_upd)
        REPORTED DATA(lr_upd).
    ENDIF.

    IF mo_client IS BOUND.
      TRY.
          mo_client->close( ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
    ENDIF.

    rs_result-mensaje = |Sujeto destildado: { rs_result-destildes_ok }. Sujeto tildado: { rs_result-tildes_ok }. | &&
                        |Ya estaban: { rs_result-sin_cambio }. Con error: { rs_result-errores }.|.
    IF lv_primer_error IS NOT INITIAL.
      rs_result-mensaje = |{ rs_result-mensaje } Primer error: { lv_primer_error }|.
    ENDIF.
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


  METHOD patch_entidad.
    " Copia de zcl_arba_ret_tuc_exencion.clas.abap:222-246 (POST + X-HTTP-Method: MERGE = PATCH parcial OData V2).
    CLEAR ev_detalle.
    DATA(lv_key) = |Supplier='{ escapar( iv_supplier ) }'| &&
                   |,CompanyCode='{ escapar( iv_sociedad ) }'| &&
                   |,WithholdingTaxType='{ escapar( iv_tipo ) }'|.
    DATA(lv_path) = |{ c_base_path }/{ c_entity }({ lv_key })|.

    DATA(lo_req) = mo_client->get_http_request( ).
    lo_req->set_uri_path( i_uri_path = lv_path ).
    lo_req->set_header_field( i_name = 'X-CSRF-Token'  i_value = mv_token ).
    lo_req->set_header_field( i_name = 'X-HTTP-Method' i_value = 'MERGE' ).
    lo_req->set_header_field( i_name = 'Content-Type'  i_value = 'application/json' ).
    lo_req->set_header_field( i_name = 'Accept'        i_value = 'application/json' ).
    " Si la API respondiera 412/428 por ETag, descomentar (criterio del DELETE, zcl_arba_ret_bp_updater.clas.abap:413):
    " lo_req->set_header_field( i_name = 'If-Match' i_value = '*' ).
    lo_req->set_text( i_text = iv_body_json ).

    DATA(lo_resp) = mo_client->execute( i_method = if_web_http_client=>post ).
    DATA(lv_code) = lo_resp->get_status( )-code.
    rv_ok = xsdbool( lv_code = 200 OR lv_code = 202 OR lv_code = 204 ).
    IF rv_ok = abap_false.
      DATA(lv_body) = lo_resp->get_text( ).
      FIND FIRST OCCURRENCE OF PCRE `"value"\s*:\s*"([^"]*)"` IN lv_body SUBMATCHES DATA(lv_err).
      ev_detalle = |HTTP { lv_code }: { COND string( WHEN lv_err IS NOT INITIAL THEN lv_err ELSE lv_body ) }|.
    ENDIF.
  ENDMETHOD.


  METHOD sin_prefijo.
    " Reintento del boton: no acumular "APLICADO: ... / NO APLICADO: ..." delante del mensaje del motor.
    " Los mensajes de ER_PROC que llegan aca empiezan con "ER marca B:" o "ER: ". Se busca la ULTIMA
    " aparicion de esos prefijos exactos (no " ER" suelto: un texto de la API como "... ERROR ..." lo
    " contiene y cortaria en el lugar equivocado).
    rv = iv_msg.
    IF strlen( rv ) >= 9 AND ( substring( val = rv len = 9 ) = `APLICADO:` OR
                                ( strlen( rv ) >= 12 AND substring( val = rv len = 12 ) = `NO APLICADO:` ) ).
      DATA(lv_pos) = find( val = rv pcre = ` (ER marca B:|ER: )` occ = -1 ).
      rv = COND #( WHEN lv_pos >= 0 THEN substring( val = rv off = lv_pos + 1 ) ELSE rv ).
    ENDIF.
  ENDMETHOD.


  METHOD escapar.
    rv = replace( val = condense( CONV string( iv_in ) ) sub = `'` with = `''` occ = 0 ).
  ENDMETHOD.


  METHOD cortar.
    rv = COND #( WHEN strlen( iv_txt ) > 255 THEN substring( val = iv_txt off = 0 len = 255 ) ELSE iv_txt ).
  ENDMETHOD.
ENDCLASS.
