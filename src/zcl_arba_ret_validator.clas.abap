CLASS zcl_arba_ret_validator DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_alicuota TYPE p LENGTH 5 DECIMALS 2.
    TYPES: BEGIN OF ty_val_result,
             es_valido   TYPE abap_boolean,
             estado      TYPE c LENGTH 3,   " '' = valido ; 'REV' = rechazado
             mensaje     TYPE string,
             advertencia TYPE string,
             alicuota    TYPE ty_alicuota,
           END OF ty_val_result.

    "! Tope de alicuota parametrizable (EF seccion 10, propuesto 15,00).
    CONSTANTS gc_alicuota_max TYPE p LENGTH 5 DECIMALS 2 VALUE '15.00'.

    "! Valida un registro segun EF seccion 10 (solo lo exigido: regimen,
    "! CUIT, alicuota y estructura; fechas y marcas son informativas).
    METHODS validate_record
      IMPORTING is_record        TYPE zcl_arba_ret_parser=>ty_record
      RETURNING VALUE(rs_result) TYPE ty_val_result.

protected section.
  PRIVATE SECTION.
    "! Convierte alicuota "9,99" a decimal. rv_ok = abap_false si el formato es invalido.
    METHODS convertir_alicuota
      IMPORTING iv_txt       TYPE c
      EXPORTING ev_valor     TYPE ty_alicuota
      RETURNING VALUE(rv_ok) TYPE abap_boolean.
ENDCLASS.



CLASS ZCL_ARBA_RET_VALIDATOR IMPLEMENTATION.


  METHOD validate_record.
    rs_result-es_valido = abap_true.

    " Estructura: cantidad de campos (EF seccion 10)
    IF is_record-campos_completos = abap_false.
      rs_result-es_valido = abap_false.
      rs_result-estado    = 'REV'.
      rs_result-mensaje   = |Cantidad incorrecta de campos ({ is_record-cant_campos }); se esperaban | &&
                            COND #( WHEN is_record-provincia = 'CABA' THEN |>= 9 (CABA)| ELSE |10 (ARBA)| ).
      RETURN.
    ENDIF.

    " Advertencia tolerada: falta ";" final con los 10 campos completos
    IF is_record-tiene_sep_final = abap_false.
      rs_result-advertencia = 'Falta separador ";" final (tolerado)'.
    ENDIF.

    " Regimen debe ser "R" (retenciones). Solo aplica a ARBA; CABA y Santa Fe no traen regimen inicial.
    IF is_record-provincia = 'ARBA' AND is_record-regimen <> 'R'.
      rs_result-es_valido = abap_false.
      rs_result-estado    = 'REV'.
      rs_result-mensaje   = |Regimen distinto de "R" (informado: "{ is_record-regimen }")|.
      RETURN.
    ENDIF.

    " CUIT: 11 digitos numericos, tratado como texto
    IF strlen( is_record-cuit ) <> 11 OR NOT matches( val = is_record-cuit regex = `\d{11}` ).
      rs_result-es_valido = abap_false.
      rs_result-estado    = 'REV'.
      rs_result-mensaje   = |CUIT invalido (debe ser numerico de 11 digitos): "{ is_record-cuit }"|.
      RETURN.
    ENDIF.

    " Alicuota: formato 9,99 y rango [0,00 ; tope parametrizable 15,00]
    IF convertir_alicuota( EXPORTING iv_txt   = is_record-alicuota_txt
                           IMPORTING ev_valor = rs_result-alicuota ) = abap_false.
      rs_result-es_valido = abap_false.
      rs_result-estado    = 'REV'.
      rs_result-mensaje   = |Alicuota invalida (formato 9,99): "{ is_record-alicuota_txt }"|.
      RETURN.
    ENDIF.

    IF rs_result-alicuota < 0 OR rs_result-alicuota > gc_alicuota_max.
      rs_result-es_valido = abap_false.
      rs_result-estado    = 'REV'.
      rs_result-mensaje   = |Alicuota fuera de rango [0,00 ; { gc_alicuota_max }]: "{ is_record-alicuota_txt }"|.
      RETURN.
    ENDIF.
  ENDMETHOD.


  METHOD convertir_alicuota.
    CLEAR ev_valor.
    DATA(lv_txt) = condense( CONV string( iv_txt ) ).

    " Formato numerico con coma decimal, decimales OPCIONALES: acepta "X,YY" (ARBA/CABA) y tambien
    " los decimales variables de Santa Fe ("2", "0,6", "1,25"). El rango se valida luego (tope 15,00).
    IF NOT matches( val = lv_txt regex = `\d{1,3}(,\d{1,2})?` ).
      RETURN.
    ENDIF.

    DATA(lv_norm) = replace( val = lv_txt sub = ',' with = '.' ).
    TRY.
        ev_valor = CONV decfloat34( lv_norm ).
        rv_ok = abap_true.
      CATCH cx_sy_conversion_error.
        CLEAR ev_valor.
        rv_ok = abap_false.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
