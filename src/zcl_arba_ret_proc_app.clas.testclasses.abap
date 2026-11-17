*"* Pruebas unitarias del procesamiento del padron ARBA Retenciones.
*"* Las dependencias que acceden a base de datos (determinador y BP updater)
*"* se sustituyen por dobles de prueba (subclases con REDEFINITION).

"======================================================================
" Doble de prueba: determinador de indicador
"======================================================================
CLASS ltd_determinador DEFINITION INHERITING FROM zcl_arba_ret_determinador.
  PUBLIC SECTION.
    METHODS determinar_indicador       REDEFINITION.
    METHODS obtener_indicador_maximo   REDEFINITION.
    METHODS obtener_alicuota_indicador REDEFINITION.
ENDCLASS.

CLASS ltd_determinador IMPLEMENTATION.
  METHOD determinar_indicador.
    CLEAR: ev_indicador, ev_estado, ev_mensaje.
    " Alicuota 9,99 (valor de prueba sin configuracion) -> pendiente
    IF iv_alicuota = '9.99'.
      ev_estado  = 'PCF'.
      ev_mensaje = 'sin indicador'.
      RETURN.
    ENDIF.
    " Indicador determinista por alicuota: "R" + parte entera
    ev_indicador = |R{ CONV i( iv_alicuota ) }|.
    ev_estado    = ''.
  ENDMETHOD.

  METHOD obtener_indicador_maximo.
    " Doble: la alicuota maxima de prueba es 6,00 -> indicador "R6"
    CLEAR: ev_indicador, ev_alicuota, ev_estado, ev_mensaje.
    ev_indicador = 'R6'.
    ev_alicuota  = '6.00'.
    ev_estado    = ''.
  ENDMETHOD.

  METHOD obtener_alicuota_indicador.
    " Doble: el indicador de prueba es "R" + parte entera de la alicuota
    " (ver determinar_indicador / obtener_indicador_maximo); deriva la alicuota de vuelta.
    CLEAR: ev_alicuota, ev_estado, ev_mensaje.
    IF strlen( iv_indicador ) >= 2 AND iv_indicador(1) = 'R'.
      ev_alicuota = iv_indicador+1.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"======================================================================
" Doble de prueba: gateway de proveedores
"======================================================================
CLASS ltd_bp DEFINITION INHERITING FROM zcl_arba_ret_bp_updater.
  PUBLIC SECTION.
    METHODS preparar                      REDEFINITION.
    METHODS buscar_proveedor              REDEFINITION.
    METHODS leer_retencion_actual         REDEFINITION.
    METHODS get_proveedores_con_retencion REDEFINITION.
ENDCLASS.

CLASS ltd_bp IMPLEMENTATION.
  METHOD preparar.
    " Doble: sin acceso a base de datos.
    RETURN.
  ENDMETHOD.

  METHOD get_proveedores_con_retencion.
    " 0000001000 esta en el padron (Caso 2); 0000009999 NO -> Caso 3
    rt_sup = VALUE #(
      ( supplier = '0000001000' cuit = '20000000028' indicador = 'R3' es_sujeto = abap_true )
      ( supplier = '0000009999' cuit = '20999999999' indicador = 'R1' es_sujeto = abap_true ) ).
  ENDMETHOD.

  METHOD buscar_proveedor.
    CLEAR et_suppliers.
    CASE iv_cuit.
      WHEN '20000000099'.        " no encontrado
        RETURN.
      WHEN '20000000088'.        " duplicado en SAP
        APPEND '0000000001' TO et_suppliers.
        APPEND '0000000002' TO et_suppliers.
      WHEN OTHERS.               " encontrado (1)
        APPEND '0000001000' TO et_suppliers.
    ENDCASE.
  ENDMETHOD.

  METHOD leer_retencion_actual.
    CLEAR rs_actual.
    " El proveedor 0000001000 no tiene retencion -> Caso 1
    " (para Caso 2 el test usaria otro doble)
    rs_actual-existe = abap_false.
  ENDMETHOD.
ENDCLASS.

"======================================================================
" Pruebas del parser
"======================================================================
CLASS ltcl_parser DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS mapea_campos         FOR TESTING.
    METHODS tolera_sin_sep_final FOR TESTING.
    METHODS cuenta_lineas_vacias FOR TESTING.
    METHODS parsea_caba          FOR TESTING.
