CLASS zcl_arba_ret_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Registro del padron ARBA parseado por ";" (EF seccion 4).
    "! Los 10 campos funcionales resultan de dividir la linea por ";".
    TYPES: BEGIN OF ty_record,
             nro_linea          TYPE i,
             provincia          TYPE c LENGTH 4,   " 'ARBA' | 'CABA' (contexto de parseo)
             regimen            TYPE c LENGTH 1,
             fecha_publicacion  TYPE c LENGTH 8,   " DDMMAAAA (solo log)
             vigencia_desde     TYPE c LENGTH 8,   " DDMMAAAA (solo log)
             vigencia_hasta     TYPE c LENGTH 8,   " DDMMAAAA (solo log)
             cuit               TYPE c LENGTH 11,
             tipo_contribuyente TYPE c LENGTH 1,   " C/D (solo log)
             marca_alta_baja    TYPE c LENGTH 1,   " S/B/N (solo log)
             marca_cambio_alic  TYPE c LENGTH 1,   " S/N (solo log)
             alicuota_txt       TYPE c LENGTH 10,  " "9,99" original
             nro_grupo          TYPE c LENGTH 2,   " (solo log)
             cant_campos        TYPE i,
             campos_completos   TYPE abap_boolean, " 10 campos funcionales presentes
             tiene_sep_final    TYPE abap_boolean, " ";" final presente
           END OF ty_record.
    TYPES ty_record_tt TYPE STANDARD TABLE OF ty_record WITH EMPTY KEY.

    "! Parsea el contenido del archivo (una linea por registro).
    "! @parameter iv_content       | contenido de texto del archivo
    "! @parameter et_records       | registros parseados (uno por linea no vacia)
    "! @parameter ev_lineas_vacias | cantidad de lineas vacias omitidas (EF seccion 10)
    METHODS parse_file
      IMPORTING iv_content       TYPE string
      EXPORTING et_records       TYPE ty_record_tt
                ev_lineas_vacias TYPE i.

    "! Parsea UNA linea (usado por el Application Job en streaming, sin cargar el
    "! archivo completo ni construir la tabla de registros).
    METHODS parse_line
      IMPORTING iv_line          TYPE string
                iv_nro_linea     TYPE i
      RETURNING VALUE(rs_record) TYPE ty_record.

    "! Fija la jurisdiccion del padron ('ARBA' por defecto | 'CABA'), que define el layout de
    "! columnas del parseo. Cualquier valor distinto de 'CABA' se trata como 'ARBA'.
    METHODS set_provincia
      IMPORTING iv_provincia TYPE c.

protected section.
  PRIVATE SECTION.
    DATA mv_provincia TYPE c LENGTH 4.
ENDCLASS.



CLASS ZCL_ARBA_RET_PARSER IMPLEMENTATION.


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
      " Toleramos un posible CR final suelto
      DATA(lv_clean) = replace( val = <lv_line> sub = cl_abap_char_utilities=>cr_lf with = `` ).
      IF lv_clean IS INITIAL.
        ADD 1 TO ev_lineas_vacias.
        CONTINUE.
      ENDIF.
      APPEND parse_line( iv_line = lv_clean iv_nro_linea = lv_index ) TO et_records.
    ENDLOOP.
  ENDMETHOD.


  METHOD parse_line.
    DATA lt_comp TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    rs_record-nro_linea = iv_nro_linea.
    DATA(lv_prov) = COND #( WHEN mv_provincia = 'CABA' THEN 'CABA'
                            WHEN mv_provincia = 'SF'   THEN 'SF'
                            ELSE 'ARBA' ).
    rs_record-provincia = lv_prov.

    SPLIT iv_line AT ';' INTO TABLE lt_comp.

    " Separador final (EF seccion 10): se detecta del texto CRUDO (ultimo caracter ";"),
    " NO del numero de componentes. Motivo: SPLIT ... INTO TABLE no es confiable respecto a
    " si incluye o no el segmento vacio final del ";" de cierre; contar componentes hacia que
    " "R;...;05;" quedara en 10 y marcara tiene_sep_final = false por error (test mapea_campos).
    rs_record-tiene_sep_final = xsdbool( iv_line CP '*;' ).

    " Campos FUNCIONALES: si SPLIT incluyo el vacio final del ";", descontarlo.
    DATA(lv_comp) = lines( lt_comp ).
    IF rs_record-tiene_sep_final = abap_true AND lv_comp > 0 AND lt_comp[ lv_comp ] IS INITIAL.
      lv_comp = lv_comp - 1.
    ENDIF.
    rs_record-cant_campos = lv_comp.

    IF lv_prov = 'CABA' OR lv_prov = 'SF'.
      " CABA / Santa Fe: SIN regimen inicial. CUIT col 4; alicuota de RETENCIONES col 9 (col 8 =
      " percepciones, se ignora). Fechas col 1-3. GRUPO RETEN = col 11 (col 10 = GRUPO PER.,
      " percepciones). El GRUPO RETEN va a nro_grupo y se usa para DESAMBIGUAR el codigo cuando hay
      " varios a la misma alicuota (misma logica que ARBA, que lo trae en col 10).
      rs_record-campos_completos = xsdbool( lv_comp >= 9 ).
      IF rs_record-cant_campos >= 9.
        rs_record-fecha_publicacion  = condense( lt_comp[ 1 ] ).
        rs_record-vigencia_desde     = condense( lt_comp[ 2 ] ).
        rs_record-vigencia_hasta     = condense( lt_comp[ 3 ] ).
        rs_record-cuit               = condense( lt_comp[ 4 ] ).
        rs_record-tipo_contribuyente = to_upper( condense( lt_comp[ 5 ] ) ).
        rs_record-marca_alta_baja    = to_upper( condense( lt_comp[ 6 ] ) ).
        rs_record-marca_cambio_alic  = to_upper( condense( lt_comp[ 7 ] ) ).
        rs_record-alicuota_txt       = condense( lt_comp[ 9 ] ).
        IF rs_record-cant_campos >= 11.
          rs_record-nro_grupo        = condense( lt_comp[ 11 ] ).
        ENDIF.
      ENDIF.
    ELSE.
      " ARBA (formato actual): regimen col 1, CUIT col 5, alicuota col 9, nro_grupo col 10.
      rs_record-campos_completos = xsdbool( lv_comp = 10 ).
      IF rs_record-cant_campos >= 10.
        rs_record-regimen            = to_upper( condense( lt_comp[ 1 ] ) ).
        rs_record-fecha_publicacion  = condense( lt_comp[ 2 ] ).
        rs_record-vigencia_desde     = condense( lt_comp[ 3 ] ).
        rs_record-vigencia_hasta     = condense( lt_comp[ 4 ] ).
        rs_record-cuit               = condense( lt_comp[ 5 ] ).
        rs_record-tipo_contribuyente = to_upper( condense( lt_comp[ 6 ] ) ).
        rs_record-marca_alta_baja    = to_upper( condense( lt_comp[ 7 ] ) ).
        rs_record-marca_cambio_alic  = to_upper( condense( lt_comp[ 8 ] ) ).
        rs_record-alicuota_txt       = condense( lt_comp[ 9 ] ).
        rs_record-nro_grupo          = condense( lt_comp[ 10 ] ).
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD set_provincia.
    mv_provincia = COND #( WHEN iv_provincia = 'CABA' THEN 'CABA'
                           WHEN iv_provincia = 'SF'   THEN 'SF'
                           ELSE 'ARBA' ).
  ENDMETHOD.
ENDCLASS.
