"! Parser del padron ATER Entre Rios (RG 280/2024), separado por ';', 12 columnas:
"!  1 fecha publicacion | 2 vigencia desde | 3 vigencia hasta | 4 CUIT | 5 tipo (C/D/P) |
"!  6 marca alta-sujeto (S/N/A/B) | 7 marca alicuota (S/N) | 8 alic. percepcion | 9 alic. RETENCION |
"!  10 grupo percepcion | 11 grupo retencion | 12 razon social.
"! - Encabezado (1ra linea no vacia cuya col 4 no tiene digitos) -> se ignora (no va al log).
"! - Lineas vacias o solo ';' (el archivo de prueba trae 19.407 ';;;;;;;;;;;') -> se cuentan y se ignoran.
"! - Fechas de 7 digitos ("1092026" = 01/09/2026) se completan con 0 a la izquierda; nunca REV por fecha.
"! - Lee linea por linea con offsets (copia de ZCL_ARBA_RET_JOB->siguiente_linea, zcl_arba_ret_job.clas.abap:444-456):
"!   no arma una tabla con las 226.356 lineas del archivo.
"! Molde de API: ZCL_ARBA_RET_SAL_PARSER (el registro trae es_valido/estado/mensaje).
CLASS zcl_arba_ret_er_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! 4 decimales: igual que ZCL_ARBA_RET_TUC_DETERMINADOR=>ty_alicuota (zcl_arba_ret_tuc_determinador.clas.abap:8).
    TYPES ty_alic TYPE zcl_arba_ret_tuc_determinador=>ty_alicuota.

    CONSTANTS: BEGIN OF c_tipo,
                 cm      TYPE c LENGTH 1 VALUE 'C',   " Convenio Multilateral
                 directo TYPE c LENGTH 1 VALUE 'D',   " Contribuyente local
                 prof    TYPE c LENGTH 1 VALUE 'P',   " Profesiones liberales (se trata como CL)
               END OF c_tipo.
    CONSTANTS c_marca_baja TYPE c LENGTH 1 VALUE 'B'.

    TYPES: BEGIN OF ty_record,
             nro_linea  TYPE i,              " linea fisica del archivo (1 = encabezado)
             cuit       TYPE c LENGTH 11,
             tipo       TYPE c LENGTH 1,     " C / D / P
             marca_alta TYPE c LENGTH 1,     " S / N / A / B (se conserva la original)
             marca_alic TYPE c LENGTH 1,     " S / N (solo log)
             alic_ret   TYPE ty_alic,        " col 9, retencion (alicuota "full" del archivo)
             alic_txt   TYPE c LENGTH 10,    " col 9 tal cual (para mensajes)
             grupo_ret  TYPE c LENGTH 2,     " col 11 (solo log)
             fecha_pub  TYPE d,              " col 1
             vig_desde  TYPE d,              " col 2
             vig_hasta  TYPE d,              " col 3
             es_valido  TYPE abap_boolean,
             estado     TYPE c LENGTH 3,     " '' | 'REV'
             mensaje    TYPE string,
           END OF ty_record.
    TYPES ty_record_tt TYPE STANDARD TABLE OF ty_record WITH EMPTY KEY.

    METHODS parse_file
      IMPORTING iv_archivo       TYPE xstring
      EXPORTING et_records       TYPE ty_record_tt
                ev_lineas_vacias TYPE i
                ev_encabezado    TYPE abap_boolean.

  PRIVATE SECTION.
    "! Rango valido de alicuota (mismo criterio que ZCL_ARBA_RET_VALIDATOR, zcl_arba_ret_validator.clas.abap:17).
    CONSTANTS c_alic_max TYPE ty_alic VALUE '15'.

    METHODS decodificar
      IMPORTING iv_archivo     TYPE xstring
      RETURNING VALUE(rv_text) TYPE string.

    METHODS siguiente_linea
      IMPORTING iv_text        TYPE string
      CHANGING  cv_off         TYPE i
      RETURNING VALUE(rv_line) TYPE string.

    METHODS es_vacia
      IMPORTING iv_line      TYPE string
      RETURNING VALUE(rv_es) TYPE abap_boolean.

    METHODS es_encabezado
      IMPORTING iv_line      TYPE string
      RETURNING VALUE(rv_es) TYPE abap_boolean.

    METHODS parse_line
      IMPORTING iv_line       TYPE string
                iv_nro        TYPE i
      RETURNING VALUE(rs_rec) TYPE ty_record.

    METHODS conv_fecha
      IMPORTING iv_txt         TYPE string
      RETURNING VALUE(rv_date) TYPE d.
