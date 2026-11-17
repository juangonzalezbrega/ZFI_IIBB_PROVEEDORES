CLASS zcl_arba_ret_test_wht DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    " Alicuotas representadas como ENTEROS (porcentaje x 10000) para comparar sin literales packed.
    TYPES ty_key_tab TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    METHODS verdict
      IMPORTING iv_type   TYPE clike
                iv_count  TYPE i
                iv_has_cl TYPE abap_bool
                iv_has_cm TYPE abap_bool
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_TEST_WHT IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    " Alicuotas EXCLUSIVAS de cada rama (x 10000), segun la config de referencia del padron Tucuman:
    " si una de estas alicuotas aparece en un tipo, ese tipo contiene codigos de esa rama.
    "   CL: 0,2500 1,8000 3,0000 3,5000 3,7500 4,0000 4,5000 4,7500
    "   CM: 0,1250 0,3750 0,5000 0,9000 1,2500 1,7500 1,8750 2,2500 2,3750
    DATA(lt_cl) = VALUE ty_key_tab( ( 2500 ) ( 18000 ) ( 30000 ) ( 35000 )
                                    ( 37500 ) ( 40000 ) ( 45000 ) ( 47500 ) ).
    DATA(lt_cm) = VALUE ty_key_tab( ( 1250 ) ( 3750 ) ( 5000 ) ( 9000 )
                                    ( 12500 ) ( 17500 ) ( 18750 ) ( 22500 ) ( 23750 ) ).

    SELECT withholdingtaxtype    AS wtype,
           withholdingtaxcode    AS wcode,
           withholdingtaxpercent AS wpct
      FROM i_extendedwhldgtaxcode
      WHERE country = 'AR'
      ORDER BY withholdingtaxtype, withholdingtaxcode
      INTO TABLE @DATA(lt).

    IF lt IS INITIAL.
      out->write( 'Sin datos en I_ExtendedWhldgTaxCode para country = AR. Revisar release / autorizacion.' ).
      RETURN.
    ENDIF.

    out->write( |Config withholding tax AR ({ lines( lt ) } codigos). Un veredicto por tipo:| ).
    out->write( `` ).

    DATA lv_type   TYPE c LENGTH 2.
    DATA lv_has_cl TYPE abap_bool.
    DATA lv_has_cm TYPE abap_bool.
    DATA lv_count  TYPE i.
    DATA lv_key    TYPE i.

    LOOP AT lt INTO DATA(ls).
      IF ls-wtype <> lv_type.
        IF lv_type IS NOT INITIAL.
          out->write( verdict( iv_type = lv_type iv_count = lv_count iv_has_cl = lv_has_cl iv_has_cm = lv_has_cm ) ).
          out->write( `` ).
        ENDIF.
        lv_type = ls-wtype.
        CLEAR: lv_has_cl, lv_has_cm, lv_count.
        out->write( |=== Tipo { lv_type } ===| ).
      ENDIF.
      lv_count += 1.
      out->write( |  { ls-wcode }  ->  { ls-wpct }| ).
      lv_key = ls-wpct * 10000.
      IF line_exists( lt_cl[ table_line = lv_key ] ). lv_has_cl = abap_true. ENDIF.
      IF line_exists( lt_cm[ table_line = lv_key ] ). lv_has_cm = abap_true. ENDIF.
    ENDLOOP.
    " veredicto del ultimo tipo
    out->write( verdict( iv_type = lv_type iv_count = lv_count iv_has_cl = lv_has_cl iv_has_cm = lv_has_cm ) ).
  ENDMETHOD.


  METHOD verdict.
    IF iv_has_cl = abap_true AND iv_has_cm = abap_true.
      rv = |>> Tipo { iv_type } ({ iv_count } cod.): contiene CL y CM en un UNICO tipo | &&
           |-> hay que desambiguar (rango de codigo o mini-tabla).|.
    ELSEIF iv_has_cl = abap_true.
      rv = |>> Tipo { iv_type } ({ iv_count } cod.): coincide con la rama CL (Contribuyente Local).|.
    ELSEIF iv_has_cm = abap_true.
      rv = |>> Tipo { iv_type } ({ iv_count } cod.): coincide con la rama CM (Convenio Multilateral).|.
    ELSE.
      rv = |>> Tipo { iv_type } ({ iv_count } cod.): no coincide con alicuotas Tucuman (probablemente otro impuesto).|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
