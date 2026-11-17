CLASS zcl_arba_ret_determinador DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_wht_type TYPE c LENGTH 2.
    TYPES ty_wht_code TYPE c LENGTH 2.
    TYPES ty_alicuota TYPE p LENGTH 5 DECIMALS 2.

    "! Determina el indicador de retencion por alicuota (EF seccion 5):
    "! busca en I_ExtendedWhldgTaxCode el indicador cuyo porcentaje configurado
    "! coincide con la alicuota del archivo.
    "!   1 coincidencia  -> ev_estado = ''    (ok)
    "!   0 coincidencias -> ev_estado = 'PCF' (pendiente de configuracion)
    "!  >1 coincidencias -> ev_estado = 'PCF' (ambiguedad de configuracion)
    "!
    "! Nota de volumen (EF seccion 12): los indicadores del tipo se leen UNA sola vez
    "! (cache interna) y el matching por alicuota se resuelve en memoria.
    METHODS determinar_indicador
      IMPORTING iv_pais      TYPE land1 DEFAULT 'AR'
                iv_tipo_ret  TYPE ty_wht_type
                iv_alicuota  TYPE ty_alicuota
      EXPORTING ev_indicador TYPE ty_wht_code
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

    "! Indicador "fuera de padron" (EF seccion 6.3 alt. B): el de la alicuota MAXIMA
    "! configurada dentro del tipo de retencion.
    "!   1 indicador con la alicuota maxima -> ev_estado = ''    (ok)
    "!   0 indicadores / empate en el maximo -> ev_estado = 'PCF'
    METHODS obtener_indicador_maximo
      IMPORTING iv_pais      TYPE land1 DEFAULT 'AR'
                iv_tipo_ret  TYPE ty_wht_type
      EXPORTING ev_indicador TYPE ty_wht_code
                ev_alicuota  TYPE ty_alicuota
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

    "! Alicuota configurada para un indicador dado. Se usa para "fuera de padron" cuando el
    "! indicador viene INFORMADO manualmente (ahi obtener_indicador_maximo no aplica y la alicuota
    "! no se conoce). No encontrado -> ev_estado = 'PCF'.
    METHODS obtener_alicuota_indicador
      IMPORTING iv_pais      TYPE land1 DEFAULT 'AR'
                iv_tipo_ret  TYPE ty_wht_type
                iv_indicador TYPE ty_wht_code
      EXPORTING ev_alicuota  TYPE ty_alicuota
                ev_estado    TYPE c
                ev_mensaje   TYPE string.

protected section.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_code,
             percent TYPE p LENGTH 5 DECIMALS 2,
             code    TYPE ty_wht_code,
           END OF ty_code.
    TYPES ty_code_tt TYPE SORTED TABLE OF ty_code WITH NON-UNIQUE KEY percent.

    DATA mv_cargado TYPE abap_boolean.
    DATA mv_pais    TYPE land1.
    DATA mv_tipo    TYPE ty_wht_type.
    DATA mt_codes   TYPE ty_code_tt.

    "! Carga (una vez por pais+tipo) los indicadores configurados del tipo de retencion.
    METHODS cargar_indicadores
      IMPORTING iv_pais     TYPE land1
                iv_tipo_ret TYPE ty_wht_type.
ENDCLASS.