ENDCLASS.



CLASS ZCL_ARBA_RET_ER_PARSER IMPLEMENTATION.


  METHOD parse_file.
    CLEAR: et_records, ev_lineas_vacias, ev_encabezado.

    DATA(lv_text) = decodificar( iv_archivo ).
    DATA(lv_len)  = strlen( lv_text ).
    DATA lv_off      TYPE i.
    DATA lv_nro      TYPE i.
    DATA lv_primera  TYPE abap_boolean VALUE abap_true.

    WHILE lv_off < lv_len.
      DATA(lv_line) = siguiente_linea( EXPORTING iv_text = lv_text CHANGING cv_off = lv_off ).
      lv_nro += 1.

      IF es_vacia( lv_line ) = abap_true.
        ev_lineas_vacias += 1.
        CONTINUE.
      ENDIF.

      IF lv_primera = abap_true.
        lv_primera = abap_false.
        IF es_encabezado( lv_line ) = abap_true.
          ev_encabezado = abap_true.
          CONTINUE.
        ENDIF.
      ENDIF.

      APPEND parse_line( iv_line = lv_line iv_nro = lv_nro ) TO et_records.
    ENDWHILE.
  ENDMETHOD.


  METHOD decodificar.
    " Copia de zcl_arba_ret_sal_parser.clas.abap:56-62. ATER es Latin-1: UTF-8 falla y cae a ISO-8859-1.
    TRY.
        rv_text = cl_abap_conv_codepage=>create_in( codepage = `UTF-8` )->convert( source = iv_archivo ).
      CATCH cx_sy_conversion_codepage cx_parameter_invalid_range.
        rv_text = cl_abap_conv_codepage=>create_in( codepage = `ISO-8859-1` )->convert( source = iv_archivo ).
    ENDTRY.
  ENDMETHOD.


  METHOD siguiente_linea.
    " Copia de zcl_arba_ret_job.clas.abap:444-456.
    DATA(lv_len) = strlen( iv_text ).
    DATA(lv_pos) = find( val = iv_text sub = cl_abap_char_utilities=>newline off = cv_off ).
    IF lv_pos < 0.
      rv_line = substring( val = iv_text off = cv_off len = lv_len - cv_off ).
      cv_off  = lv_len.
    ELSE.
      rv_line = substring( val = iv_text off = cv_off len = lv_pos - cv_off ).
      cv_off  = lv_pos + 1.
    ENDIF.
    rv_line = replace( val = rv_line regex = `\r` with = `` occ = 0 ).
  ENDMETHOD.


METHOD es_vacia.
  " Vacia = solo ';', espacios, TAB o CR.
  DATA(lv_restante) = replace(
    val  = iv_line
    pcre = `[;\s]`
    with = ``
    occ  = 0 ).

  rv_es = xsdbool( lv_restante IS INITIAL ).
ENDMETHOD.


  METHOD es_encabezado.
  " Encabezado ATER: la columna 4 no contiene digitos.
  DATA lt_c TYPE STANDARD TABLE OF string WITH EMPTY KEY.

  SPLIT iv_line AT ';' INTO TABLE lt_c.

  DATA(lv_c4) = COND string(
    WHEN lines( lt_c ) >= 4
    THEN lt_c[ 4 ]
    ELSE iv_line ).

  DATA(lv_digitos) = replace(
    val  = lv_c4
    pcre = `[^0-9]`
    with = ``
    occ  = 0 ).

  rv_es = xsdbool( lv_digitos IS INITIAL ).
