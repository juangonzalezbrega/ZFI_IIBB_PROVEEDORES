"! Export Salta: keepers del snapshot. La app estandar borra por ausencia (tambien en otras sociedades,
"! verificado en KMZ 08/10). Salta nunca quita el tipo, asi que todo titular del tipo, de cualquier sociedad,
"! cuyo CUIT no este ya en el archivo va sin cambio (alicuota de su codigo actual). La BAdI, al no hallar
"! el CUIT en la corrida, le deja el codigo actual.
CLASS zcl_arba_ret_sal_export DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS keepers
      IMPORTING iv_sociedad TYPE bukrs
                iv_tipo     TYPE zcl_arba_ret_determinador=>ty_wht_type
                it_rows     TYPE zcl_arba_ret_exporter=>ty_rows
      EXPORTING et_rows     TYPE zcl_arba_ret_exporter=>ty_rows
                ev_sin_cuit TYPE i.
ENDCLASS.



CLASS ZCL_ARBA_RET_SAL_EXPORT IMPLEMENTATION.


  METHOD keepers.
    CLEAR: et_rows, ev_sin_cuit.

    DATA lt_vistos TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_cuit WITH UNIQUE KEY table_line.
    LOOP AT it_rows INTO DATA(ls_in).
      INSERT ls_in-cuit INTO TABLE lt_vistos.
    ENDLOOP.

    DATA(lo_bp)  = NEW zcl_arba_ret_bp_updater( ).
    DATA(lo_det) = NEW zcl_arba_ret_determinador( ).
    lo_bp->preparar( iv_sociedad = iv_sociedad iv_tipo_ret = iv_tipo ).   " mapa CUIT -> proveedor

    SELECT DISTINCT companycode FROM i_supplierwithholdingtax
      WHERE withholdingtaxtype = @iv_tipo
      INTO TABLE @DATA(lt_soc).

    TYPES: BEGIN OF ty_alic_c,
             cod  TYPE zcl_arba_ret_determinador=>ty_wht_code,
             alic TYPE zcl_arba_ret_exporter=>ty_alicuota,
           END OF ty_alic_c.
    DATA lt_alic TYPE HASHED TABLE OF ty_alic_c WITH UNIQUE KEY cod.

    LOOP AT lt_soc INTO DATA(ls_soc).
      LOOP AT lo_bp->leer_titulares_tipo( iv_sociedad = ls_soc-companycode iv_tipo = iv_tipo ) INTO DATA(ls_h).
        IF ls_h-cuit IS INITIAL.
          ev_sin_cuit = ev_sin_cuit + 1.
          CONTINUE.
        ENDIF.
        IF line_exists( lt_vistos[ table_line = ls_h-cuit ] ).
          CONTINUE.
        ENDIF.
        INSERT ls_h-cuit INTO TABLE lt_vistos.

        READ TABLE lt_alic INTO DATA(ls_alic) WITH TABLE KEY cod = ls_h-indicador.
        IF sy-subrc <> 0.
          DATA lv_alic TYPE zcl_arba_ret_exporter=>ty_alicuota.
          DATA lv_est  TYPE c LENGTH 3.
          DATA lv_msg  TYPE string.
          CLEAR: lv_alic, lv_est, lv_msg.
          lo_det->obtener_alicuota_indicador( EXPORTING iv_tipo_ret  = iv_tipo
                                                        iv_indicador = ls_h-indicador
                                              IMPORTING ev_alicuota  = lv_alic
                                                        ev_estado    = lv_est
                                                        ev_mensaje   = lv_msg ).
          ls_alic = VALUE #( cod = ls_h-indicador alic = lv_alic ).
          INSERT ls_alic INTO TABLE lt_alic.
        ENDIF.
        APPEND VALUE #( cuit = ls_h-cuit alicuota = ls_alic-alic ) TO et_rows.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
