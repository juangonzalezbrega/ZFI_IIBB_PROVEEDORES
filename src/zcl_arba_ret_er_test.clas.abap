"! Prueba de consola (F9 en ADT) para Entre Rios: NO escribe nada.
"! 1) lista las filas de ZTFI_RET_TUC del tipo (via ZI_ARBA_RET_TUC_CLCM) y el % SPRO de cada codigo;
"! 2) corre ZCL_ARBA_RET_ER_DETERMINADOR con las combinaciones del padron de prueba;
"! 3) parsea un mini-padron embebido con ZCL_ARBA_RET_ER_PARSER.
"! Molde: ZCL_ARBA_RET_TEST_WHT (zcl_arba_ret_test_wht.clas.abap:7, 26).
"! OJO: F9 corre en el mandante del proyecto ADT (080). ZTFI_RET_TUC y los indicadores 08 son customizing
"! del 100: en el 080 las partes 1 y 2 dan 0 filas / PCF (normal). La parte 3 (parser) vale en cualquier mandante.
CLASS zcl_arba_ret_er_test DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PRIVATE SECTION.
    CONSTANTS c_tipo TYPE zcl_arba_ret_determinador=>ty_wht_type VALUE '08'.
ENDCLASS.



CLASS ZCL_ARBA_RET_ER_TEST IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    " 1) Customizing
    SELECT withholdingtaxcode, withholdingtaxpercent, convmult
      FROM zi_arba_ret_tuc_clcm
      WHERE country = 'AR' AND withholdingtaxtype = @c_tipo
      ORDER BY withholdingtaxcode
      INTO TABLE @DATA(lt_z).
    out->write( |ZTFI_RET_TUC tipo { c_tipo }: { lines( lt_z ) } filas| ).
    DATA(lo_det) = NEW zcl_arba_ret_er_determinador( ).
    " ev_estado es TYPE c generico: no admite DATA( ) inline; variable con largo fijo (como
    " zcl_arba_ret_sal_param.clas.abap:25-28).
    DATA lv_e TYPE c LENGTH 3.
    LOOP AT lt_z INTO DATA(ls_z).
      CLEAR lv_e.
      lo_det->alicuota( EXPORTING iv_tipo_ret = c_tipo iv_indicador = ls_z-withholdingtaxcode
                        IMPORTING ev_alicuota = DATA(lv_spro) ev_estado = lv_e ).
      out->write( |  { ls_z-withholdingtaxcode } MA='{ ls_z-convmult }' Rate { ls_z-withholdingtaxpercent DECIMALS = 4 }| &&
                  | / SPRO { COND string( WHEN lv_e IS INITIAL THEN |{ lv_spro DECIMALS = 2 }| ELSE `NO EXISTE` ) }| ).
    ENDLOOP.
    out->write( |tiene_customizing = { lo_det->tiene_customizing( c_tipo ) }| ).

    " 2) Determinacion (esperado: C3->01, D3->02, D0->04, P0->04, C0->05, C0,1->06, C0,25/D1/D0,1/C0,01 -> PCF)
    TYPES: BEGIN OF ty_caso, tipo TYPE c LENGTH 1, alic TYPE zcl_arba_ret_tuc_determinador=>ty_alicuota, END OF ty_caso.
    DATA lt_casos TYPE STANDARD TABLE OF ty_caso WITH EMPTY KEY.
    lt_casos = VALUE #( ( tipo = 'C' alic = '3' )    ( tipo = 'D' alic = '3' )    ( tipo = 'D' alic = '0' )
                        ( tipo = 'P' alic = '0' )    ( tipo = 'C' alic = '0' )    ( tipo = 'C' alic = '0.1' )
                        ( tipo = 'C' alic = '0.25' ) ( tipo = 'D' alic = '1' )    ( tipo = 'D' alic = '0.1' )
                        ( tipo = 'C' alic = '0.01' ) ( tipo = 'D' alic = '1.5' ) ).
    DATA lv_est TYPE c LENGTH 3.
    LOOP AT lt_casos INTO DATA(ls_c).
      lo_det->determinar( EXPORTING iv_tipo_ret = c_tipo iv_tipo_contrib = ls_c-tipo iv_alicuota = ls_c-alic
                          IMPORTING ev_indicador = DATA(lv_ind) ev_alicuota = DATA(lv_al)
                                    ev_estado = lv_est ev_mensaje = DATA(lv_msg) ).
      out->write( |  { ls_c-tipo } { ls_c-alic DECIMALS = 4 } -> { COND string( WHEN lv_est IS INITIAL
                    THEN |{ lv_ind } ({ lv_al DECIMALS = 2 })| ELSE |{ lv_est }: { lv_msg }| ) }| ).
    ENDLOOP.

    " 3) Parser con un mini-padron (encabezado + linea vacia + fecha de 7 digitos + REV)
    DATA(lv_txt) = |FECHA PUBLICACION;FECHA VIGENCIA DESDE;FECHA VIGENCIA HASTA;CUIT;TIPO;MARCA;MA;AP;AR;GP;GR;RAZON\r\n| &&
                   |26082026;1092026;30092026;20032542566;C;N;N;3;3;0;0;LOZA HORACIO ALFREDO\r\n| &&
                   |;;;;;;;;;;;\r\n| &&
                   |26082026;1092026;30092026;20042790800;D;B;S;6;6;0;0;BLASCHI COSME ALBERTO\r\n| &&
                   |26082026;1092026;30092026;2004279080;X;Q;S;6;6;0;0;CUIT CORTO\r\n|.
    DATA(lv_x) = cl_abap_conv_codepage=>create_out( codepage = `ISO-8859-1` )->convert( source = lv_txt ).
    NEW zcl_arba_ret_er_parser( )->parse_file( EXPORTING iv_archivo       = lv_x
                                               IMPORTING et_records       = DATA(lt_rec)
                                                         ev_lineas_vacias = DATA(lv_vac)
                                                         ev_encabezado    = DATA(lv_enc) ).
    out->write( |Parser: { lines( lt_rec ) } registros, { lv_vac } vacias, encabezado = { lv_enc }| ).
    LOOP AT lt_rec INTO DATA(ls_r).
      out->write( |  linea { ls_r-nro_linea } CUIT { ls_r-cuit } { ls_r-tipo }/{ ls_r-marca_alta } alic { ls_r-alic_ret DECIMALS = 4 }| &&
                  | desde { ls_r-vig_desde } valido={ ls_r-es_valido } { ls_r-mensaje }| ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
