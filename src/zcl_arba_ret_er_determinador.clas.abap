"! Padron Entre Rios: indicador por (tipo de contribuyente, alicuota de retencion) contra ZTFI_RET_TUC
"! (tabla de Ivan, leida via ZI_ARBA_RET_TUC_CLCM). NO duplica logica: delega en
"!   - ZCL_ARBA_RET_TUC_DETERMINADOR->determinar_indicador (CM: alicuota x 0,5 con MA = 'X'; CL: alicuota
"!     tal cual con MA vacio; 0 o >1 coincidencias = PCF) (zcl_arba_ret_tuc_determinador.clas.abap:60-91);
"!   - ZCL_ARBA_RET_DETERMINADOR->obtener_alicuota_indicador (% configurado en SPRO via
"!     I_ExtendedWhldgTaxCode) (zcl_arba_ret_determinador.clas.abap:135-147).
"! El llamador pasa la alicuota "full" del archivo: el x 0,5 lo hace TUC_DETERMINADOR (:67-69).
"! El Rate de la Z para el control Z = SPRO se lee DIRECTO de ZI_ARBA_RET_TUC_CLCM (no con
"! TUC_DETERMINADOR->obtener_alicuota_indicador: desde el 03/11 devuelve primero el % de SPRO,
"! zcl_arba_ret_tuc_determinador.clas.abap:94-111, y el control compararia SPRO contra SPRO).
"! Molde: ZCL_ARBA_RET_SAL_DETERMINADOR (misma API determinar / alicuota / tiene_customizing).
CLASS zcl_arba_ret_er_determinador DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_det_tuc TYPE REF TO zcl_arba_ret_tuc_determinador OPTIONAL
                io_det_gen TYPE REF TO zcl_arba_ret_determinador     OPTIONAL.

    "! ev_alicuota = % del indicador en SPRO (2 decimales, lo que se graba en el log y va al export).
    "! ev_estado = 'PCF' si no hay indicador (o hay mas de uno), si el indicador no existe en SPRO
    "! o si el Rate de ZTFI_RET_TUC no coincide con el % de SPRO.
    METHODS determinar
      IMPORTING iv_tipo_ret     TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_tipo_contrib TYPE c                                     " C / D / P
                iv_alicuota     TYPE zcl_arba_ret_tuc_determinador=>ty_alicuota
      EXPORTING ev_indicador    TYPE zcl_arba_ret_determinador=>ty_wht_code
                ev_alicuota     TYPE zcl_arba_ret_determinador=>ty_alicuota
                ev_estado       TYPE c
                ev_mensaje      TYPE string.

    "! % configurado del indicador en SPRO. No existe -> ev_estado no vacio.
    METHODS alicuota
      IMPORTING iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
                iv_indicador TYPE zcl_arba_ret_determinador=>ty_wht_code
      EXPORTING ev_alicuota  TYPE zcl_arba_ret_determinador=>ty_alicuota
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

    "! El tipo tiene al menos una fila CM (MA = 'X') y una CL (MA vacio) en ZI_ARBA_RET_TUC_CLCM.
    METHODS tiene_customizing
      IMPORTING iv_tipo_ret  TYPE zcl_arba_ret_determinador=>ty_wht_type
      RETURNING VALUE(rv_ok) TYPE abap_boolean.

  PRIVATE SECTION.
    "! Tolerancia Z vs SPRO: SPRO se lee con 2 decimales (zcl_arba_ret_determinador.clas.abap:8) y la Z con 4.
    CONSTANTS c_tolerancia TYPE zcl_arba_ret_tuc_determinador=>ty_alicuota VALUE '0.005'.

    DATA mo_tuc TYPE REF TO zcl_arba_ret_tuc_determinador.
    DATA mo_gen TYPE REF TO zcl_arba_ret_determinador.
ENDCLASS.



