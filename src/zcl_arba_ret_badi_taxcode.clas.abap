"! Implementacion de la BAdI ES_FIWTAR_UPDATE_TAXCODE (interface IF_FIWTAR_UPDATE_TAXCODE)
"! para la app estandar "Update Withholding Tax Codes and Open Items" (localizacion AR).
"!
"! Objetivo: que la app aplique el MISMO codigo que el RAP. Por cada proveedor (CUIT), LEE el codigo
"! que el RAP ya determino (log zarba_ret_log, ejecucion mas reciente de la sociedad + tipo) y lo
"! devuelve en withcd_new. NO re-determina por alicuota (eso daba ambiguedad cuando hay varios codigos
"! a la misma alicuota y no ve la columna GRUPO del padron). La app estandar actualiza luego el MAESTRO
"! y AJUSTA LAS PARTIDAS ABIERTAS (EF seccion 6.5) con ese codigo.
"!
"! ====================================================================================
"! ACTIVACION EN ADT (no alcanza con crear la clase; hay que vincularla al enhancement spot):
"!   1) New -> Other ABAP Repository Object -> filtrar "BAdI" -> "BAdI Enhancement Implementation".
"!   2) Enhancement Spot: ES_FIWTAR_UPDATE_TAXCODE ; nombre Z... + transporte.
"!   3) "Add BAdI Implementation" -> elegir la BAdI del spot -> Implementing Class = ZCL_ARBA_RET_BADI_TAXCODE.
"!   4) Activar la enhancement implementation y la clase.
"!
"! NOTA: los nombres de parametros (IT_VDMR_FILE / CT_OUTPUT) y de campos (STCD1/WITHT/FILE_RATE/
"! WT_WITHCD/WITHCD_NEW) son los de la interfaz liberada segun la doc de SAP. Al agregar
"! "INTERFACES if_fiwtar_update_taxcode", ADT genera el stub con la firma REAL de tu release: si
"! algun nombre difiere, ajustar el metodo a ese stub (y avisar para corregir aca).
"! ====================================================================================
CLASS zcl_arba_ret_badi_taxcode DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_fiwtar_update_taxcode.
ENDCLASS.



