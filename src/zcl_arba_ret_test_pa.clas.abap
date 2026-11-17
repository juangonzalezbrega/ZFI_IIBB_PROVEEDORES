"! Clase utilitaria TEMPORAL de DIAGNOSTICO (EF 6.5 - partidas abiertas).
"! Correr con F9 en ADT (Run As -> ABAP Application (Console)). NO dispara ningun ajuste.
"! Para el proveedor de prueba:
"!   1) CUIT + codigo de retencion en el MAESTRO (I_SupplierWithHoldingTax)
"!   2) PARTIDAS ABIERTAS (I_WithholdingTaxItem): compara COD partida vs COD maestro por
"!      (sociedad, tipo) y marca solo las DESINCRONIZADas (las que quedaron con el viejo)
"!   3) preview del COD que corresponderia por alicuota (zcl_arba_ret_determinador)
"! Uso: correr ANTES y DESPUES de la app "Update Tax Code and Open Items - Region" para
"! verificar que las partidas abiertas pasan a coincidir con el maestro. Borrar tras validar.
"! NOTA: las partidas se leen por acceso DINAMICO; si I_WithholdingTaxItem no estuviera
"! liberada para ABAP en el release, la clase activa igual y avisa (bloque 2 capturado).
CLASS zcl_arba_ret_test_pa DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

protected section.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_master,
             companycode TYPE c LENGTH 4,
             wht_type    TYPE c LENGTH 2,
             wht_code    TYPE c LENGTH 2,
           END OF ty_master.
    TYPES tt_master TYPE SORTED TABLE OF ty_master WITH UNIQUE KEY companycode wht_type.

    " >>> Ajustar al caso de prueba <<<
    CONSTANTS c_supplier  TYPE c LENGTH 10 VALUE '0070000002'.
    CONSTANTS c_sociedad  TYPE bukrs       VALUE '2384'.
    CONSTANTS c_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type VALUE '02'.
    CONSTANTS c_categoria TYPE c LENGTH 4  VALUE 'AR1A'.
    CONSTANTS c_alicuota  TYPE string      VALUE '0.00'.

    METHODS maestro    IMPORTING out              TYPE REF TO if_oo_adt_classrun_out
                       RETURNING VALUE(rt_master) TYPE tt_master.
    METHODS partidas   IMPORTING out       TYPE REF TO if_oo_adt_classrun_out
                                 it_master TYPE tt_master.
    METHODS determinar IMPORTING out TYPE REF TO if_oo_adt_classrun_out.
ENDCLASS.