ENDCLASS.

CLASS ltcl_parser IMPLEMENTATION.
  METHOD mapea_campos.
    DATA(lo) = NEW zcl_arba_ret_parser( ).
    lo->parse_file(
      EXPORTING iv_content = |R;25022026;01032026;31032026;20000000028;D;N;N;0,00;05;|
      IMPORTING et_records = DATA(lt) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( lt ) ).
    DATA(ls) = lt[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = 'R'            act = ls-regimen ).
    cl_abap_unit_assert=>assert_equals( exp = '20000000028'  act = ls-cuit ).
    cl_abap_unit_assert=>assert_equals( exp = '0,00'         act = ls-alicuota_txt ).
    cl_abap_unit_assert=>assert_equals( exp = '05'           act = ls-nro_grupo ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true      act = ls-campos_completos ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true      act = ls-tiene_sep_final ).
  ENDMETHOD.

  METHOD tolera_sin_sep_final.
    DATA(lo) = NEW zcl_arba_ret_parser( ).
    lo->parse_file(
      EXPORTING iv_content = |R;25022026;01032026;31032026;20000000028;D;N;N;0,00;05|
      IMPORTING et_records = DATA(lt) ).
    DATA(ls) = lt[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = abap_true  act = ls-campos_completos ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = ls-tiene_sep_final ).
  ENDMETHOD.

  METHOD cuenta_lineas_vacias.
    DATA(lo) = NEW zcl_arba_ret_parser( ).
    lo->parse_file(
      EXPORTING iv_content = |R;25022026;01032026;31032026;20000000028;D;N;N;0,00;05;|
                          && cl_abap_char_utilities=>cr_lf && ||
                          && cl_abap_char_utilities=>cr_lf
                          && |R;25022026;01032026;31032026;20000000031;D;N;N;1,00;05;|
      IMPORTING et_records = DATA(lt) ev_lineas_vacias = DATA(lv_vacias) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lv_vacias ).
  ENDMETHOD.

  METHOD parsea_caba.
    " CABA: sin regimen inicial; CUIT col 4; alicuota de RETENCIONES col 9 (col 8 = percepciones).
    DATA(lo) = NEW zcl_arba_ret_parser( ).
    lo->set_provincia( 'CABA' ).
    lo->parse_file(
      EXPORTING iv_content = |28072026;01082026;31082026;20383564361;D;S;N;4,00;3,00;00;00;FUEZ BERNARDO M|
      IMPORTING et_records = DATA(lt) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( lt ) ).
    DATA(ls) = lt[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = 'CABA'        act = ls-provincia ).
    cl_abap_unit_assert=>assert_equals( exp = '20383564361' act = ls-cuit ).
    cl_abap_unit_assert=>assert_equals( exp = '3,00'        act = ls-alicuota_txt ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true     act = ls-campos_completos ).
  ENDMETHOD.
ENDCLASS.

"======================================================================
" Pruebas del validador
"======================================================================
CLASS ltcl_validator DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS valido             FOR TESTING.
    METHODS rechaza_regimen    FOR TESTING.
    METHODS rechaza_cuit       FOR TESTING.
    METHODS rechaza_alicuota   FOR TESTING.
    METHODS convierte_alicuota FOR TESTING.
    METHODS acepta_decimales_variables FOR TESTING.
    METHODS rec IMPORTING iv_reg TYPE c iv_cuit TYPE c iv_alic TYPE c
                RETURNING VALUE(rs) TYPE zcl_arba_ret_parser=>ty_record.
ENDCLASS.

