"! Clase utilitaria TEMPORAL para probar la conexion al API_BUSINESS_PARTNER
"! (self-call via communication arrangement). Correr con F9 en ADT
"! (Run As -> ABAP Application (Console)). Borrar despues de validar.
CLASS zcl_arba_ret_test_conn DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
protected section.
private section.
ENDCLASS.



CLASS ZCL_ARBA_RET_TEST_CONN IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    TRY.
        " Mismos valores que usa zcl_arba_ret_bp_updater (ajustar a los reales del tenant)
        DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
          comm_scenario = 'ZCS_ARBA_RET_PADRON'
          service_id    = 'ZOS_ARBA_ABP_REST' ).
        DATA(lo_http) = cl_web_http_client_manager=>create_by_http_destination( i_destination = lo_dest ).

        DATA(lo_req) = lo_http->get_http_request( ).
        lo_req->set_uri_path( i_uri_path = '/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_SupplierWithHoldingTax?$top=1&$format=json' ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'fetch' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).

        DATA(lo_resp) = lo_http->execute( i_method = if_web_http_client=>get ).

        DATA(lv_code)  = lo_resp->get_status( )-code.
        DATA(lv_token) = lo_resp->get_header_field( 'x-csrf-token' ).
        DATA(lv_body)  = lo_resp->get_text( ).

        out->write( |HTTP status : { lv_code }| ).
        out->write( |CSRF token  : { lv_token }| ).
        out->write( '--- Respuesta ---' ).
        out->write( lv_body ).

        lo_http->close( ).

        IF lv_code = 200.
          out->write( 'OK: conexion y autorizacion al API_BUSINESS_PARTNER funcionan.' ).
        ELSE.
          out->write( |ATENCION: status { lv_code } (revisar user/arrangement/path).| ).
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        out->write( |ERROR (destino/arrangement): { lx->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
