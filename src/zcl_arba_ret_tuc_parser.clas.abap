CLASS zcl_arba_ret_tuc_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Modo de archivo Tucuman: 'A' = Acreditan (alicuotas) ; 'C' = Coeficientes.
    TYPES ty_modo TYPE c LENGTH 1.
    CONSTANTS: BEGIN OF c_modo,
                 acreditan    TYPE ty_modo VALUE 'A',
                 coeficientes TYPE ty_modo VALUE 'C',
               END OF c_modo.

    "! Registro parseado de un archivo Tucuman (Acreditan o Coeficientes).
    "! Los archivos son de texto plano por POSICION FIJA, con dos espacios de separacion entre
    "! campos; los campos se extraen por offset (no por split), segun el layout de cada modo.
    TYPES: BEGIN OF ty_record,
             nro_linea      TYPE i,
             modo           TYPE ty_modo,
             cuit           TYPE c LENGTH 11,
             excluido       TYPE abap_boolean,   " marca 'E' (no practicar retencion)
             tipo_contrib   TYPE c LENGTH 2,     " Acreditan: 'CL' / 'CM'
             coeficiente    TYPE c LENGTH 10,    " Coeficientes: texto original ("." decimal)
             porcentaje_txt TYPE c LENGTH 10,    " texto original ("." decimal, o "-----" si excluido)
             vigencia_desde TYPE c LENGTH 8,     " Acreditan (informativo, AAAAMMDD)
             vigencia_hasta TYPE c LENGTH 8,     " Acreditan (informativo, AAAAMMDD)
             vigencia       TYPE c LENGTH 6,     " Coeficientes (informativo, AAAAMM)
             denominacion   TYPE c LENGTH 150,   " informativo (razon social)
             longitud       TYPE i,              " longitud de la linea
             estructura_ok  TYPE abap_boolean,   " la linea alcanza para contener el porcentaje
           END OF ty_record.
    TYPES ty_record_tt TYPE STANDARD TABLE OF ty_record WITH EMPTY KEY.

    "! Fija el modo de archivo a parsear ('A' Acreditan por defecto | 'C' Coeficientes).
    METHODS set_modo
      IMPORTING iv_modo TYPE ty_modo.

    "! Parsea el contenido completo (una linea por registro).
    METHODS parse_file
      IMPORTING iv_content       TYPE string
      EXPORTING et_records       TYPE ty_record_tt
                ev_lineas_vacias TYPE i.

    "! Parsea UNA linea segun el modo fijado (usado tambien en streaming desde el job).
    METHODS parse_line
      IMPORTING iv_line          TYPE string
                iv_nro_linea     TYPE i
      RETURNING VALUE(rs_record) TYPE ty_record.

  PRIVATE SECTION.
    DATA mv_modo TYPE ty_modo VALUE 'A'.

    "! Substring por offset/longitud con recorte defensivo (no dumpea si la linea es mas corta).
    METHODS seg
      IMPORTING iv_line      TYPE string
                iv_off       TYPE i
                iv_len       TYPE i
      RETURNING VALUE(rv)    TYPE string.

    "! Primer token (hasta el primer espacio) de un texto ya condensado. Aisla el porcentaje
    "! de cualquier relleno posterior.
    METHODS primer_token
      IMPORTING iv_txt    TYPE string
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_TUC_PARSER IMPLEMENTATION.


  METHOD set_modo.
    mv_modo = COND #( WHEN iv_modo = c_modo-coeficientes THEN c_modo-coeficientes ELSE c_modo-acreditan ).
  ENDMETHOD.


  METHOD parse_file.
    DATA lt_lines TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    CLEAR: et_records, ev_lineas_vacias.

    " Normaliza saltos de linea (CRLF o LF)
    SPLIT iv_content AT cl_abap_char_utilities=>cr_lf INTO TABLE lt_lines.
    IF lines( lt_lines ) = 1.
      SPLIT iv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    ENDIF.

    LOOP AT lt_lines ASSIGNING FIELD-SYMBOL(<lv_line>).
      DATA(lv_index) = sy-tabix.
      " Quitar CR final suelto SIN tocar el resto (el parseo es por posicion)
      DATA(lv_clean) = replace( val = <lv_line> regex = `\r` with = `` occ = 0 ).
      IF lv_clean IS INITIAL.
        ADD 1 TO ev_lineas_vacias.
        CONTINUE.
      ENDIF.
      APPEND parse_line( iv_line = lv_clean iv_nro_linea = lv_index ) TO et_records.
    ENDLOOP.
  ENDMETHOD.


  METHOD parse_line.
    rs_record-nro_linea = iv_nro_linea.
    rs_record-modo      = mv_modo.
    rs_record-longitud  = strlen( iv_line ).

    " Campos comunes: CUIT (pos 1-11) y EXCLUIDO (pos 14)
    rs_record-cuit = condense( seg( iv_line = iv_line iv_off = 0 iv_len = 11 ) ).
    DATA(lv_exc)   = to_upper( condense( seg( iv_line = iv_line iv_off = 13 iv_len = 1 ) ) ).
    rs_record-excluido = xsdbool( lv_exc = 'E' ).

    IF mv_modo = c_modo-coeficientes.
      " Coeficientes (long ~182): COEFICIENTE(17-22), VIGENCIA(25-30), DENOM(33-182), PORCENTAJE(185+)
      rs_record-coeficiente    = condense( seg( iv_line = iv_line iv_off = 16 iv_len = 6 ) ).
      rs_record-vigencia       = condense( seg( iv_line = iv_line iv_off = 24 iv_len = 6 ) ).
      rs_record-denominacion   = seg( iv_line = iv_line iv_off = 32 iv_len = 150 ).
      rs_record-porcentaje_txt = primer_token( seg( iv_line = iv_line iv_off = 184 iv_len = 20 ) ).
      rs_record-estructura_ok  = xsdbool( rs_record-longitud >= 185 ).
    ELSE.
      " Acreditan (long ~190): TIPO CONTRIB(17-18), VIG.DESDE(21-28), VIG.HASTA(31-38),
      "                        DENOM(41-190), PORCENTAJE(193+)
      rs_record-tipo_contrib   = to_upper( condense( seg( iv_line = iv_line iv_off = 16 iv_len = 2 ) ) ).
      rs_record-vigencia_desde = condense( seg( iv_line = iv_line iv_off = 20 iv_len = 8 ) ).
      rs_record-vigencia_hasta = condense( seg( iv_line = iv_line iv_off = 30 iv_len = 8 ) ).
      rs_record-denominacion   = seg( iv_line = iv_line iv_off = 40 iv_len = 150 ).
      rs_record-porcentaje_txt = primer_token( seg( iv_line = iv_line iv_off = 192 iv_len = 20 ) ).
      rs_record-estructura_ok  = xsdbool( rs_record-longitud >= 193 ).
    ENDIF.
  ENDMETHOD.


  METHOD seg.
    DATA(lv_len) = strlen( iv_line ).
    IF iv_off >= lv_len OR iv_len <= 0.
      rv = ``.
      RETURN.
    ENDIF.
    DATA(lv_take) = iv_len.
    IF iv_off + lv_take > lv_len.
      lv_take = lv_len - iv_off.
    ENDIF.
    rv = substring( val = iv_line off = iv_off len = lv_take ).
  ENDMETHOD.


  METHOD primer_token.
    SPLIT condense( iv_txt ) AT ` ` INTO DATA(lv_first) DATA(lv_rest).
    rv = lv_first.
  ENDMETHOD.
ENDCLASS.
