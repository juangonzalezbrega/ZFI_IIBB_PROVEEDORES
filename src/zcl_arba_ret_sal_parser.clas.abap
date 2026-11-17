"! Parser del padron DGR Salta: TAB, 5 columnas CUIT | DENOMINACION | CONDICION | ACT EXENTAS | CERT NRP.
"! Solo usa CUIT y CONDICION. Encabezado opcional: la 1ra linea no vacia se toma como encabezado solo si
"! su columna 1 no tiene digitos Y su columna 3 no es una condicion valida. CRLF o LF. UTF-8 o Latin-1.
CLASS zcl_arba_ret_sal_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_condicion TYPE c LENGTH 3.
    CONSTANTS: BEGIN OF c_cond,
                 ju  TYPE ty_condicion VALUE 'JU',
                 cm  TYPE ty_condicion VALUE 'CM',
                 ex  TYPE ty_condicion VALUE 'EX',
                 exc TYPE ty_condicion VALUE 'EXC',
               END OF c_cond.

    TYPES: BEGIN OF ty_record,
             nro_linea TYPE i,
             cuit      TYPE c LENGTH 11,
             condicion TYPE ty_condicion,
             es_valido TYPE abap_boolean,
             estado    TYPE c LENGTH 3,
             mensaje   TYPE string,
           END OF ty_record.
    TYPES ty_record_tt TYPE STANDARD TABLE OF ty_record WITH EMPTY KEY.

    "! Decodifica el archivo: UTF-8 y, si no es valido, Latin-1 (nunca falla).
    METHODS decodificar
      IMPORTING iv_archivo     TYPE xstring
      RETURNING VALUE(rv_text) TYPE string.

    METHODS parse_file
      IMPORTING iv_content TYPE string
      EXPORTING et_records TYPE ty_record_tt.

    CLASS-METHODS es_condicion_valida
      IMPORTING iv_cond      TYPE string
      RETURNING VALUE(rv_ok) TYPE abap_boolean.

  PRIVATE SECTION.
    METHODS es_encabezado
      IMPORTING iv_line      TYPE string
      RETURNING VALUE(rv_es) TYPE abap_boolean.

    METHODS parse_line
      IMPORTING iv_line       TYPE string
                iv_nro        TYPE i
      RETURNING VALUE(rs_rec) TYPE ty_record.
ENDCLASS.



CLASS ZCL_ARBA_RET_SAL_PARSER IMPLEMENTATION.


  METHOD decodificar.
    TRY.
        rv_text = cl_abap_conv_codepage=>create_in( codepage = `UTF-8` )->convert( source = iv_archivo ).
      CATCH cx_sy_conversion_codepage cx_parameter_invalid_range.
        rv_text = cl_abap_conv_codepage=>create_in( codepage = `ISO-8859-1` )->convert( source = iv_archivo ).
    ENDTRY.
  ENDMETHOD.


  METHOD es_condicion_valida.
    rv_ok = xsdbool( iv_cond = c_cond-ju OR iv_cond = c_cond-cm OR iv_cond = c_cond-ex OR iv_cond = c_cond-exc ).
  ENDMETHOD.


  METHOD es_encabezado.
    DATA lt_c TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    SPLIT iv_line AT cl_abap_char_utilities=>horizontal_tab INTO TABLE lt_c.
    IF lt_c IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_c3) = COND string( WHEN lines( lt_c ) >= 3 THEN to_upper( condense( lt_c[ 3 ] ) ) ).
    DATA(lv_dig) = replace( val = lt_c[ 1 ] pcre = `[^0-9]` with = `` occ = 0 ).
    rv_es = xsdbool( lv_dig IS INITIAL AND es_condicion_valida( lv_c3 ) = abap_false ).
  ENDMETHOD.


  METHOD parse_file.
    CLEAR et_records.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    SPLIT iv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    DATA(lv_cr) = substring( val = cl_abap_char_utilities=>cr_lf len = 1 ).

    DATA lv_primera TYPE abap_boolean VALUE abap_true.
    LOOP AT lt_lines INTO DATA(lv_raw).
      DATA(lv_nro)  = sy-tabix.
      DATA(lv_line) = replace( val = lv_raw sub = lv_cr with = `` occ = 0 ).
      DATA(lv_trim) = condense( lv_line ).
      IF lv_trim IS INITIAL.
        CONTINUE.
      ENDIF.
      IF lv_primera = abap_true.
        lv_primera = abap_false.
        IF es_encabezado( lv_line ) = abap_true.
          CONTINUE.
        ENDIF.
      ENDIF.
      APPEND parse_line( iv_line = lv_line iv_nro = lv_nro ) TO et_records.
    ENDLOOP.
  ENDMETHOD.


  METHOD parse_line.
    rs_rec-nro_linea = iv_nro.
    rs_rec-es_valido = abap_true.

    DATA lt_comp TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    SPLIT iv_line AT cl_abap_char_utilities=>horizontal_tab INTO TABLE lt_comp.
    IF lines( lt_comp ) < 3.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: linea con menos de 3 campos separados por TAB (informado: { lines( lt_comp ) })|.
      RETURN.
    ENDIF.

    " CUIT: solo digitos (tolera guiones/espacios/BOM); deben quedar exactamente 11.
    DATA(lv_cuit_txt) = condense( lt_comp[ 1 ] ).
    DATA(lv_dig)      = replace( val = lv_cuit_txt pcre = `[^0-9]` with = `` occ = 0 ).
    IF strlen( lv_dig ) <> 11.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: CUIT invalido, debe tener 11 digitos (informado: { lv_cuit_txt })|.
      RETURN.
    ENDIF.
    rs_rec-cuit = lv_dig.

    DATA(lv_cond) = to_upper( condense( lt_comp[ 3 ] ) ).
    IF es_condicion_valida( lv_cond ) = abap_false.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: condicion desconocida, se espera JU, CM, EX o EXC (informado: { lv_cond })|.
      RETURN.
    ENDIF.
    rs_rec-condicion = lv_cond.
  ENDMETHOD.
ENDCLASS.