CLASS ZCL_ARBA_RET_DETERMINADOR IMPLEMENTATION.


  METHOD determinar_indicador.
    CLEAR: ev_indicador, ev_estado, ev_mensaje.

    cargar_indicadores( iv_pais = iv_pais iv_tipo_ret = iv_tipo_ret ).

    DATA lt_hit TYPE STANDARD TABLE OF ty_wht_code WITH EMPTY KEY.
    LOOP AT mt_codes INTO DATA(ls_code) WHERE percent = iv_alicuota.
      APPEND ls_code-code TO lt_hit.
    ENDLOOP.

    CASE lines( lt_hit ).
      WHEN 1.
        ev_indicador = lt_hit[ 1 ].
        ev_estado    = ''.
      WHEN 0.
        ev_estado  = 'PCF'.
        ev_mensaje = |Para la Alícuota { replace( val = |{ iv_alicuota DECIMALS = 2 }| sub = `.` with = `,` ) } | &&
                     |no existe un Indicador de Retención equivalente (tipo { iv_tipo_ret })|.
      WHEN OTHERS.
        ev_estado  = 'PCF'.
        ev_mensaje = |Para la Alícuota { replace( val = |{ iv_alicuota DECIMALS = 2 }| sub = `.` with = `,` ) } | &&
                     |hay { lines( lt_hit ) } Indicadores de Retención equivalentes | &&
                     |({ concat_lines_of( table = lt_hit sep = `, ` ) }; tipo { iv_tipo_ret }): definir cuál corresponde|.
    ENDCASE.
  ENDMETHOD.


  METHOD obtener_indicador_maximo.
    CLEAR: ev_indicador, ev_alicuota, ev_estado, ev_mensaje.

    cargar_indicadores( iv_pais = iv_pais iv_tipo_ret = iv_tipo_ret ).
    IF mt_codes IS INITIAL.
      ev_estado  = 'PCF'.
      ev_mensaje = |No hay indicadores configurados para el tipo { iv_tipo_ret }|.
      RETURN.
    ENDIF.

    " Alicuota maxima configurada
    DATA lv_max TYPE p LENGTH 5 DECIMALS 2.
    LOOP AT mt_codes INTO DATA(ls).
      IF ls-percent > lv_max.
        lv_max = ls-percent.
      ENDIF.
    ENDLOOP.

    " Indicadores que tienen esa alicuota maxima
    DATA lt_hit TYPE STANDARD TABLE OF ty_wht_code WITH EMPTY KEY.
    LOOP AT mt_codes INTO ls WHERE percent = lv_max.
      APPEND ls-code TO lt_hit.
    ENDLOOP.

    IF lines( lt_hit ) = 1.
      ev_indicador = lt_hit[ 1 ].
      ev_alicuota  = lv_max.
    ELSE.
      ev_estado  = 'PCF'.
      ev_mensaje = |Ambiguedad: { lines( lt_hit ) } indicadores con la alicuota maxima { lv_max }|.
    ENDIF.
  ENDMETHOD.


  METHOD obtener_alicuota_indicador.
    CLEAR: ev_alicuota, ev_estado, ev_mensaje.

    cargar_indicadores( iv_pais = iv_pais iv_tipo_ret = iv_tipo_ret ).

    LOOP AT mt_codes INTO DATA(ls) WHERE code = iv_indicador.
      ev_alicuota = ls-percent.
      RETURN.
    ENDLOOP.

    ev_estado  = 'PCF'.
    ev_mensaje = |No existe alicuota configurada para el indicador { iv_indicador } (tipo { iv_tipo_ret })|.
  ENDMETHOD.


  METHOD cargar_indicadores.
    " Recarga solo si cambia el contexto (pais + tipo)
    IF mv_cargado = abap_true AND mv_pais = iv_pais AND mv_tipo = iv_tipo_ret.
      RETURN.
    ENDIF.

    CLEAR mt_codes.
    mv_pais = iv_pais.
    mv_tipo = iv_tipo_ret.

    " NOTA DE INTEGRACION: confirmar nombres de elementos de la vista liberada
    " I_ExtendedWhldgTaxCode en el release del tenant (Country / WithholdingTaxType
    " / WithholdingTaxCode / WithholdingTaxPercent).
    SELECT withholdingtaxcode AS code,
           withholdingtaxpercent AS percent
      FROM i_extendedwhldgtaxcode
      WHERE country            = @iv_pais
        AND withholdingtaxtype = @iv_tipo_ret
      INTO CORRESPONDING FIELDS OF TABLE @mt_codes.

    mv_cargado = abap_true.
  ENDMETHOD.
ENDCLASS.