ENDMETHOD.


  METHOD parse_line.
    rs_rec-nro_linea = iv_nro.
    rs_rec-es_valido = abap_true.

    DATA lt_comp TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    SPLIT iv_line AT ';' INTO TABLE lt_comp.
    " Si la col 4 trae un CUIT de 11 digitos se guarda ANTES de cualquier rechazo: una linea cortada o
    " mal formada de un CUIT real cuenta como "en padron" (ER_PROC no le asigna el 03 ni un alta caso 4)
    " y, como queda REV y no se exporta, la app estandar lo conserva via keepers.
    IF lines( lt_comp ) >= 4.
      DATA(lv_cuit_pre) = replace( val = condense( lt_comp[ 4 ] ) pcre = `[^0-9]` with = `` occ = 0 ).
      IF strlen( lv_cuit_pre ) = 11.
        rs_rec-cuit = lv_cuit_pre.
      ENDIF.
    ENDIF.

    " 12 columnas; se toleran 11 (sin razon social). SPLIT no genera el componente vacio final.
    IF lines( lt_comp ) < 11.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: cantidad incorrecta de campos separados por ';' (informado: { lines( lt_comp ) })|.
      RETURN.
    ENDIF.

    " Col 4: CUIT, solo digitos, exactamente 11 (zcl_arba_ret_sal_parser.clas.abap:120-129).
    DATA(lv_cuit_txt) = condense( lt_comp[ 4 ] ).
    DATA(lv_dig)      = replace( val = lv_cuit_txt pcre = `[^0-9]` with = `` occ = 0 ).
    IF strlen( lv_dig ) <> 11.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: CUIT invalido, debe tener 11 digitos (informado: { lv_cuit_txt })|.
      RETURN.
    ENDIF.
    rs_rec-cuit = lv_dig.

    " Col 5: tipo de contribuyente C / D / P.
    DATA(lv_tipo) = to_upper( condense( lt_comp[ 5 ] ) ).
    IF lv_tipo <> c_tipo-cm AND lv_tipo <> c_tipo-directo AND lv_tipo <> c_tipo-prof.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: tipo de contribuyente desconocido, se espera C, D o P (informado: { lv_tipo })|.
      RETURN.
    ENDIF.
    rs_rec-tipo = lv_tipo.

    " Col 6: marca alta-sujeto. Lista blanca S/N/A/B. NO se convierte A en S (el log muestra la original).
    DATA(lv_marca) = to_upper( condense( lt_comp[ 6 ] ) ).
    IF lv_marca <> 'S' AND lv_marca <> 'N' AND lv_marca <> 'A' AND lv_marca <> c_marca_baja.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: marca alta-sujeto desconocida, se espera S, N, A o B (informado: { lv_marca })|.
      RETURN.
    ENDIF.
    rs_rec-marca_alta = lv_marca.

    " Col 7 y col 11: solo informativos.
    rs_rec-marca_alic = to_upper( condense( lt_comp[ 7 ] ) ).
    rs_rec-grupo_ret  = condense( lt_comp[ 11 ] ).

    " Col 9: alicuota de RETENCION (no la de percepcion, col 8). Coma decimal, hasta 4 decimales, 0..15.
    DATA(lv_alic_txt) = condense( lt_comp[ 9 ] ).
    rs_rec-alic_txt   = lv_alic_txt.
    DATA(lv_alic_pto) = replace( val = lv_alic_txt sub = `,` with = `.` occ = 0 ).
    IF NOT matches( val = lv_alic_pto pcre = `\d{1,3}(\.\d{1,4})?` ).
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: alicuota de retencion invalida (informado: { lv_alic_txt })|.
      RETURN.
    ENDIF.
    rs_rec-alic_ret = CONV ty_alic( lv_alic_pto ).
    IF rs_rec-alic_ret > c_alic_max.
      rs_rec-es_valido = abap_false.
      rs_rec-estado    = 'REV'.
      rs_rec-mensaje   = |Rechazado: alicuota de retencion fuera de rango 0-15 (informado: { lv_alic_txt })|.
      RETURN.
    ENDIF.

    " Cols 1-3: fechas informativas (export). Nunca rechazan.
    rs_rec-fecha_pub = conv_fecha( lt_comp[ 1 ] ).
    rs_rec-vig_desde = conv_fecha( lt_comp[ 2 ] ).
    rs_rec-vig_hasta = conv_fecha( lt_comp[ 3 ] ).
  ENDMETHOD.


  METHOD conv_fecha.
    " DDMMAAAA -> AAAAMMDD. 7 digitos ("1092026") -> se completa con 0 a la izquierda ("01092026").
    CLEAR rv_date.
    DATA(lv_dig) = condense( iv_txt ).
    IF NOT matches( val = lv_dig pcre = `\d{7,8}` ).
      RETURN.
    ENDIF.
    IF strlen( lv_dig ) = 7.
      lv_dig = |0{ lv_dig }|.
    ENDIF.
    DATA(lv_dd)   = substring( val = lv_dig off = 0 len = 2 ).
    DATA(lv_mm)   = substring( val = lv_dig off = 2 len = 2 ).
    DATA(lv_aaaa) = substring( val = lv_dig off = 4 len = 4 ).
    IF lv_mm < `01` OR lv_mm > `12` OR lv_dd < `01` OR lv_dd > `31`.
      RETURN.
    ENDIF.
    rv_date = |{ lv_aaaa }{ lv_mm }{ lv_dd }|.
  ENDMETHOD.
ENDCLASS.
