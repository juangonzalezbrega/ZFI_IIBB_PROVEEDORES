CLASS zcl_arba_ret_bp_updater DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_supplier    TYPE c LENGTH 10.
    TYPES ty_supplier_tt TYPE STANDARD TABLE OF ty_supplier WITH EMPTY KEY.
    TYPES ty_cuit        TYPE c LENGTH 11.

    TYPES: BEGIN OF ty_ret_actual,
             existe    TYPE abap_boolean,   " el proveedor ya tiene el tipo de retencion
             indicador TYPE zcl_arba_ret_determinador=>ty_wht_code,
             es_sujeto TYPE abap_boolean,
           END OF ty_ret_actual.

    "! Proveedor con datos de retencion existentes (para sincronizacion completa).
    TYPES: BEGIN OF ty_sup_ret,
             supplier  TYPE ty_supplier,
             cuit      TYPE c LENGTH 11,
             indicador TYPE zcl_arba_ret_determinador=>ty_wht_code,
             es_sujeto TYPE abap_boolean,
           END OF ty_sup_ret.
    TYPES ty_sup_ret_tt TYPE STANDARD TABLE OF ty_sup_ret WITH EMPTY KEY.

    "! Precarga en memoria el universo de la ejecucion (EF seccion 12): mapa CUIT->proveedor(es)
    "! y los registros de retencion existentes para la sociedad + tipo. Se ejecuta UNA vez;
    "! luego el matching y la lectura por CUIT se resuelven sin acceso a base de datos.
    METHODS preparar
      IMPORTING iv_sociedad  TYPE bukrs
                iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_categoria TYPE c DEFAULT 'AR1A'.   " BPTaxType: categoria de nro fiscal CUIT (AR); en GZ3 es 'AR1A'

    "! El proveedor esta ampliado (tiene datos) en la sociedad de la ejecucion. Sin eso no se le puede
    "! dar de alta la retencion (la API la rechaza). Si preparar( ) no cargo la sociedad (p.ej. dobles
    "! de prueba), devuelve abap_true para no alterar el comportamiento previo.
    METHODS esta_ampliado
      IMPORTING iv_supplier  TYPE ty_supplier
      RETURNING VALUE(rv_ok) TYPE abap_boolean.

    "! Busca proveedores por CUIT (matching por BPTaxNumber normalizado a 11 digitos).
    "! 0 -> no encontrado ; 1 -> ok ; >1 -> duplicado en SAP.
    METHODS buscar_proveedor
      IMPORTING iv_cuit      TYPE c
      EXPORTING et_suppliers TYPE ty_supplier_tt.

    "! Lee el registro de retencion actual del proveedor (sociedad + tipo).
    METHODS leer_retencion_actual
      IMPORTING iv_supplier      TYPE ty_supplier
                iv_sociedad      TYPE bukrs
                iv_tipo_ret      TYPE zcl_arba_ret_determinador=>ty_wht_type
      RETURNING VALUE(rs_actual) TYPE ty_ret_actual.

    "! Devuelve todos los proveedores que YA tienen el tipo de retencion (sociedad + tipo),
    "! precargados por preparar( ). Sirve para el recorrido "fuera de padron" (Caso 3).
    METHODS get_proveedores_con_retencion
      RETURNING VALUE(rt_sup) TYPE ty_sup_ret_tt.

    "! Titulares (proveedores) que YA tienen un tipo de retencion dado (sociedad + tipo), con su CUIT.
    "! Usa el mapa CUIT->proveedor precargado por preparar( ). Para el TN de Tucuman se usa como
    "! "keepers": los titulares TN actuales se conservan en el snapshot (evita que la app estandar los
    "! borre por ausencia) y resuelve la baja del TN (Caso 7) por su ausencia cuando pasan al padron.
    METHODS leer_titulares_tipo
      IMPORTING iv_sociedad   TYPE bukrs
                iv_tipo       TYPE zcl_arba_ret_determinador=>ty_wht_type
      RETURNING VALUE(rt_sup) TYPE ty_sup_ret_tt.

    "! Proveedores con domicilio en una REGION dada (EF Tucuman, caso 6 "fuera de padron"), con su CUIT.
    "! Lee la vista ZI_ARBA_RET_SUP_REGION (region del domicilio via I_Supplier). BLINDAJE: si la
    "! lectura de la direccion del BP no esta autorizada o falla, ev_error = 'X' y et_sup vuelve vacio
    "! -> el motor NO ejecuta el fuera de padron por region (nunca genera un snapshot vacio que dispare
    "! borrados). Solo devuelve proveedores con CUIT (necesario para el matching de la app estandar).
    METHODS get_proveedores_por_region
      IMPORTING iv_region  TYPE c
      EXPORTING et_sup     TYPE ty_sup_ret_tt
                ev_error   TYPE abap_boolean
                ev_mensaje TYPE string.

    "! Crea/actualiza los datos de retencion del proveedor.
    "! PUNTO DE INTEGRACION: API_BUSINESS_PARTNER / A_SupplierWithHoldingTax.
    METHODS actualizar_retencion
      IMPORTING iv_supplier  TYPE ty_supplier
                iv_sociedad  TYPE bukrs
                iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_indicador TYPE zcl_arba_ret_determinador=>ty_wht_code
                iv_es_sujeto TYPE abap_boolean
                iv_crear     TYPE abap_boolean   " abap_true = alta (Caso 1); false = update (Caso 2)
      EXPORTING ev_ok        TYPE abap_boolean
                ev_mensaje   TYPE string.

    "! Borra el registro de retencion del proveedor (tipo) del maestro via API (OData V2 DELETE sobre
    "! A_SupplierWithHoldingTax). Usado SOLO para el "cambio de regimen" de Santa Fe (opcion A, Fase 2).
    METHODS borrar_retencion
      IMPORTING iv_supplier TYPE ty_supplier
                iv_sociedad TYPE bukrs
                iv_tipo_ret TYPE zcl_arba_ret_determinador=>ty_wht_type
      EXPORTING ev_ok       TYPE abap_boolean
                ev_mensaje  TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_cuit_map,
             cuit     TYPE c LENGTH 11,
             supplier TYPE ty_supplier,
           END OF ty_cuit_map.
    TYPES ty_cuit_map_tt TYPE SORTED TABLE OF ty_cuit_map WITH NON-UNIQUE KEY cuit.

    TYPES: BEGIN OF ty_ret_map,
             supplier  TYPE ty_supplier,
             indicador TYPE zcl_arba_ret_determinador=>ty_wht_code,
             es_sujeto TYPE abap_boolean,
           END OF ty_ret_map.
    TYPES ty_ret_map_tt TYPE HASHED TABLE OF ty_ret_map WITH UNIQUE KEY supplier.

    DATA mv_preparado TYPE abap_boolean.
    DATA mt_cuit_map  TYPE ty_cuit_map_tt.
    DATA mt_ret_map   TYPE ty_ret_map_tt.
    DATA mt_soc_sup   TYPE HASHED TABLE OF ty_supplier WITH UNIQUE KEY table_line.
    DATA mv_soc_carg  TYPE abap_boolean.

    " Path COMPLETO del servicio OData V2 + entidad (el Communication System solo aporta el host,
    " el outbound service NO agrega prefijo -> el path completo va aca).
    CONSTANTS c_entity_set TYPE string VALUE '/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_SupplierWithHoldingTax'.
    " Raiz del servicio: destino del fetch de token CSRF (GET liviano, SIN query options).
    CONSTANTS c_service_root TYPE string VALUE '/sap/opu/odata/sap/API_BUSINESS_PARTNER/'.

    "! Normaliza un CUIT a 11 digitos numericos: quita guiones/separadores con los que el
    "! maestro BP suele guardar el nro fiscal AR (20-38356436-1 -> 20383564361).
    METHODS normalizar_cuit
      IMPORTING iv_value       TYPE clike
      RETURNING VALUE(rv_cuit) TYPE ty_cuit.
