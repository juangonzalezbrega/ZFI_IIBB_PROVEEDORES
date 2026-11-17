CLASS zcl_arba_ret_tuc_determinador DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_wht_type TYPE c LENGTH 2.
    TYPES ty_wht_code TYPE c LENGTH 2.
    TYPES ty_alicuota TYPE p LENGTH 7 DECIMALS 4.

    "! Determina el codigo de retencion del padron Tucuman por CL/CM + alicuota, contra la vista
    "! ZI_ARBA_RET_TUC_CLCM (que ya distingue CL/CM). Para CM aplica el x0,50 sobre la alicuota del
    "! archivo (los codigos CM estan configurados a la alicuota reducida).
    "!   1 coincidencia  -> ev_estado = ''    (ok)
    "!   0 coincidencias -> ev_estado = 'PCF' (no hay codigo para esa alicuota/rama)
    "!  >1 coincidencias -> ev_estado = 'PCF' (ambiguedad)
    METHODS determinar_indicador
      IMPORTING iv_pais      TYPE land1     DEFAULT 'AR'
                iv_tipo_ret  TYPE ty_wht_type
                iv_conv_mult TYPE abap_boolean   " CM = true ; CL = false
                iv_alicuota  TYPE ty_alicuota     " porcentaje "full" del archivo
      EXPORTING ev_indicador TYPE ty_wht_code
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

    "! Alicuota configurada para un tipo + codigo: primero I_ExtendedWhldgTaxCode (T059Z, contra la que
    "! compara la app estandar) y, si no esta o es 0, ZI_ARBA_RET_TUC_CLCM. 0 si no existe en ninguna.
    "! Se usa para el Log y el .txt del export del fuera de padron (TN). En Tucuman, TN codigo 01 = 7 %.
    METHODS obtener_alicuota_indicador
      IMPORTING iv_pais        TYPE land1 DEFAULT 'AR'
                iv_tipo_ret    TYPE ty_wht_type
                iv_indicador   TYPE ty_wht_code
      RETURNING VALUE(rv_alic) TYPE ty_alicuota.

  PRIVATE SECTION.
    "! CM del contribuyente -> divide la alicuota del archivo (el codigo CM esta a la alicuota reducida).
    CONSTANTS c_medio TYPE ty_alicuota VALUE '0.5'.

    TYPES: BEGIN OF ty_code,
             conv_mult TYPE c LENGTH 1,
             percent   TYPE ty_alicuota,
             code      TYPE ty_wht_code,
           END OF ty_code.
    TYPES ty_code_tt TYPE STANDARD TABLE OF ty_code WITH EMPTY KEY.

    DATA mv_cargado TYPE abap_boolean.
    DATA mv_pais    TYPE land1.
    DATA mv_tipo    TYPE ty_wht_type.
    DATA mt_codes   TYPE ty_code_tt.

    METHODS cargar
      IMPORTING iv_pais     TYPE land1
                iv_tipo_ret TYPE ty_wht_type.
ENDCLASS.



CLASS ZCL_ARBA_RET_TUC_DETERMINADOR IMPLEMENTATION.


  METHOD determinar_indicador.
    CLEAR: ev_indicador, ev_estado, ev_mensaje.

    cargar( iv_pais = iv_pais iv_tipo_ret = iv_tipo_ret ).

    " Alicuota de busqueda: CL directa ; CM a la mitad (los codigos CM estan a la alicuota reducida).
    DATA(lv_look) = iv_alicuota.
    IF iv_conv_mult = abap_true.
      lv_look = iv_alicuota * c_medio.
    ENDIF.
    DATA(lv_cm) = COND #( WHEN iv_conv_mult = abap_true THEN 'X' ELSE ' ' ).

    DATA lt_hit TYPE STANDARD TABLE OF ty_wht_code WITH EMPTY KEY.
    LOOP AT mt_codes INTO DATA(ls) WHERE conv_mult = lv_cm AND percent = lv_look.
      APPEND ls-code TO lt_hit.
    ENDLOOP.

    DATA(lv_rama) = COND string( WHEN iv_conv_mult = abap_true THEN 'CM' ELSE 'CL' ).
    CASE lines( lt_hit ).
      WHEN 1.
        ev_indicador = lt_hit[ 1 ].
        ev_estado    = ''.
      WHEN 0.
        ev_estado  = 'PCF'.
        ev_mensaje = |Pendiente de configuracion: no existe indicador { lv_rama } con alicuota | &&
                     |{ lv_look } para el tipo { iv_tipo_ret }|.
      WHEN OTHERS.
        ev_estado  = 'PCF'.
        ev_mensaje = |Pendiente de configuracion: { lines( lt_hit ) } indicadores { lv_rama } con | &&
                     |alicuota { lv_look } (ambiguedad)|.
    ENDCASE.
  ENDMETHOD.


  METHOD obtener_alicuota_indicador.
    " Primero T059Z: no depende de que el TN este cargado en ZTFI_RET_TUC (Redmine 33748, nota #46).
    SELECT SINGLE withholdingtaxpercent FROM i_extendedwhldgtaxcode
      WHERE country            = @iv_pais
        AND withholdingtaxtype = @iv_tipo_ret
        AND withholdingtaxcode = @iv_indicador
      INTO @rv_alic.
    IF sy-subrc = 0 AND rv_alic > 0.
      RETURN.
    ENDIF.

    CLEAR rv_alic.
    cargar( iv_pais = iv_pais iv_tipo_ret = iv_tipo_ret ).
    READ TABLE mt_codes INTO DATA(ls) WITH KEY code = iv_indicador.
    IF sy-subrc = 0.
      rv_alic = ls-percent.
    ENDIF.
  ENDMETHOD.


  METHOD cargar.
    IF mv_cargado = abap_true AND mv_pais = iv_pais AND mv_tipo = iv_tipo_ret.
      RETURN.
    ENDIF.

    CLEAR mt_codes.
    mv_pais = iv_pais.
    mv_tipo = iv_tipo_ret.

    SELECT withholdingtaxcode    AS code,
           withholdingtaxpercent AS percent,
           convmult              AS conv_mult
      FROM zi_arba_ret_tuc_clcm
      WHERE country            = @iv_pais
        AND withholdingtaxtype = @iv_tipo_ret
      INTO CORRESPONDING FIELDS OF TABLE @mt_codes.

    mv_cargado = abap_true.
  ENDMETHOD.
ENDCLASS.
