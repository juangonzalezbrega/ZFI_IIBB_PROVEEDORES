CLASS zcl_arba_ret_tuc_validator DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_alicuota TYPE p LENGTH 7 DECIMALS 4.

    "! Resultado de validar un registro Tucuman. 'REV' = rechazado por validacion.
    "! alicuota  = porcentaje del archivo convertido (rate "full"; el x0,50 de CM lo aplica el determinador).
    "! coeficiente = solo modo Coeficientes.
    TYPES: BEGIN OF ty_val_result,
             es_valido   TYPE abap_boolean,
             estado      TYPE c LENGTH 3,
             mensaje     TYPE string,
             alicuota    TYPE ty_alicuota,
             coeficiente TYPE ty_alicuota,
           END OF ty_val_result.

    "! Tope de alicuota (defensivo).
    CONSTANTS gc_alicuota_max TYPE p LENGTH 7 DECIMALS 4 VALUE '15.0000'.

    "! Valida un registro parseado (Acreditan o Coeficientes).
    METHODS validate_record
      IMPORTING is_record        TYPE zcl_arba_ret_tuc_parser=>ty_record
      RETURNING VALUE(rs_result) TYPE ty_val_result.

  PRIVATE SECTION.
    "! Convierte un decimal con punto ("9.9999") a packed. rv_ok = false si el formato es invalido.
    METHODS to_decimal
      IMPORTING iv_txt       TYPE c
      EXPORTING ev_val       TYPE ty_alicuota
      RETURNING VALUE(rv_ok) TYPE abap_boolean.
ENDCLASS.



CLASS ZCL_ARBA_RET_TUC_VALIDATOR IMPLEMENTATION.


  METHOD validate_record.
    rs_result-es_valido = abap_true.

    " Estructura: la linea tiene que alcanzar para contener el porcentaje (posicion fija)
    IF is_record-estructura_ok = abap_false.
      rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                           mensaje = |Estructura/longitud incorrecta (linea de { is_record-longitud } caracteres)| ).
      RETURN.
    ENDIF.

    " CUIT: 11 digitos numericos
    IF strlen( is_record-cuit ) <> 11 OR NOT matches( val = is_record-cuit regex = `\d{11}` ).
      rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                           mensaje = |CUIT invalido (numerico de 11 digitos): "{ is_record-cuit }"| ).
      RETURN.
    ENDIF.

    IF is_record-modo = zcl_arba_ret_tuc_parser=>c_modo-coeficientes.
      " --- Coeficientes ---
      " Excluido: valido (se destilda "sujeto a retencion"); no requiere coeficiente ni porcentaje.
      IF is_record-excluido = abap_true.
        RETURN.
      ENDIF.

      " Coeficiente: decimal valido en [0 ; 1]
      IF to_decimal( EXPORTING iv_txt = is_record-coeficiente IMPORTING ev_val = rs_result-coeficiente ) = abap_false.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Coeficiente invalido: "{ is_record-coeficiente }"| ).
        RETURN.
      ENDIF.
      IF rs_result-coeficiente < 0 OR rs_result-coeficiente > 1.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Coeficiente fuera de rango [0 ; 1]: "{ is_record-coeficiente }"| ).
        RETURN.
      ENDIF.

      " Porcentaje (alicuota CM del archivo): decimal valido en [0 ; tope]
      IF to_decimal( EXPORTING iv_txt = is_record-porcentaje_txt IMPORTING ev_val = rs_result-alicuota ) = abap_false.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Porcentaje invalido: "{ is_record-porcentaje_txt }"| ).
        RETURN.
      ENDIF.
      IF rs_result-alicuota < 0 OR rs_result-alicuota > gc_alicuota_max.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Porcentaje fuera de rango [0 ; { gc_alicuota_max }]: "{ is_record-porcentaje_txt }"| ).
        RETURN.
      ENDIF.

    ELSE.
      " --- Acreditan ---
      " Tipo de contribuyente: CL o CM (siempre, incluso si esta excluido)
      IF is_record-tipo_contrib <> 'CL' AND is_record-tipo_contrib <> 'CM'.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Tipo de contribuyente invalido (CL/CM): "{ is_record-tipo_contrib }"| ).
        RETURN.
      ENDIF.

      " Excluido: valido; el indicador lo pone el parametro "Ind. Ret. Exento CM", no la alicuota.
      IF is_record-excluido = abap_true.
        RETURN.
      ENDIF.

      " Porcentaje: decimal valido en [0 ; tope]
      IF to_decimal( EXPORTING iv_txt = is_record-porcentaje_txt IMPORTING ev_val = rs_result-alicuota ) = abap_false.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Porcentaje invalido: "{ is_record-porcentaje_txt }"| ).
        RETURN.
      ENDIF.
      IF rs_result-alicuota < 0 OR rs_result-alicuota > gc_alicuota_max.
        rs_result = VALUE #( es_valido = abap_false estado = 'REV'
                             mensaje = |Porcentaje fuera de rango [0 ; { gc_alicuota_max }]: "{ is_record-porcentaje_txt }"| ).
        RETURN.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD to_decimal.
    CLEAR ev_val.
    DATA(lv_txt) = condense( CONV string( iv_txt ) ).

    " Decimal con PUNTO (Tucuman), decimales opcionales: "5", "3.5", "0.175", "1.0000".
    IF lv_txt IS INITIAL OR NOT matches( val = lv_txt regex = `\d{1,3}(\.\d{1,4})?` ).
      RETURN.
    ENDIF.

    TRY.
        ev_val = CONV decfloat34( lv_txt ).
        rv_ok  = abap_true.
      CATCH cx_sy_conversion_error.
        CLEAR ev_val.
        rv_ok = abap_false.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
