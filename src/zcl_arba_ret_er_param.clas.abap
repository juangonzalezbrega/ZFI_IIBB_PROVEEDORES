"! Entre Rios (ATER): constante de provincia y validacion de sus parametros de pantalla.
"! Molde: ZCL_ARBA_RET_SAL_PARAM (zcl_arba_ret_sal_param.clas.abap:1-34).
"! El Indicador Fuera de Padron (03) lo valida el control generico de error_parametros
"! (zbp_i_arba_ret_ejecucion.clas.locals_imp.abap:1267-1279); aca solo lo propio de ER.
CLASS zcl_arba_ret_er_param DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    "! Codigo de provincia del combo (char 4: "ERIOS"/"E_RIOS" no entran).
    CONSTANTS c_provincia TYPE c LENGTH 4 VALUE 'ER'.
    "! Region (T005S, pais AR) de Entre Rios: universo del fuera de padron.
    CONSTANTS c_region    TYPE c LENGTH 3 VALUE '05'.

    "! El tipo debe tener en ZTFI_RET_TUC (via ZI_ARBA_RET_TUC_CLCM) al menos una fila CM (MA = 'X')
    "! y al menos una fila CL (MA vacio). Si no, todo el archivo daria PCF.
    CLASS-METHODS error_parametros
      IMPORTING iv_tipo  TYPE zcl_arba_ret_determinador=>ty_wht_type
      EXPORTING ev_msg   TYPE string
                ev_campo TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_ER_PARAM IMPLEMENTATION.


  METHOD error_parametros.
    CLEAR: ev_msg, ev_campo.
    IF NEW zcl_arba_ret_er_determinador( )->tiene_customizing( iv_tipo ) = abap_false.
      ev_msg   = |Tipo { iv_tipo } sin alicuotas CM y CL en ZTFI_RET_TUC|.
      ev_campo = 'TIPO'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