ENDCLASS.



CLASS ZCL_ARBA_RET_BP_UPDATER IMPLEMENTATION.


  METHOD preparar.
    CLEAR: mt_cuit_map, mt_ret_map, mt_soc_sup, mv_soc_carg.

    " Proveedores ampliados a la sociedad (datos de sociedad): condicion para dar de alta la retencion.
    SELECT supplier FROM i_suppliercompany
      WHERE companycode = @iv_sociedad
      INTO TABLE @mt_soc_sup.
    " Si la lectura vino vacia (p.ej. sin autorizacion por sociedad) no se filtra: se intenta el alta.
    mv_soc_carg = xsdbool( mt_soc_sup IS NOT INITIAL ).

    " Mapa CUIT -> proveedor(es). El universo de proveedores activos es acotado
    " (EF supuesto S5: < 20.000), por lo que se carga completo una sola vez.
    " El CUIT (AR) vive en BPTaxNumber para la categoria 'AR1A' (verificado en GZ3: se guarda
    " en 11 digitos limpios), NO en BPTaxLongNumber (vacio en este tenant). Se lee el valor
    " crudo (ancho completo, sin truncar) y se normaliza a 11 digitos -defensivo, por si algun
    " BP tuviera guiones- para el match contra el CUIT del padron.
    SELECT tax~bptaxnumber      AS taxnumber,
           tax~businesspartner  AS supplier
      FROM i_businesspartnertaxnumber AS tax
      INNER JOIN i_supplier AS sup
        ON sup~supplier = tax~businesspartner
      WHERE tax~bptaxtype = @iv_categoria
      INTO TABLE @DATA(lt_maestro).

    LOOP AT lt_maestro INTO DATA(ls_maestro).
      DATA(lv_cuit) = normalizar_cuit( ls_maestro-taxnumber ).
      IF lv_cuit IS INITIAL.
        CONTINUE.
      ENDIF.
      INSERT VALUE #( cuit = lv_cuit supplier = ls_maestro-supplier ) INTO TABLE mt_cuit_map.
    ENDLOOP.

    " Registros de retencion existentes para la sociedad + tipo (para clasificar Caso 1 vs 2).
    SELECT supplier,
           withholdingtaxcode      AS indicador,
           iswithholdingtaxsubject AS es_sujeto
      FROM i_supplierwithholdingtax
      WHERE companycode        = @iv_sociedad
        AND withholdingtaxtype = @iv_tipo_ret
      INTO CORRESPONDING FIELDS OF TABLE @mt_ret_map.

    mv_preparado = abap_true.
  ENDMETHOD.


  METHOD esta_ampliado.
    rv_ok = xsdbool( mv_soc_carg = abap_false OR line_exists( mt_soc_sup[ table_line = iv_supplier ] ) ).
  ENDMETHOD.


  METHOD buscar_proveedor.
    CLEAR et_suppliers.
    LOOP AT mt_cuit_map INTO DATA(ls) WHERE cuit = iv_cuit.
      APPEND ls-supplier TO et_suppliers.
    ENDLOOP.
  ENDMETHOD.


  METHOD normalizar_cuit.
    " Conserva solo los digitos (descarta guiones, espacios y cualquier separador).
    DATA lv_digitos TYPE string.
    DATA lv_offset  TYPE i.
    DATA(lv_source) = CONV string( iv_value ).

    WHILE lv_offset < strlen( lv_source ).
      DATA(lv_char) = substring( val = lv_source off = lv_offset len = 1 ).
      IF lv_char CO '0123456789'.
        lv_digitos = |{ lv_digitos }{ lv_char }|.
      ENDIF.
      lv_offset = lv_offset + 1.
    ENDWHILE.

    IF lv_digitos IS INITIAL.
      RETURN.
    ENDIF.

    " CUIT = 11 digitos: recorta excedente o rellena con ceros a la izquierda.
    IF strlen( lv_digitos ) > 11.
      lv_digitos = substring( val = lv_digitos off = 0 len = 11 ).
    ELSEIF strlen( lv_digitos ) < 11.
      lv_digitos = |{ lv_digitos WIDTH = 11 ALIGN = RIGHT PAD = '0' }|.
    ENDIF.

    rv_cuit = lv_digitos.
  ENDMETHOD.


  METHOD leer_retencion_actual.
    CLEAR rs_actual.
    READ TABLE mt_ret_map INTO DATA(ls) WITH TABLE KEY supplier = iv_supplier.
    IF sy-subrc = 0.
      rs_actual-existe    = abap_true.
      rs_actual-indicador = ls-indicador.
      rs_actual-es_sujeto = COND #( WHEN ls-es_sujeto = abap_true THEN abap_true ELSE abap_false ).
    ENDIF.
  ENDMETHOD.


  METHOD get_proveedores_con_retencion.
    CLEAR rt_sup.

    " Indice auxiliar proveedor -> CUIT (para informar el CUIT en el log)
    DATA lt_sup_cuit TYPE HASHED TABLE OF ty_cuit_map WITH UNIQUE KEY supplier.
    LOOP AT mt_cuit_map INTO DATA(ls_cm).
      INSERT ls_cm INTO TABLE lt_sup_cuit.  " si el proveedor ya existe, se ignora
    ENDLOOP.

    LOOP AT mt_ret_map INTO DATA(ls_ret).
      DATA(lv_cuit) = VALUE #( lt_sup_cuit[ supplier = ls_ret-supplier ]-cuit OPTIONAL ).
      APPEND VALUE #( supplier  = ls_ret-supplier
                      cuit      = lv_cuit
                      indicador = ls_ret-indicador
                      es_sujeto = ls_ret-es_sujeto ) TO rt_sup.
    ENDLOOP.
  ENDMETHOD.


  METHOD leer_titulares_tipo.
    CLEAR rt_sup.

    " Indice proveedor -> CUIT (del mapa precargado por preparar).
    DATA lt_sup_cuit TYPE HASHED TABLE OF ty_cuit_map WITH UNIQUE KEY supplier.
    LOOP AT mt_cuit_map INTO DATA(ls_cm).
      INSERT ls_cm INTO TABLE lt_sup_cuit.  " si el proveedor ya existe, se ignora
    ENDLOOP.

    SELECT supplier,
           withholdingtaxcode      AS indicador,
           iswithholdingtaxsubject AS es_sujeto
      FROM i_supplierwithholdingtax
      WHERE companycode        = @iv_sociedad
        AND withholdingtaxtype = @iv_tipo
      INTO TABLE @DATA(lt).

    LOOP AT lt INTO DATA(ls).
      APPEND VALUE #( supplier  = ls-supplier
                      cuit      = VALUE #( lt_sup_cuit[ supplier = ls-supplier ]-cuit OPTIONAL )
                      indicador = ls-indicador
                      es_sujeto = COND #( WHEN ls-es_sujeto = abap_true THEN abap_true ELSE abap_false ) ) TO rt_sup.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_proveedores_por_region.
    CLEAR: et_sup, ev_error, ev_mensaje.

    " Indice proveedor -> CUIT (del mapa precargado por preparar).
    DATA lt_sup_cuit TYPE HASHED TABLE OF ty_cuit_map WITH UNIQUE KEY supplier.
    LOOP AT mt_cuit_map INTO DATA(ls_cm).
      INSERT ls_cm INTO TABLE lt_sup_cuit.
    ENDLOOP.

    " BLINDAJE: la lectura de la direccion del BP puede no estar autorizada. Si el SELECT falla, se
    " informa el error y se devuelve vacio -> el caller NO ejecuta el fuera de padron por region.
    TRY.
        SELECT supplier
          FROM zi_arba_ret_sup_region
          WHERE region = @iv_region
          INTO TABLE @DATA(lt).
      CATCH cx_root INTO DATA(lx).
        ev_error   = abap_true.
        ev_mensaje = lx->get_text( ).
        RETURN.
    ENDTRY.

    LOOP AT lt INTO DATA(ls).
      DATA(lv_cuit) = VALUE ty_cuit( lt_sup_cuit[ supplier = ls-supplier ]-cuit OPTIONAL ).
      IF lv_cuit IS INITIAL.
        CONTINUE.   " sin CUIT no se puede exportar/matchear en la app estandar
      ENDIF.
      APPEND VALUE #( supplier = ls-supplier cuit = lv_cuit ) TO et_sup.
    ENDLOOP.
  ENDMETHOD.


  METHOD actualizar_retencion.
    CLEAR: ev_ok, ev_mensaje.

    TRY.
        DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
          comm_scenario = 'ZCS_ARBA_RET_PADRON'
          service_id    = 'ZOS_ARBA_ABP_REST' ).
        DATA(lo_http) = cl_web_http_client_manager=>create_by_http_destination( i_destination = lo_dest ).

        " 1) Token CSRF (GET con X-CSRF-Token: fetch) contra la RAIZ del servicio.
        "    Importante: NO usar query options ($top/$skip/...). A_SupplierWithHoldingTax
        "    las rechaza y, como el request se reutiliza para el POST, el query string se
        "    filtraria a la URI de escritura (por-clave) -> HTTP 400 "query options not allowed".
        DATA(lo_req) = lo_http->get_http_request( ).
        lo_req->set_uri_path( i_uri_path = c_service_root ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'fetch' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        DATA(lo_resp_csrf) = lo_http->execute( i_method = if_web_http_client=>get ).
        DATA(lv_token) = lo_resp_csrf->get_header_field( 'x-csrf-token' ).

        " 2) Cuerpo y ruta (Caso 1 = crear ; Caso 2 = actualizar via MERGE)
        DATA(lv_subject) = COND string( WHEN iv_es_sujeto = abap_true THEN 'true' ELSE 'false' ).
        DATA lv_path  TYPE string.
        DATA lv_body  TYPE string.
        DATA lv_merge TYPE abap_boolean.
        IF iv_crear = abap_true.
          lv_merge = abap_false.
          lv_path  = c_entity_set.
          lv_body  = |\{ "Supplier":"{ iv_supplier }","CompanyCode":"{ iv_sociedad }",|
                  && |"WithholdingTaxType":"{ iv_tipo_ret }","WithholdingTaxCode":"{ iv_indicador }",|
                  && |"IsWithholdingTaxSubject":{ lv_subject } \}|.
        ELSE.
          lv_merge = abap_true.
          lv_path  = |{ c_entity_set }(Supplier='{ iv_supplier }',CompanyCode='{ iv_sociedad }',WithholdingTaxType='{ iv_tipo_ret }')|.
          lv_body  = |\{ "WithholdingTaxCode":"{ iv_indicador }","IsWithholdingTaxSubject":{ lv_subject } \}|.
        ENDIF.

        " 3) Escritura con el token CSRF (POST; update = POST + X-HTTP-Method MERGE, OData V2)
        DATA(lo_req2) = lo_http->get_http_request( ).
        lo_req2->set_uri_path( i_uri_path = lv_path ).
        lo_req2->set_header_field( i_name = 'X-CSRF-Token' i_value = lv_token ).
        lo_req2->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_req2->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        IF lv_merge = abap_true.
          lo_req2->set_header_field( i_name = 'X-HTTP-Method' i_value = 'MERGE' ).
        ENDIF.
        lo_req2->set_text( i_text = lv_body ).
        DATA(lo_resp) = lo_http->execute( i_method = if_web_http_client=>post ).

        DATA(lv_code) = lo_resp->get_status( )-code.
        IF lv_code >= 200 AND lv_code < 300.
          ev_ok = abap_true.
        ELSE.
          ev_ok      = abap_false.
          ev_mensaje = |API_BUSINESS_PARTNER HTTP { lv_code }: { lo_resp->get_text( ) }|.
        ENDIF.

        lo_http->close( ).

      CATCH cx_root INTO DATA(lx).
        ev_ok      = abap_false.
        ev_mensaje = |Error API_BUSINESS_PARTNER: { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD borrar_retencion.
    CLEAR: ev_ok, ev_mensaje.

    TRY.
        DATA(lo_dest) = cl_http_destination_provider=>create_by_comm_arrangement(
          comm_scenario = 'ZCS_ARBA_RET_PADRON'
          service_id    = 'ZOS_ARBA_ABP_REST' ).
        DATA(lo_http) = cl_web_http_client_manager=>create_by_http_destination( i_destination = lo_dest ).

        " Path por-clave del registro de retencion del proveedor (se reusa para DELETE y verificacion).
        DATA(lv_path) = |{ c_entity_set }(Supplier='{ iv_supplier }',CompanyCode='{ iv_sociedad }',WithholdingTaxType='{ iv_tipo_ret }')|.

        " 1) Token CSRF (GET fetch) contra la RAIZ del servicio, SIN query options (mismo GOTCHA que
        "    actualizar_retencion: get_http_request devuelve el MISMO objeto request).
        DATA(lo_req) = lo_http->get_http_request( ).
        lo_req->set_uri_path( i_uri_path = c_service_root ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'fetch' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        DATA(lo_resp_csrf) = lo_http->execute( i_method = if_web_http_client=>get ).
        DATA(lv_csrf_code) = lo_resp_csrf->get_status( )-code.
        DATA(lv_token)     = lo_resp_csrf->get_header_field( 'x-csrf-token' ).

        " Sin token, el arrangement/destino NO esta resolviendo la API (p.ej. redireccion a login que
        " responde 200 HTML). Abortar con diagnostico en vez de intentar un DELETE que "responde OK".
        IF lv_token IS INITIAL.
          ev_ok      = abap_false.
          ev_mensaje = |Sin token CSRF (HTTP { lv_csrf_code }). Revisar Communication Arrangement ZCS_ARBA_RET_PADRON / conectividad a API_BUSINESS_PARTNER.|.
          lo_http->close( ).
          RETURN.
        ENDIF.

        " 2) DELETE por clave: borra el registro de retencion (tipo) del proveedor en el maestro.
        DATA(lo_req2) = lo_http->get_http_request( ).
        lo_req2->set_uri_path( i_uri_path = lv_path ).
        lo_req2->set_header_field( i_name = 'X-CSRF-Token' i_value = lv_token ).
        lo_req2->set_header_field( i_name = 'If-Match'     i_value = '*' ).   " OData V2: bypass etag
        lo_req2->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        DATA(lo_resp) = lo_http->execute( i_method = if_web_http_client=>delete ).
        DATA(lv_code) = lo_resp->get_status( )-code.
        DATA(lv_body) = lo_resp->get_text( ).
        DATA(lv_body_short) = COND string( WHEN strlen( lv_body ) > 300 THEN substring( val = lv_body off = 0 len = 300 ) ELSE lv_body ).
        lo_http->close( ).

        IF lv_code < 200 OR lv_code >= 300.
          ev_ok      = abap_false.
          ev_mensaje = |DELETE HTTP { lv_code }: { lv_body_short }|.
          RETURN.
        ENDIF.

        " 3) VERIFICACION REAL: un 2xx NO garantiza que se haya borrado (redireccion/auth que responde
        "    2xx, o SAP que acepta pero NO aplica por regla de negocio -p.ej. partidas/documentos con el
        "    tipo-). Se re-lee por clave con un cliente NUEVO (sin headers residuales del DELETE):
        "      GET 404 -> borrado confirmado ; GET 2xx -> el registro SIGUE -> el borrado no se aplico.
        DATA(lo_http2) = cl_web_http_client_manager=>create_by_http_destination( i_destination = lo_dest ).
        DATA(lo_reqv)  = lo_http2->get_http_request( ).
        lo_reqv->set_uri_path( i_uri_path = lv_path ).
        lo_reqv->set_header_field( i_name = 'Accept' i_value = 'application/json' ).
        DATA(lo_respv) = lo_http2->execute( i_method = if_web_http_client=>get ).
        DATA(lv_chk)   = lo_respv->get_status( )-code.
        lo_http2->close( ).

        IF lv_chk = 404.
          ev_ok      = abap_true.
          ev_mensaje = |Borrado confirmado (DELETE { lv_code }, verificacion GET 404).|.
        ELSEIF lv_chk >= 200 AND lv_chk < 300.
          ev_ok      = abap_false.
          ev_mensaje = |El DELETE respondio { lv_code } pero el registro SIGUE existiendo (GET { lv_chk }): el borrado NO se aplico. | &&
                       |Respuesta DELETE: { lv_body_short }|.
        ELSE.
          " No se pudo confirmar (p.ej. 412 por If-Match, u otro). No afirmar exito.
          ev_ok      = abap_false.
          ev_mensaje = |DELETE { lv_code } pero verificacion no concluyente (GET { lv_chk }). Revisar manualmente el maestro.|.
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        ev_ok      = abap_false.
        ev_mensaje = |Error API_BUSINESS_PARTNER (delete): { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