CLASS ZCL_ARBA_RET_ER_DETERMINADOR IMPLEMENTATION.


  METHOD constructor.
    mo_tuc = COND #( WHEN io_det_tuc IS BOUND THEN io_det_tuc ELSE NEW zcl_arba_ret_tuc_determinador( ) ).
    mo_gen = COND #( WHEN io_det_gen IS BOUND THEN io_det_gen ELSE NEW zcl_arba_ret_determinador( ) ).
  ENDMETHOD.


  METHOD determinar.
    CLEAR: ev_indicador, ev_alicuota, ev_estado, ev_mensaje.

    " C = Convenio Multilateral; D y P = contribuyente local (decision funcional / EF).
    DATA(lv_cm) = xsdbool( iv_tipo_contrib = zcl_arba_ret_er_parser=>c_tipo-cm ).

    DATA lv_ind TYPE zcl_arba_ret_tuc_determinador=>ty_wht_code.
    DATA lv_est TYPE c LENGTH 3.
    DATA lv_msg TYPE string.
    mo_tuc->determinar_indicador( EXPORTING iv_tipo_ret  = iv_tipo_ret
                                            iv_conv_mult = lv_cm
                                            iv_alicuota  = iv_alicuota      " full: el x0,5 lo hace TUC_DETERMINADOR
                                  IMPORTING ev_indicador = lv_ind
                                            ev_estado    = lv_est
                                            ev_mensaje   = lv_msg ).
    IF lv_est IS NOT INITIAL.
      ev_estado  = 'PCF'.
      ev_mensaje = |{ lv_msg } (archivo: tipo { iv_tipo_contrib }, alicuota { iv_alicuota DECIMALS = 4 })|.
      RETURN.
    ENDIF.

    " El indicador tiene que existir en SPRO (la retencion al pagar se calcula con ese %).
    alicuota( EXPORTING iv_tipo_ret  = iv_tipo_ret
                        iv_indicador = lv_ind
              IMPORTING ev_alicuota  = ev_alicuota
                        ev_estado    = lv_est ).
    IF lv_est IS NOT INITIAL.
      CLEAR ev_alicuota.
      ev_estado  = 'PCF'.
      ev_mensaje = |Pendiente de configuracion: indicador { lv_ind } de ZTFI_RET_TUC no existe en el tipo { iv_tipo_ret }|.
      RETURN.
    ENDIF.

    " Rate de la Z = % de SPRO (si no, el RAP asigna un codigo cuyo % real es otro). Se lee la fila de la Z
    " que matcheo (codigo + rama CM/CL), no obtener_alicuota_indicador de TUC (lee SPRO primero desde el 03/11).
    DATA lv_rate_z TYPE zcl_arba_ret_tuc_determinador=>ty_alicuota.
    DATA(lv_ma) = COND #( WHEN lv_cm = abap_true THEN 'X' ELSE ' ' ).
    SELECT SINGLE withholdingtaxpercent FROM zi_arba_ret_tuc_clcm
      WHERE country            = 'AR'
        AND withholdingtaxtype = @iv_tipo_ret
        AND withholdingtaxcode = @lv_ind
        AND convmult           = @lv_ma
      INTO @lv_rate_z.
    IF abs( lv_rate_z - ev_alicuota ) > c_tolerancia.
      ev_estado  = 'PCF'.
      ev_mensaje = |Pendiente de configuracion: indicador { lv_ind } Rate ZTFI_RET_TUC { lv_rate_z DECIMALS = 4 } | &&
                   |distinto del % SPRO { ev_alicuota DECIMALS = 2 }|.
      CLEAR ev_alicuota.
      RETURN.
    ENDIF.

    ev_indicador = lv_ind.
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
    SELECT SINGLE @abap_true FROM zi_arba_ret_tuc_clcm
      WHERE country = 'AR' AND withholdingtaxtype = @iv_tipo_ret AND convmult = 'X'
      INTO @DATA(lv_cm).
    SELECT SINGLE @abap_true FROM zi_arba_ret_tuc_clcm
      WHERE country = 'AR' AND withholdingtaxtype = @iv_tipo_ret AND convmult = @space
      INTO @DATA(lv_cl).
    rv_ok = xsdbool( lv_cm = abap_true AND lv_cl = abap_true ).
  ENDMETHOD.
ENDCLASS.