CLASS ZCL_ARBA_RET_TEST_PA IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    out->write( |### Diagnostico retencion proveedor { c_supplier } (soc { c_sociedad }, tipo { c_tipo_ret }) ###| ).
    out->write( `` ).
    DATA(lt_master) = maestro( out ).
    out->write( `` ).
    partidas( out = out it_master = lt_master ).
    out->write( `` ).
    determinar( out ).
  ENDMETHOD.


  METHOD maestro.
    out->write( '=== 1) CUIT + MAESTRO de retencion ===' ).

    SELECT SINGLE bptaxnumber
      FROM i_businesspartnertaxnumber
      WHERE businesspartner = @c_supplier
        AND bptaxtype       = @c_categoria
      INTO @DATA(lv_cuit).
    out->write( |CUIT (I_BusinessPartnerTaxNumber / { c_categoria }): { lv_cuit }| ).

    SELECT supplier, companycode, withholdingtaxtype,
           withholdingtaxcode, iswithholdingtaxsubject
      FROM i_supplierwithholdingtax
      WHERE supplier = @c_supplier
      INTO TABLE @DATA(lt_m).
    IF lt_m IS INITIAL.
      out->write( 'Maestro: SIN registros de retencion para el proveedor.' ).
      RETURN.
    ENDIF.
    LOOP AT lt_m INTO DATA(ls_m).
      out->write( |Maestro: soc { ls_m-companycode } tipo { ls_m-withholdingtaxtype } | &&
                  |-> COD { ls_m-withholdingtaxcode } (sujeto { ls_m-iswithholdingtaxsubject })| ).
      INSERT VALUE #( companycode = ls_m-companycode
                      wht_type    = ls_m-withholdingtaxtype
                      wht_code    = ls_m-withholdingtaxcode ) INTO TABLE rt_master.
    ENDLOOP.
  ENDMETHOD.


  METHOD partidas.
    out->write( '=== 2) PARTIDAS ABIERTAS (I_WithholdingTaxItem) vs MAESTRO ===' ).
    out->write( 'Solo abiertas (sin compensar). Se listan SOLO las desincronizadas (COD != maestro).' ).

    TRY.
        DATA lr_tab TYPE REF TO data.
        DATA lr_wa  TYPE REF TO data.
        CREATE DATA lr_tab TYPE TABLE OF ('I_WITHHOLDINGTAXITEM').
        CREATE DATA lr_wa  TYPE ('I_WITHHOLDINGTAXITEM').
        FIELD-SYMBOLS <t> TYPE ANY TABLE.
        ASSIGN lr_tab->* TO <t>.
        DATA(lo_str) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data_ref( lr_wa ) ).

        " El nombre del campo de proveedor puede variar por release: se ubica por RTTI.
        DATA lv_field TYPE string.
        LOOP AT lo_str->components INTO DATA(ls_c).
          IF ls_c-name CS 'SUPPLIER' OR ls_c-name = 'BUSINESSPARTNER'.
            lv_field = ls_c-name.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_field IS INITIAL.
          out->write( 'Sin campo de proveedor directo. Campos disponibles:' ).
          LOOP AT lo_str->components INTO ls_c.
            out->write( |  { ls_c-name }| ).
          ENDLOOP.
          RETURN.
        ENDIF.

        DATA(lv_where) = |{ lv_field } = '{ c_supplier }'|.
        SELECT * FROM ('I_WITHHOLDINGTAXITEM') WHERE (lv_where) INTO TABLE @<t> UP TO 2000 ROWS.

        DATA lv_cc     TYPE c LENGTH 4.
        DATA lv_ty     TYPE c LENGTH 2.
        DATA lv_cd     TYPE c LENGTH 2.
        DATA lv_clr    TYPE c LENGTH 8.
        DATA lv_doc    TYPE c LENGTH 10.
        DATA lv_open   TYPE i.
        DATA lv_ok     TYPE i.
        DATA lv_desync TYPE i.
        FIELD-SYMBOLS <row> TYPE any.
        FIELD-SYMBOLS <f>   TYPE any.

        LOOP AT <t> ASSIGNING <row>.
          CLEAR: lv_cc, lv_ty, lv_cd, lv_clr, lv_doc.
          ASSIGN COMPONENT 'COMPANYCODE'        OF STRUCTURE <row> TO <f>. IF sy-subrc = 0. lv_cc  = <f>. ENDIF.
          ASSIGN COMPONENT 'WITHHOLDINGTAXTYPE' OF STRUCTURE <row> TO <f>. IF sy-subrc = 0. lv_ty  = <f>. ENDIF.
          ASSIGN COMPONENT 'WITHHOLDINGTAXCODE' OF STRUCTURE <row> TO <f>. IF sy-subrc = 0. lv_cd  = <f>. ENDIF.
          ASSIGN COMPONENT 'CLEARINGDATE'       OF STRUCTURE <row> TO <f>. IF sy-subrc = 0. lv_clr = <f>. ENDIF.
          ASSIGN COMPONENT 'ACCOUNTINGDOCUMENT' OF STRUCTURE <row> TO <f>. IF sy-subrc = 0. lv_doc = <f>. ENDIF.

          " Solo partidas ABIERTAS (sin fecha de compensacion)
          IF NOT ( lv_clr IS INITIAL OR lv_clr = '00000000' ).
            CONTINUE.
          ENDIF.
          lv_open = lv_open + 1.

          DATA(lv_master) = VALUE #( it_master[ companycode = lv_cc wht_type = lv_ty ]-wht_code OPTIONAL ).
          IF lv_cd = lv_master.
            lv_ok = lv_ok + 1.
          ELSE.
            lv_desync = lv_desync + 1.
            out->write( |DESYNC: doc { lv_doc } soc { lv_cc } tipo { lv_ty } | &&
                        |-> partida COD { lv_cd } != maestro COD { lv_master }| ).
          ENDIF.
        ENDLOOP.

        out->write( `` ).
        out->write( |Partidas ABIERTAS: { lv_open }   OK: { lv_ok }   DESINCRONIZADAS: { lv_desync }| ).

      CATCH cx_root INTO DATA(lx).
        out->write( |No se pudo leer I_WithholdingTaxItem: { lx->get_text( ) }| ).
        out->write( 'Puede no estar liberada para ABAP en este release. Revisa las partidas en la' ).
        out->write( 'app Fiori "Manage Withholding Tax Items".' ).
    ENDTRY.
  ENDMETHOD.


  METHOD determinar.
    out->write( '=== 3) DETERMINACION (preview): que COD corresponde a la alicuota ===' ).
    DATA lv_alic TYPE p LENGTH 5 DECIMALS 2.
    lv_alic = c_alicuota.
    DATA lv_ind TYPE zcl_arba_ret_determinador=>ty_wht_code.
    DATA lv_est TYPE c LENGTH 3.
    DATA lv_msg TYPE string.
    NEW zcl_arba_ret_determinador( )->determinar_indicador(
      EXPORTING iv_tipo_ret  = c_tipo_ret
                iv_alicuota  = lv_alic
      IMPORTING ev_indicador = lv_ind
                ev_estado    = lv_est
                ev_mensaje   = lv_msg ).
    out->write( |Alicuota { lv_alic } -> COD que se asignaria: { lv_ind } | &&
                |(estado '{ lv_est }') { lv_msg }| ).
  ENDMETHOD.
ENDCLASS.