CLASS ltcl_validator IMPLEMENTATION.
  METHOD rec.
    rs-nro_linea        = 1.
    rs-provincia        = 'ARBA'.   " estos tests son formato ARBA (con regimen 'R')
    rs-regimen          = iv_reg.
    rs-cuit             = iv_cuit.
    rs-alicuota_txt     = iv_alic.
    rs-campos_completos = abap_true.
    rs-tiene_sep_final  = abap_true.
    rs-cant_campos      = 11.
  ENDMETHOD.

  METHOD valido.
    DATA(lo) = NEW zcl_arba_ret_validator( ).
    DATA(r) = lo->validate_record( rec( iv_reg = 'R' iv_cuit = '20000000028' iv_alic = '3,25' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = r-es_valido ).
    cl_abap_unit_assert=>assert_equals( exp = '3.25'    act = r-alicuota ).
  ENDMETHOD.

  METHOD rechaza_regimen.
    DATA(lo) = NEW zcl_arba_ret_validator( ).
    DATA(r) = lo->validate_record( rec( iv_reg = 'P' iv_cuit = '20000000028' iv_alic = '3,00' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = r-es_valido ).
    cl_abap_unit_assert=>assert_equals( exp = 'REV'      act = r-estado ).
  ENDMETHOD.

  METHOD rechaza_cuit.
    DATA(lo) = NEW zcl_arba_ret_validator( ).
    DATA(r) = lo->validate_record( rec( iv_reg = 'R' iv_cuit = '2000ABC0028' iv_alic = '3,00' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = r-es_valido ).
    cl_abap_unit_assert=>assert_equals( exp = 'REV'      act = r-estado ).
  ENDMETHOD.

  METHOD rechaza_alicuota.
    DATA(lo) = NEW zcl_arba_ret_validator( ).
    " Fuera de rango (tope 15,00)
    DATA(r) = lo->validate_record( rec( iv_reg = 'R' iv_cuit = '20000000028' iv_alic = '99,99' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = r-es_valido ).
  ENDMETHOD.

  METHOD convierte_alicuota.
    DATA(lo) = NEW zcl_arba_ret_validator( ).
    DATA(r) = lo->validate_record( rec( iv_reg = 'R' iv_cuit = '20000000028' iv_alic = '0,40' ) ).
    cl_abap_unit_assert=>assert_equals( exp = '0.40' act = r-alicuota ).
  ENDMETHOD.

  METHOD acepta_decimales_variables.
    " Santa Fe: alicuotas con 0 o 1 decimal ("2", "0,6") ahora son validas y se convierten a X,YY.
    DATA(lo) = NEW zcl_arba_ret_validator( ).
    DATA(r1) = lo->validate_record( rec( iv_reg = 'R' iv_cuit = '20000000028' iv_alic = '2' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = r1-es_valido ).
    cl_abap_unit_assert=>assert_equals( exp = '2.00'    act = r1-alicuota ).
    DATA(r2) = lo->validate_record( rec( iv_reg = 'R' iv_cuit = '20000000028' iv_alic = '0,6' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = r2-es_valido ).
    cl_abap_unit_assert=>assert_equals( exp = '0.60'    act = r2-alicuota ).
  ENDMETHOD.
ENDCLASS.

"======================================================================
" Pruebas del orquestador (con dobles)
"======================================================================
CLASS ltcl_proc DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS mo_app RETURNING VALUE(ro) TYPE REF TO zcl_arba_ret_proc_app.
    METHODS to_x IMPORTING iv_s TYPE string RETURNING VALUE(rv) TYPE xstring.

    METHODS simula_caso1_y_rechazo FOR TESTING.
    METHODS no_encontrado          FOR TESTING.
    METHODS duplicado_en_sap       FOR TESTING.
    METHODS pendiente_config       FOR TESTING.
    METHODS dedup_identico         FOR TESTING.
    METHODS dedup_contradictorio   FOR TESTING.
    METHODS sync_completa_caso3       FOR TESTING.
    METHODS fuera_padron_usa_set      FOR TESTING.
    METHODS fuera_padron_manual_alic  FOR TESTING.
    METHODS real_no_actualiza_maestro FOR TESTING.
    METHODS sf_cambio_regimen         FOR TESTING.
ENDCLASS.

CLASS ltcl_proc IMPLEMENTATION.
  METHOD mo_app.
    ro = NEW zcl_arba_ret_proc_app(
      io_determinador = NEW ltd_determinador( )
      io_bp_updater   = NEW ltd_bp( ) ).
  ENDMETHOD.

  METHOD to_x.
    rv = cl_abap_conv_codepage=>create_out( )->convert( source = iv_s ).
  ENDMETHOD.

  METHOD simula_caso1_y_rechazo.
    DATA(lv_txt) = |R;25022026;01032026;31032026;20000000028;D;N;N;3,00;05;|
                && cl_abap_char_utilities=>cr_lf
                && |P;25022026;01032026;31032026;20000000031;D;N;N;3,00;05;|.
    mo_app( )->procesar(
      EXPORTING iv_content = to_x( lv_txt ) iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ev_estado_ejec = DATA(lv_estado) ).

    cl_abap_unit_assert=>assert_equals( exp = 2 act = ls_kpi-leidos ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-actualizados ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-rechazados ).
    cl_abap_unit_assert=>assert_equals( exp = 'OK' act = lv_estado ).

    DATA(ls_act) = lt_log[ estado = 'ACT' ].
    cl_abap_unit_assert=>assert_equals( exp = '1' act = ls_act-caso ).
  ENDMETHOD.

  METHOD no_encontrado.
    mo_app( )->procesar(
      EXPORTING iv_content = to_x( |R;25022026;01032026;31032026;20000000099;D;N;N;3,00;05;| )
                iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-no_encontrados ).
  ENDMETHOD.

  METHOD duplicado_en_sap.
    mo_app( )->procesar(
      EXPORTING iv_content = to_x( |R;25022026;01032026;31032026;20000000088;D;N;N;3,00;05;| )
                iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-rechazados ).
    cl_abap_unit_assert=>assert_equals( exp = 'DUP' act = lt_log[ 1 ]-estado ).
  ENDMETHOD.

  METHOD pendiente_config.
    mo_app( )->procesar(
      EXPORTING iv_content = to_x( |R;25022026;01032026;31032026;20000000028;D;N;N;9,99;05;| )
                iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-pendiente_config ).
    cl_abap_unit_assert=>assert_equals( exp = 'PCF' act = lt_log[ 1 ]-estado ).
  ENDMETHOD.

  METHOD dedup_identico.
    " Mismo CUIT dos veces con la misma alicuota -> una accion + un omitido (EF seccion 7)
    DATA(lv_txt) = |R;25022026;01032026;31032026;20000000028;D;N;N;3,00;05;|
                && cl_abap_char_utilities=>cr_lf
                && |R;25022026;01032026;31032026;20000000028;D;N;N;3,00;05;|.
    mo_app( )->procesar(
      EXPORTING iv_content = to_x( lv_txt ) iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-actualizados ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = ls_kpi-omitidos ).
  ENDMETHOD.

  METHOD dedup_contradictorio.
    " Mismo CUIT con distinta alicuota -> se rechazan ambas lineas (EF seccion 7)
    DATA(lv_txt) = |R;25022026;01032026;31032026;20000000028;D;N;N;3,00;05;|
                && cl_abap_char_utilities=>cr_lf
                && |R;25022026;01032026;31032026;20000000028;D;N;N;5,00;05;|.
    mo_app( )->procesar(
      EXPORTING iv_content = to_x( lv_txt ) iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = ls_kpi-rechazados ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = ls_kpi-actualizados ).
  ENDMETHOD.

  METHOD sync_completa_caso3.
    " Padron con un CUIT (proveedor 0000001000). En sincronizacion completa, el
    " proveedor 0000009999 tiene el tipo pero NO esta en el padron -> Caso 3:
    " se le asigna el indicador de alicuota maxima (R6).
    mo_app( )->procesar(
      EXPORTING iv_content     = to_x( |R;25022026;01032026;31032026;20000000028;D;N;N;3,00;05;| )
                iv_sociedad    = '1000'
                iv_tipo_ret    = 'R1'
                iv_solo_padron = abap_false
                iv_simular     = abap_true
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ).

    " Debe existir una fila Caso 3 para el proveedor fuera de padron
    DATA(ls_c3) = lt_log[ caso = '3' ].
    cl_abap_unit_assert=>assert_equals( exp = '0000009999' act = ls_c3-proveedor ).
    cl_abap_unit_assert=>assert_equals( exp = 'R6'         act = ls_c3-indicador_nuevo ).
    cl_abap_unit_assert=>assert_equals( exp = 'ACT'        act = ls_c3-estado ).
  ENDMETHOD.

  METHOD fuera_padron_usa_set.
    " Regresion del bug del Application Job: procesar_fuera_padron debe EXCLUIR a los
    " proveedores de it_sup_procesados, sin depender de ct_log (que en el job llega VACIO
    " porque el log se persiste y descarta por lote). Con ct_log vacio pero el set conteniendo
    " a 0000001000, ese proveedor NO debe recibir "fuera de padron"; solo 0000009999 (Caso 3).
    DATA lt_log TYPE zcl_arba_ret_proc_app=>ty_log_tt.   " vacio, como lo recibe en el job
    DATA ls_kpi TYPE zcl_arba_ret_proc_app=>ty_kpi.
    DATA lt_set TYPE zcl_arba_ret_proc_app=>ty_sup_set.
    INSERT '0000001000' INTO TABLE lt_set.

    mo_app( )->procesar_fuera_padron(
      EXPORTING iv_sociedad       = '1000'
                iv_tipo_ret       = 'R1'
                iv_ind_fuera      = ''
                iv_prov_desde     = ''
                iv_prov_hasta     = ''
                iv_simular        = abap_true
                it_sup_procesados = lt_set
      CHANGING  ct_log            = lt_log
                cs_kpi            = ls_kpi ).

    " El doble get_proveedores_con_retencion devuelve 0000001000 (excluido) y 0000009999.
    cl_abap_unit_assert=>assert_equals( exp = 1            act = lines( lt_log ) ).
    cl_abap_unit_assert=>assert_equals( exp = '0000009999' act = lt_log[ 1 ]-proveedor ).
    cl_abap_unit_assert=>assert_equals( exp = '3'          act = lt_log[ 1 ]-caso ).
    cl_abap_unit_assert=>assert_equals( exp = 'R6'         act = lt_log[ 1 ]-indicador_nuevo ).
  ENDMETHOD.

  METHOD fuera_padron_manual_alic.
    " Fix: con indicador "fuera de padron" INFORMADO manualmente, la alicuota del log debe
    " derivarse del indicador (no quedar en 0,00), para que el .txt exportado la lleve bien.
    DATA lt_log TYPE zcl_arba_ret_proc_app=>ty_log_tt.
    DATA ls_kpi TYPE zcl_arba_ret_proc_app=>ty_kpi.
    DATA lt_set TYPE zcl_arba_ret_proc_app=>ty_sup_set.
    INSERT '0000001000' INTO TABLE lt_set.

    mo_app( )->procesar_fuera_padron(
      EXPORTING iv_sociedad       = '1000'
                iv_tipo_ret       = 'R1'
                iv_ind_fuera      = 'R3'
                iv_prov_desde     = ''
                iv_prov_hasta     = ''
                iv_simular        = abap_true
                it_sup_procesados = lt_set
      CHANGING  ct_log            = lt_log
                cs_kpi            = ls_kpi ).

    DATA lv_exp_alic TYPE p LENGTH 5 DECIMALS 2.
    lv_exp_alic = '3.00'.
    cl_abap_unit_assert=>assert_equals( exp = 1            act = lines( lt_log ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'R3'         act = lt_log[ 1 ]-indicador_nuevo ).
    cl_abap_unit_assert=>assert_equals( exp = lv_exp_alic  act = lt_log[ 1 ]-alicuota_nueva ).
  ENDMETHOD.

  METHOD real_no_actualiza_maestro.
    " El RAP ya NO actualiza el maestro: una corrida REAL (simular=false) DETERMINA y loguea ACT
    " sin llamar a actualizar_retencion (que haria el self-call HTTP). El apply (maestro + PAs) lo
    " hace la app estandar + BAdI con el .txt exportado. El doble ltd_bp NO redefine
    " actualizar_retencion: si el codigo la llamara, el test intentaria el HTTP y fallaria -> blindaje.
    mo_app( )->procesar(
      EXPORTING iv_content  = to_x( |R;25022026;01032026;31032026;20000000028;D;N;N;3,00;05;| )
                iv_sociedad = '1000' iv_tipo_ret = 'R1' iv_simular = abap_false
      IMPORTING et_log = DATA(lt_log) es_kpi = DATA(ls_kpi) ev_estado_ejec = DATA(lv_estado) ).

    cl_abap_unit_assert=>assert_equals( exp = 1     act = ls_kpi-actualizados ).
    cl_abap_unit_assert=>assert_equals( exp = 0     act = ls_kpi-error_tecnico ).
    cl_abap_unit_assert=>assert_equals( exp = 'ACT' act = lt_log[ 1 ]-estado ).
    cl_abap_unit_assert=>assert_equals( exp = 'OK'  act = lv_estado ).
  ENDMETHOD.

  METHOD sf_cambio_regimen.
    " Santa Fe: un proveedor con el tipo que aparece en el OTRO universo del archivo (cambio de
    " regimen) NO recibe fuera de padron -> se marca 'REG' y se EXCLUYE del export; la app estandar
    " lo borra por AUSENCIA (maestro + partidas). El que NO esta en el otro universo cae en fuera de
    " padron normal (Caso 3).
    DATA lt_log  TYPE zcl_arba_ret_proc_app=>ty_log_tt.
    DATA ls_kpi  TYPE zcl_arba_ret_proc_app=>ty_kpi.
    DATA lt_set  TYPE zcl_arba_ret_proc_app=>ty_sup_set.
    DATA lt_otro TYPE zcl_arba_ret_proc_app=>ty_cuit_set.
    INSERT '20999999999' INTO TABLE lt_otro.   " 0000009999 aparece en el otro universo

    mo_app( )->procesar_fuera_padron(
      EXPORTING iv_sociedad       = '1000'
                iv_tipo_ret       = '21'
                iv_ind_fuera      = '23'
                iv_prov_desde     = ''
                iv_prov_hasta     = ''
                iv_simular        = abap_true
                it_sup_procesados = lt_set
                iv_provincia      = 'SF'
                it_otro_universo  = lt_otro
      CHANGING  ct_log            = lt_log
                cs_kpi            = ls_kpi ).

    DATA(ls_reg) = VALUE #( lt_log[ estado = 'REG' ] OPTIONAL ).
    cl_abap_unit_assert=>assert_equals( exp = '0000009999' act = ls_reg-proveedor ).
    cl_abap_unit_assert=>assert_equals( exp = 'R'          act = ls_reg-caso ).
    DATA(ls_c3) = VALUE #( lt_log[ caso = '3' ] OPTIONAL ).
    cl_abap_unit_assert=>assert_equals( exp = '0000001000' act = ls_c3-proveedor ).
  ENDMETHOD.
ENDCLASS.


"======================================================================
" Pruebas del exporter: el layout del .txt debe respetar la provincia
" (la app estandar lee CUIT/alicuota por POSICION: ARBA col 5 / CABA col 4).
"======================================================================
CLASS ltcl_exporter DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS arba_cuit_col5 FOR TESTING.
    METHODS caba_cuit_col4 FOR TESTING.
ENDCLASS.

CLASS ltcl_exporter IMPLEMENTATION.
  METHOD arba_cuit_col5.
    DATA(lo) = NEW zcl_arba_ret_exporter( ).
    DATA(lt) = VALUE zcl_arba_ret_exporter=>ty_rows( ( cuit = '20383564361' alicuota = '4.00' ) ).
    SPLIT lo->build_txt( it_rows = lt iv_provincia = 'ARBA' ) AT ';' INTO TABLE DATA(lt_c).
    cl_abap_unit_assert=>assert_equals( exp = '20383564361' act = lt_c[ 5 ] ).   " CUIT col 5
    cl_abap_unit_assert=>assert_equals( exp = '4,00'        act = lt_c[ 9 ] ).   " alicuota col 9
  ENDMETHOD.

  METHOD caba_cuit_col4.
    DATA(lo) = NEW zcl_arba_ret_exporter( ).
    DATA(lt) = VALUE zcl_arba_ret_exporter=>ty_rows( ( cuit = '20383564361' alicuota = '4.50' ) ).
    SPLIT lo->build_txt( it_rows = lt iv_provincia = 'CABA' ) AT ';' INTO TABLE DATA(lt_c).
    cl_abap_unit_assert=>assert_equals( exp = '20383564361' act = lt_c[ 4 ] ).   " CUIT col 4
    cl_abap_unit_assert=>assert_equals( exp = '4,50'        act = lt_c[ 9 ] ).   " alicuota col 9
  ENDMETHOD.
ENDCLASS.

