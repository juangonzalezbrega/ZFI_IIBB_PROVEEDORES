"! Aplica por API (API_BUSINESS_PARTNER, A_SupplierWithHoldingTax) los dos casos de Coeficientes de
"! Tucuman que la app estandar no hace: destilde de "sujeto a retencion" (Excluido, caso 'X') y exencion
"! (coeficiente < 1). Lee las filas del log de una ejecucion REAL y deja el resultado en el mensaje de
"! cada fila. Usa el mismo Communication Arrangement que las altas (ZCS_ARBA_RET_BP_OUT).
CLASS zcl_arba_ret_tuc_exencion DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_result,
             destildes_ok  TYPE i,
             exenciones_ok TYPE i,
             errores       TYPE i,
             mensaje       TYPE string,
           END OF ty_result.

    "! Aplica destildes y exenciones de una ejecucion contra la API BP.
    METHODS aplicar
      IMPORTING iv_ejecucion_uuid TYPE sysuuid_x16
      RETURNING VALUE(rs_result)  TYPE ty_result.

  PRIVATE SECTION.
    " --- Config de la llamada (ver instructivo). Longitudes segun los parametros de
    " create_by_comm_arrangement: comm_scenario = C(30), service_id = C(40). ---
    CONSTANTS c_comm_scenario TYPE c LENGTH 30 VALUE 'ZCS_ARBA_RET_BP_OUT'.
    CONSTANTS c_service_id    TYPE c LENGTH 40 VALUE 'ZARBA_RET_BP_OUT_REST'.
    " Path relativo del servicio OData (V2) de la API BP.
    CONSTANTS c_base_path TYPE string VALUE '/sap/opu/odata/sap/API_BUSINESS_PARTNER'.
    CONSTANTS c_entity    TYPE string VALUE 'A_SupplierWithHoldingTax'.

    " --- Campos de A_SupplierWithHoldingTax ---
    CONSTANTS c_fld_subject    TYPE string VALUE 'IsWithholdingTaxSubject'.
    CONSTANTS c_fld_exmpt_pct  TYPE string VALUE 'WithholdingTaxExmptPercent'.
    CONSTANTS c_fld_exmpt_from TYPE string VALUE 'ExemptionDateBegin'.
    CONSTANTS c_fld_exmpt_to   TYPE string VALUE 'ExemptionDateEnd'.
    " SAP exige el nro. de certificado de exencion (LFBW-WT_EXNR) cuando se carga el porcentaje. Se arma
    " con la provincia y el periodo del padron (ej. TUC202610). A confirmar con el funcional.
    CONSTANTS c_fld_exmpt_cert TYPE string VALUE 'WithholdingTaxCertificate'.

    DATA mo_client TYPE REF TO if_web_http_client.
    DATA mv_token  TYPE string.

    METHODS abrir_conexion RAISING cx_static_check.
    METHODS csrf_token     RETURNING VALUE(rv_token) TYPE string RAISING cx_static_check.

    "! PATCH (MERGE de OData V2) al registro de retencion del proveedor. Clave: Supplier + CompanyCode +
    "! WithholdingTaxType (la misma que usa ZCL_ARBA_RET_BP_UPDATER). ev_detalle = codigo y respuesta HTTP.
    METHODS patch_entidad
      IMPORTING iv_supplier  TYPE c
                iv_sociedad  TYPE c
                iv_tipo      TYPE c
                iv_body_json TYPE string
      EXPORTING ev_detalle   TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_boolean
      RAISING   cx_static_check.

    "! Fecha en formato OData V2 Edm.DateTime: /Date(milisegundos_epoch_UTC)/.
    METHODS odata_date
      IMPORTING iv_date   TYPE d
      RETURNING VALUE(rv) TYPE string.

    METHODS escapar
      IMPORTING iv_in     TYPE c
      RETURNING VALUE(rv) TYPE string.

    "! Recorta al largo del campo mensaje del log (char 255).
    METHODS cortar
      IMPORTING iv_txt    TYPE string
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_TUC_EXENCION IMPLEMENTATION.


  METHOD aplicar.
    " 1) Cabecera: solo ejecuciones REALES finalizadas (las simulaciones no se aplican al maestro).
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
      rs_result-mensaje = 'Las exenciones se aplican solo a una corrida ejecutada (botón Ejecutar), no a una simulación.'.
      RETURN.
    ENDIF.

    " 2) Filas a aplicar: destilde (caso 'X') o exencion (exencion_pct > 0), con proveedor. La exencion
    "    tambien con SCB: coef < 1 y el codigo ya correcto queda "sin cambios" pero la exencion igual va.
    SELECT log_uuid, proveedor, caso, mensaje, exencion_pct, exencion_desde, exencion_hasta
      FROM zarba_ret_log
      WHERE ejecucion_uuid = @iv_ejecucion_uuid
        AND ( estado = 'ACT' OR ( estado = 'SCB' AND exencion_pct > 0 ) )
        AND proveedor     <> @space
        AND ( caso = 'X' OR exencion_pct > 0 )
      INTO TABLE @DATA(lt_rows).
    IF lt_rows IS INITIAL.
      rs_result-mensaje = 'Esta corrida no tiene exenciones ni destildes para aplicar.'.
      RETURN.
    ENDIF.

    " 3) Abrir conexion y obtener token CSRF una vez.
    TRY.
        abrir_conexion( ).
        mv_token = csrf_token( ).
      CATCH cx_root INTO DATA(lx_conn).
        rs_result-errores = lines( lt_rows ).
        rs_result-mensaje = |No se pudo conectar con SAP para aplicar las exenciones: { lx_conn->get_text( ) }|.
        RETURN.
    ENDTRY.

    " 4) Aplicar fila por fila y dejar el resultado en el mensaje de la fila. Se llama desde la accion RAP:
    "    no se puede escribir la base directo (BEHAVIOR_ILLEGAL_STATEMENT); el mensaje va por EML y lo graba
    "    el framework al final de la accion.
    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion\\Log.
    LOOP AT lt_rows INTO DATA(ls).
      DATA lv_ok      TYPE abap_boolean.
      DATA lv_body    TYPE string.
      DATA lv_detalle TYPE string.
      DATA lv_res     TYPE string.
      CLEAR: lv_ok, lv_body, lv_detalle, lv_res.

      IF ls-caso = 'X'.
        lv_body = |\{ "{ c_fld_subject }": false \}|.
      ELSE.
        " Porcentaje con punto decimal; las fechas solo si el log las trae (vigencia AAAAMM del archivo).
        DATA(lv_pct) = |{ ls-exencion_pct DECIMALS = 2 }|.
        lv_body = |\{ "{ c_fld_exmpt_pct }": "{ lv_pct }"|.
        IF ls-exencion_desde IS NOT INITIAL AND ls-exencion_desde <> '00000000'.
          lv_body = |{ lv_body }, "{ c_fld_exmpt_cert }": "TUC{ ls-exencion_desde(6) }"|.
          lv_body = |{ lv_body }, "{ c_fld_exmpt_from }": "{ odata_date( ls-exencion_desde ) }"|.
        ELSE.
          lv_body = |{ lv_body }, "{ c_fld_exmpt_cert }": "TUC"|.
        ENDIF.
        IF ls-exencion_hasta IS NOT INITIAL AND ls-exencion_hasta <> '00000000'.
          lv_body = |{ lv_body }, "{ c_fld_exmpt_to }": "{ odata_date( ls-exencion_hasta ) }"|.
        ENDIF.
        lv_body = |{ lv_body } \}|.
      ENDIF.

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
        IF ls-caso = 'X'.
          rs_result-destildes_ok = rs_result-destildes_ok + 1.
          lv_res = 'APLICADO: sujeto a retencion destildado en el maestro.'.
        ELSE.
          rs_result-exenciones_ok = rs_result-exenciones_ok + 1.
          lv_res = |APLICADO: exencion { ls-exencion_pct DECIMALS = 2 }% cargada en el maestro.|.
        ENDIF.
      ELSE.
        rs_result-errores = rs_result-errores + 1.
        lv_res = |NO APLICADO: { lv_detalle }|.
      ENDIF.

      APPEND VALUE #( %is_draft     = if_abap_behv=>mk-off
                      EjecucionUUID = iv_ejecucion_uuid
                      LogUUID       = ls-log_uuid
                      Mensaje       = cortar( |{ lv_res } { ls-mensaje }| ) ) TO lt_upd.
      IF lv_ok = abap_false AND rs_result-mensaje IS INITIAL.
        rs_result-mensaje = lv_detalle.   " primer error, para el mensaje de pantalla
      ENDIF.
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

    DATA(lv_primer_error) = rs_result-mensaje.
    rs_result-mensaje = |Exenciones aplicadas: { rs_result-exenciones_ok }. | &&
                        |Destildes de "sujeto a retención": { rs_result-destildes_ok }. Con error: { rs_result-errores }.|.
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
    CLEAR ev_detalle.
    DATA(lv_key) = |Supplier='{ escapar( iv_supplier ) }'| &&
                   |,CompanyCode='{ escapar( iv_sociedad ) }'| &&
                   |,WithholdingTaxType='{ escapar( iv_tipo ) }'|.
    DATA(lv_path) = |{ c_base_path }/{ c_entity }({ lv_key })|.

    DATA(lo_req) = mo_client->get_http_request( ).
    lo_req->set_uri_path( i_uri_path = lv_path ).
    lo_req->set_header_field( i_name = 'X-CSRF-Token'  i_value = mv_token ).
    lo_req->set_header_field( i_name = 'X-HTTP-Method' i_value = 'MERGE' ). " PATCH parcial en OData V2
    lo_req->set_header_field( i_name = 'Content-Type'  i_value = 'application/json' ).
    lo_req->set_header_field( i_name = 'Accept'        i_value = 'application/json' ).
    lo_req->set_text( i_text = iv_body_json ).

    DATA(lo_resp) = mo_client->execute( i_method = if_web_http_client=>post ).
    DATA(lv_code) = lo_resp->get_status( )-code.
    " 200/202/204 = ok. Otro codigo = error: se devuelve el mensaje de la API para el log.
    rv_ok = xsdbool( lv_code = 200 OR lv_code = 202 OR lv_code = 204 ).
    IF rv_ok = abap_false.
      DATA(lv_body) = lo_resp->get_text( ).
      FIND FIRST OCCURRENCE OF PCRE `"value"\s*:\s*"([^"]*)"` IN lv_body SUBMATCHES DATA(lv_err).
      ev_detalle = |HTTP { lv_code }: { COND string( WHEN lv_err IS NOT INITIAL THEN lv_err ELSE lv_body ) }|.
    ENDIF.
  ENDMETHOD.


  METHOD odata_date.
    IF iv_date IS INITIAL.
      rv = ``.
      RETURN.
    ENDIF.
    DATA(lv_days) = iv_date - CONV d( '19700101' ).
    DATA(lv_ms)   = CONV int8( lv_days ) * 86400000.
    rv = |/Date({ lv_ms })/|.
  ENDMETHOD.


  METHOD escapar.
    " Comilla simple en el valor de clave OData se duplica.
    rv = replace( val = condense( CONV string( iv_in ) ) sub = `'` with = `''` occ = 0 ).
  ENDMETHOD.


  METHOD cortar.
    rv = COND #( WHEN strlen( iv_txt ) > 255 THEN substring( val = iv_txt off = 0 len = 255 ) ELSE iv_txt ).
  ENDMETHOD.
ENDCLASS.