CLASS ZCL_ARBA_RET_BADI_TAXCODE IMPLEMENTATION.


  METHOD if_fiwtar_update_taxcode~populate_new_tax_code.
    DATA lt_data TYPE if_fiwtar_update_taxcode~tt_vdmr_file.
    lt_data = it_vdmr_file.
    IF lt_data IS INITIAL.
      ct_output = lt_data.
      RETURN.
    ENDIF.

    " FUENTE UNICA DE DETERMINACION = el RAP. La app estandar (esta BAdI) YA NO re-determina el codigo por
    " alicuota: eso fallaba cuando hay MAS DE UN codigo a la misma alicuota (p.ej. ARBA tipo 02: 2 codigos
    " a 1,75% ; 0% -> varios), porque la BAdI ve la alicuota pero NO la columna GRUPO del padron. En su
    " lugar se lee el codigo que el RAP YA determino -que resuelve alicuota + desambiguacion por GRUPO +
    " fuera-de-padron- para la ejecucion MAS RECIENTE de esta sociedad + tipo, y la BAdI solo lo APLICA.
    " Supuesto: el archivo que se sube a la estandar ES el .zip exportado por el RAP (mismos proveedores).
    DATA(lv_witht) = lt_data[ 1 ]-witht.

    TYPES: BEGIN OF ty_map,
             cuit TYPE c LENGTH 11,
             cod  TYPE zcl_arba_ret_determinador=>ty_wht_code,
           END OF ty_map.
    DATA lt_map TYPE HASHED TABLE OF ty_map WITH UNIQUE KEY cuit.

    " 1) Ejecucion REAL mas reciente (finalizada OK / OK_CON_ERRORES) para la sociedad donde este tipo es
    "    el de padron O el de fuera de padron. Tucuman usa DOS tipos en la misma corrida (24 padron + TN
    "    No Inscriptos), asi que la corrida del tipo TN se encuentra por tipo_ret_fuera, no por
    "    tipo_retencion. Se excluyen simulaciones y corridas EN_PROCESO/FALLIDA: una simulacion posterior
    "    a la corrida real NO debe cambiar los codigos que aplica la estandar (ExportarCambios solo
    "    exporta corridas reales, asi que el archivo y esta lectura quedan alineados).
    SELECT ejecucion_uuid, tipo_retencion, provincia FROM zarba_ret_ejec
      WHERE sociedad = @iv_bukrs
        AND ( tipo_retencion = @lv_witht OR tipo_ret_fuera = @lv_witht )
        AND modo_simulacion = @abap_false
        AND estado_ejecucion IN ( 'OK', 'OK_CON_ERRORES' )
      ORDER BY fecha_hora DESCENDING
      INTO @DATA(ls_ejec)
      UP TO 1 ROWS.
    ENDSELECT.

    " 2) Mapa CUIT -> codigo determinado por el RAP, SOLO de las filas del tipo que procesa la app
    "    estandar (tipo_ret = witht). Fallback: filas sin tipo_ret (corridas anteriores) se toman si el
    "    tipo de padron de la ejecucion coincide con witht. Los PCF (alicuota que no resuelve) quedan
    "    SIN codigo -> no entran al mapa -> se les deja el codigo actual (no se tocan).
    IF sy-subrc = 0 AND ls_ejec-ejecucion_uuid IS NOT INITIAL.
      SELECT cuit, indicador_nuevo, tipo_ret, estado, indicador_anterior FROM zarba_ret_log
        WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid
        INTO TABLE @DATA(lt_log).
      LOOP AT lt_log INTO DATA(ls_log).
        IF ls_log-cuit IS INITIAL OR ls_log-indicador_nuevo IS INITIAL.
          CONTINUE.
        ENDIF.
        IF NOT ( ls_log-tipo_ret = lv_witht
              OR ( ls_log-tipo_ret IS INITIAL AND ls_ejec-tipo_retencion = lv_witht ) ).
          CONTINUE.
        ENDIF.
        INSERT VALUE #( cuit = ls_log-cuit cod = ls_log-indicador_nuevo ) INTO TABLE lt_map.
      ENDLOOP.
    ENDIF.

    " 3) Aplicar por CUIT.
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<ls>).
      " Solo Tucuman (Redmine 33748 nota #62): las bajas por ausencia (update_flag 'D') se dejan como las
      " arma la estandar. Ponerles el codigo actual en withcd_new hacia que "Update Database" no borrara el
      " tipo, aunque la vista previa mostrara la baja (30001331 seguia con 24/07). El resto de las
      " provincias queda como estaba (la baja recibe el codigo actual y no se graba): cambiarlo no fue
      " pedido y en Santa Fe / CABA borraria proveedores que hay que conservar (se avisa aparte).
      IF <ls>-update_flag = 'D' AND ls_ejec-provincia = 'TUC'.
        CONTINUE.
      ENDIF.
      DATA lv_cuit TYPE c LENGTH 11.
      lv_cuit = <ls>-stcd1.   " CUIT del archivo (AR = 11 digitos numericos)
      READ TABLE lt_map INTO DATA(ls_map) WITH KEY cuit = lv_cuit.
      IF sy-subrc = 0.
        <ls>-withcd_new = ls_map-cod.
      ELSE.
        " Sin determinacion del RAP para este CUIT -> deja el codigo actual (no lo cambia).
        <ls>-withcd_new = <ls>-wt_withcd.
      ENDIF.
    ENDLOOP.

    " 4) Solo Tucuman (Redmine 33748, notas #32 y #41): con el tipo de fuera de padron (TN) la app
    "    estandar procesa unicamente lo que la corrida determino para ese tipo. Si se la corre con TN
    "    usando otro archivo (por ejemplo el del 24), no propone altas, cambios ni bajas que la corrida
    "    no decidio. Bajas del TN validas: los que ahora vienen en el padron (Caso 7). Se decide por el
    "    Log y no por el tilde "Actualizar Solo Padron", que se puede editar despues de ejecutar.
    IF ls_ejec-ejecucion_uuid IS NOT INITIAL.
      SELECT SINGLE provincia, tipo_retencion, tipo_ret_fuera
        FROM zarba_ret_ejec
        WHERE ejecucion_uuid = @ls_ejec-ejecucion_uuid
        INTO @DATA(ls_tuc).
      IF sy-subrc = 0 AND ls_tuc-provincia = 'TUC'
         AND ls_tuc-tipo_ret_fuera = lv_witht AND ls_tuc-tipo_retencion <> lv_witht.
        DATA lt_tn TYPE if_fiwtar_update_taxcode~tt_vdmr_file.
        " Sin filas del TN en el Log (con "Actualizar Solo Padron" o Modo C la corrida no proceso el
        " fuera de padron) no queda nada para aplicar con este tipo.
        IF lt_map IS NOT INITIAL.
          DATA lt_padron TYPE HASHED TABLE OF ty_map-cuit WITH UNIQUE KEY table_line.
          " Solo filas del padron que quedan con su tipo (ACT, SCB o PCF con indicador actual), mismo criterio
          " que ZCL_ARBA_RET_TUC_PROC->procesar_bajas: no las bajas por API (BAJ, nota #57) ni las rechazadas,
          " cuyo CUIT no habilita la baja del TN (quedarian sin ningun tipo).
          LOOP AT lt_log INTO ls_log WHERE tipo_ret <> lv_witht
                                       AND ( estado = 'ACT' OR estado = 'SCB'
                                             OR ( estado = 'PCF' AND indicador_anterior IS NOT INITIAL ) ).
            INSERT ls_log-cuit INTO TABLE lt_padron.
          ENDLOOP.
          LOOP AT lt_data INTO DATA(ls_fila).
            lv_cuit = ls_fila-stcd1.
            IF ( ls_fila-update_flag = 'D' AND line_exists( lt_padron[ table_line = lv_cuit ] ) )
            OR ( ls_fila-update_flag <> 'D' AND line_exists( lt_map[ cuit = lv_cuit ] ) ).
              APPEND ls_fila TO lt_tn.
            ENDIF.
          ENDLOOP.
        ENDIF.
        lt_data = lt_tn.
      ENDIF.
    ENDIF.

    ct_output = lt_data.
  ENDMETHOD.


  METHOD if_fiwtar_update_taxcode~process_open_item.
    " Sin logica custom: el ajuste de las PARTIDAS ABIERTAS lo hace el flujo estandar de la app
    " "Update Withholding Tax Codes and Open Items". La interface OBLIGA a implementar TODOS sus
    " metodos, por eso se implementa vacio -> se conserva el comportamiento estandar (la BAdI no
    " modifica la partida). Si en el futuro hiciera falta logica por-partida, se agrega aca.
  ENDMETHOD.
ENDCLASS.
