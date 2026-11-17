"! Salta: constante de provincia y validacion de sus parametros de pantalla.
CLASS zcl_arba_ret_sal_param DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS c_provincia TYPE c LENGTH 4 VALUE 'SAL'.
    "! Sin "Solo Padron" el Indicador Fuera de Padron No Salta es obligatorio y debe ser del tipo; el tipo
    "! debe tener condiciones Salta. El "Salta" (IndicadorFueraPadron) lo valida el control generico.
    CLASS-METHODS error_parametros
      IMPORTING iv_tipo       TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_ind_no_sal TYPE zcl_arba_ret_determinador=>ty_wht_code
                iv_solo       TYPE abap_boolean
      EXPORTING ev_msg        TYPE string
                ev_campo      TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_SAL_PARAM IMPLEMENTATION.


  METHOD error_parametros.
    CLEAR: ev_msg, ev_campo.
    IF NEW zcl_arba_ret_sal_determinador( )->tiene_customizing( iv_tipo ) = abap_false.
      ev_msg = |Sin condiciones Salta para el tipo { iv_tipo }|. ev_campo = 'TIPO'. RETURN.
    ENDIF.
    IF iv_solo = abap_false AND iv_ind_no_sal IS INITIAL.
      ev_msg = 'Ingrese el Indicador Fuera de Padron No Salta'. ev_campo = 'IND2'. RETURN.
    ENDIF.
    IF iv_ind_no_sal IS NOT INITIAL.
      DATA lv_est TYPE c LENGTH 3.
      NEW zcl_arba_ret_determinador( )->obtener_alicuota_indicador(
        EXPORTING iv_tipo_ret = iv_tipo iv_indicador = iv_ind_no_sal
        IMPORTING ev_estado   = lv_est ).
      IF lv_est IS NOT INITIAL.
        ev_msg = |Indicador { iv_ind_no_sal } no es del tipo { iv_tipo }|. ev_campo = 'IND2'.
      ENDIF.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
