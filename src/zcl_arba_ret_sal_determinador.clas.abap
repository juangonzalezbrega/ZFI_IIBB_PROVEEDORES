"! Padron Salta: indicador por CONDICION (customizing ZARBA_RET_SALC, Custom Business Configurations)
"! y alicuota configurada del indicador (via ZCL_ARBA_RET_DETERMINADOR, solo lectura).
CLASS zcl_arba_ret_sal_determinador DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_det_gen TYPE REF TO zcl_arba_ret_determinador OPTIONAL.

    "! ev_estado = 'PCF' si la condicion no tiene indicador o el indicador no existe en el tipo.
    METHODS determinar
      IMPORTING iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_condicion TYPE zcl_arba_ret_sal_parser=>ty_condicion
      EXPORTING ev_indicador TYPE zcl_arba_ret_determinador=>ty_wht_code
                ev_alicuota  TYPE zcl_arba_ret_determinador=>ty_alicuota
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

    "! Alicuota configurada del indicador en el tipo. No existe -> ev_estado no vacio.
    METHODS alicuota
      IMPORTING iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_indicador TYPE zcl_arba_ret_determinador=>ty_wht_code
      EXPORTING ev_alicuota  TYPE zcl_arba_ret_determinador=>ty_alicuota
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

    "! Hay al menos una condicion configurada para el tipo (validacion de parametros).
    METHODS tiene_customizing
      IMPORTING iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
      RETURNING VALUE(rv_ok) TYPE abap_boolean.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_map,
             condicion TYPE zcl_arba_ret_sal_parser=>ty_condicion,
             indicador TYPE zcl_arba_ret_determinador=>ty_wht_code,
           END OF ty_map.
    DATA mt_map     TYPE HASHED TABLE OF ty_map WITH UNIQUE KEY condicion.
    DATA mv_tipo    TYPE zcl_arba_ret_determinador=>ty_wht_type.
    DATA mv_cargado TYPE abap_boolean.
    DATA mo_gen     TYPE REF TO zcl_arba_ret_determinador.

    METHODS cargar
      IMPORTING iv_tipo_ret TYPE zcl_arba_ret_determinador=>ty_wht_type.
ENDCLASS.



CLASS ZCL_ARBA_RET_SAL_DETERMINADOR IMPLEMENTATION.


  METHOD constructor.
    mo_gen = COND #( WHEN io_det_gen IS BOUND THEN io_det_gen ELSE NEW zcl_arba_ret_determinador( ) ).
  ENDMETHOD.


  METHOD cargar.
    IF mv_cargado = abap_true AND mv_tipo = iv_tipo_ret.
      RETURN.
    ENDIF.
    CLEAR mt_map.
    mv_tipo = iv_tipo_ret.
    SELECT condicion, wt_withcd AS indicador
      FROM zarba_ret_salc
      WHERE witht = @iv_tipo_ret
      INTO CORRESPONDING FIELDS OF TABLE @mt_map.
    mv_cargado = abap_true.
  ENDMETHOD.


  METHOD determinar.
    CLEAR: ev_indicador, ev_alicuota, ev_estado, ev_mensaje.
    cargar( iv_tipo_ret ).

    READ TABLE mt_map INTO DATA(ls) WITH TABLE KEY condicion = iv_condicion.
    IF sy-subrc <> 0 OR ls-indicador IS INITIAL.
      ev_estado  = 'PCF'.
      ev_mensaje = |Pendiente de configuracion: condicion { iv_condicion } sin indicador para el tipo { iv_tipo_ret } (Padron Salta - Condiciones)|.
      RETURN.
    ENDIF.

    alicuota( EXPORTING iv_tipo_ret  = iv_tipo_ret
                        iv_indicador = ls-indicador
              IMPORTING ev_alicuota  = ev_alicuota
                        ev_estado    = ev_estado ).
    IF ev_estado IS NOT INITIAL.
      ev_estado  = 'PCF'.
      ev_mensaje = |Pendiente de configuracion: indicador { ls-indicador } de la condicion { iv_condicion } no existe en el tipo { iv_tipo_ret }|.
      RETURN.
    ENDIF.
    ev_indicador = ls-indicador.
  ENDMETHOD.


  METHOD alicuota.
    CLEAR: ev_alicuota, ev_estado, ev_mensaje.
    mo_gen->obtener_alicuota_indicador( EXPORTING iv_tipo_ret  = iv_tipo_ret
                                                  iv_indicador = iv_indicador
                                        IMPORTING ev_alicuota  = ev_alicuota
                                                  ev_estado    = ev_estado
                                                  ev_mensaje   = ev_mensaje ).
  ENDMETHOD.


  METHOD tiene_customizing.
    cargar( iv_tipo_ret ).
    rv_ok = xsdbool( mt_map IS NOT INITIAL ).
  ENDMETHOD.
ENDCLASS.
