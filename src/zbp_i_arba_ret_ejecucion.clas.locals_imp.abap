CLASS lhc_ejecucion DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PUBLIC SECTION.
    "! Intencion de agendado guardada en la fase de interaccion; el saver la consume
    "! en la fase de save (unica fase donde cl_apj_rt_api=>schedule_job es legal).
    TYPES: BEGIN OF ty_pending,
             uuid    TYPE sysuuid_x16,
             id_ejec TYPE c LENGTH 32,
             simular TYPE abap_boolean,
           END OF ty_pending.
    CLASS-DATA gt_pending TYPE STANDARD TABLE OF ty_pending WITH EMPTY KEY.

  PRIVATE SECTION.
    "! Lista de CUIT (11 digitos) para membership en el armado del snapshot de export.
    TYPES ty_cuit_tt TYPE STANDARD TABLE OF zcl_arba_ret_bp_updater=>ty_cuit WITH EMPTY KEY.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Ejecucion
      RESULT result.

    METHODS setdefaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~setDefaults.

    METHODS setindicadorfuera FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~setIndicadorFuera.

    METHODS validarparametros FOR VALIDATE ON SAVE
      IMPORTING keys FOR Ejecucion~validarParametros.

    "! Reglas de parametros: Provincia / Sociedad / Tipo obligatorios; fuera de Tucuman, Indicador Fuera de
    "! Padron obligatorio sin "Solo Padron" y, si se informa, del Tipo de Retencion. Devuelve el primer error
    "! (texto corto: new_message_with_text recorta) y el campo (PROV/SOC/TIPO/IND); vacio = OK.
    METHODS error_parametros
      IMPORTING iv_provincia TYPE zi_arba_ret_ejecucion-Provincia
                iv_sociedad  TYPE zi_arba_ret_ejecucion-Sociedad
                iv_tipo      TYPE zi_arba_ret_ejecucion-TipoRetencion
                iv_indicador TYPE zi_arba_ret_ejecucion-IndicadorFueraPadron
                iv_solo      TYPE zi_arba_ret_ejecucion-ActualizarSoloPadron
                iv_ind_no_sal TYPE zi_arba_ret_ejecucion-IndicadorFueraPadronNoSal OPTIONAL
      EXPORTING ev_msg       TYPE string
                ev_campo     TYPE string.

    "! Motivo por el que Simular/Ejecutar NO puede lanzar el proceso (vacio = se puede): ya procesada en
    "! real, proceso en curso (EN_PROCESO reciente: evita dos jobs sobre la misma ejecucion, que pisaban el
    "! estado -> FALLIDA y luego OK), parametros incompletos o sin archivo.
    METHODS motivo_no_lanzable
      IMPORTING iv_uuid       TYPE sysuuid_x16
      RETURNING VALUE(rv_msg) TYPE string.

    METHODS sethidetuc FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~setHideTuc.

    " Salta: HideSal + limpieza del Indicador Fuera de Padron No Salta (ver ZCL_ARBA_RET_SAL_PARAM).
    METHODS sethidesal FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~setHideSal.

    "! Tucuman: grisa los parametros que no aplican al Modo (C: los de Acreditan; A: "Indicador CM Coef. 0").
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Ejecucion RESULT result.

    "! Mantiene TipoIndFuera: tipo por el que filtra el matchcode de "Indicador Fuera de Padron"
    "! (Tucuman: Tipo Ret. Fuera de Padron; resto: Tipo de Retencion).
    METHODS settipoindfuera FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~setTipoIndFuera.

    "! Tucuman: al cambiar el Modo limpia los parametros que quedan grisados (Redmine 33748, 07/10).
    "!   Modo C: Indicador / Tipo Ret. Fuera de Padron e Ind. Ret. Exento CM. Modo A: Indicador CM Coef. 0.
    METHODS limpiarpormodo FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~limpiarPorModo.

    "! Tucuman: al cambiar el Tipo Ret. Fuera de Padron limpia el Indicador Fuera de Padron si no es de ese tipo.
    METHODS limpiarindfuera FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Ejecucion~limpiarIndFuera.

    "! Tucuman: Tipo de Retencion del padron de Tucuman; con Modo A sin Solo Padron, Tipo e Indicador Fuera de
    "! Padron obligatorios y el indicador del tipo fuera de padron (Redmine 33748, 02/09).
    METHODS validarparametrostuc FOR VALIDATE ON SAVE
      IMPORTING keys FOR Ejecucion~validarParametrosTuc.

    METHODS simular FOR MODIFY
      IMPORTING keys FOR ACTION Ejecucion~Simular RESULT result.

    METHODS ejecutar FOR MODIFY
      IMPORTING keys FOR ACTION Ejecucion~Ejecutar RESULT result.

    METHODS exportarcambios FOR MODIFY
      IMPORTING keys FOR ACTION Ejecucion~ExportarCambios RESULT result.

    "! Tucuman: aplica por API los casos que la estandar no hace (destilde de sujeto y exencion).
    "! Se ejecuta despues de "Actualizar Codigos y Partidas".
    METHODS aplicarexenciones FOR MODIFY
      IMPORTING keys FOR ACTION Ejecucion~AplicarExenciones RESULT result.

    "! Registra la intencion de agendado y marca EN_PROCESO. NO agenda aca:
    "! schedule_job es commit-relevant y solo es legal en la fase de save (saver).
    METHODS lanzar_job
      IMPORTING iv_uuid    TYPE sysuuid_x16
                iv_simular TYPE abap_boolean.

    "! "Keepers" del snapshot (fix borrado-por-ausencia): titulares ACTUALES del tipo que NO estan en el
    "! archivo se agregan al export SIN CAMBIO para que la app estandar no los borre. Solo para "Solo
    "! Padron" (actualizacion parcial) y provincias del flujo generico (no Tucuman, que tiene su propio
    "! mecanismo TN). Excluye los que ya estan en el export y los REG (Santa Fe: baja a proposito). Un
    "! titular sin CUIT AR1A no se puede proteger -> se cuenta en ev_sin_cuit para advertir. NO toca el log.
    METHODS keepers_para_export
      IMPORTING iv_sociedad    TYPE bukrs
                iv_tipo        TYPE zcl_arba_ret_determinador=>ty_wht_type
                it_export_cuit TYPE ty_cuit_tt
                it_reg_cuit    TYPE ty_cuit_tt
      EXPORTING et_rows        TYPE zcl_arba_ret_exporter=>ty_rows
                ev_conservados TYPE i
                ev_sin_cuit    TYPE i.

    "! Tucuman: titulares ACTUALES del tipo en TODAS las sociedades que no vienen en el export. La app
    "! estandar, corrida para una sociedad, propone borrar tambien a titulares del tipo de otras sociedades.
    "! Con it_cuit_tipo (CUIT del export de este tipo), en otras sociedades solo deja de conservar a los que
    "! ya van en este archivo. Con iv_bajas_padron (tipo de padron sin "Solo Padron"; Redmine 33748 nota
    "! #57), en la sociedad de la corrida no conserva a los que no vienen en el archivo (it_cuit_archivo):
    "! la estandar les da de baja el tipo. Se exceptuan los proveedores de it_proteger (alta del tipo de
    "! fuera de padron fallida u omitida: no quedan sin ningun tipo). ev_bajas cuenta esas bajas.
    METHODS keepers_tuc
      IMPORTING iv_sociedad     TYPE bukrs
                iv_tipo         TYPE zarba_ret_log-tipo_ret
                it_export_cuit  TYPE ty_cuit_tt
                it_cuit_tipo    TYPE ty_cuit_tt OPTIONAL
                iv_bajas_padron TYPE abap_boolean DEFAULT abap_false
                it_cuit_archivo TYPE ty_cuit_tt OPTIONAL
                it_proteger     TYPE zcl_arba_ret_alta=>ty_sup_tt OPTIONAL
                iv_prov_desde   TYPE zcl_arba_ret_bp_updater=>ty_supplier OPTIONAL
                iv_prov_hasta   TYPE zcl_arba_ret_bp_updater=>ty_supplier OPTIONAL
      EXPORTING et_rows         TYPE zcl_arba_ret_exporter=>ty_rows
                ev_conservados  TYPE i
                ev_sin_cuit     TYPE i
                ev_bajas        TYPE i.

    "! Provincias cuyo export se BLOQUEA cuando el padron no dejo ninguna fila exportable (el archivo
    "! saldria solo con keepers, sin cambios, y la estandar no mostraria nada). Hoy solo Tucuman: en el
    "! resto, sin filas puede haber bajas (REG de Santa Fe, modo completo) y lo decide el control de cambios.
    METHODS export_requiere_padron
      IMPORTING iv_prov       TYPE zarba_ret_ejec-provincia
      RETURNING VALUE(rv_req) TYPE abap_boolean.

    "! Fila del log que la app estandar aplica como cambio de codigo: 'ACT' con indicador nuevo distinto del
    "! anterior, salvo las altas (caso 1 y 4), que las crea Ejecutar por API y la estandar no las lista. Un
    "! 'ACT' con el mismo codigo (p.ej. Excluido de Coeficientes, caso X) no lo aplica la estandar.
    METHODS es_cambio_std
      IMPORTING iv_estado     TYPE zarba_ret_log-estado
                iv_caso       TYPE zarba_ret_log-caso
                iv_ind_ant    TYPE zarba_ret_log-indicador_anterior
                iv_ind_nue    TYPE zarba_ret_log-indicador_nuevo
      RETURNING VALUE(rv_cam) TYPE abap_boolean.

    "! Hay algun titular actual del tipo que NO esta en el archivo (it_rows): la estandar le da de baja el
    "! tipo por ausencia. iv_todas_soc: titulares de todas las sociedades (Tucuman y Salta, como sus keepers).
    METHODS hay_bajas_por_ausencia
      IMPORTING iv_sociedad   TYPE bukrs
                iv_tipo       TYPE zarba_ret_log-tipo_ret
                iv_todas_soc  TYPE abap_boolean
                it_rows       TYPE zcl_arba_ret_exporter=>ty_rows
      RETURNING VALUE(rv_hay) TYPE abap_boolean.

    "! Mensaje para el usuario de hasta 200 caracteres (new_message_with_text corta en 50): mensaje 000
    "! ("&1&2&3&4") de la clase ZARBA_RET_TUC con el texto repartido en las 4 variables. Usado en Tucuman.
    METHODS msg_texto
      IMPORTING iv_severity   TYPE if_abap_behv_message=>t_severity
                iv_texto      TYPE string
      RETURNING VALUE(ro_msg) TYPE REF TO if_abap_behv_message.
ENDCLASS.


CLASS lhc_ejecucion IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Scaffold: se conceden todas las operaciones. La autorizacion real
    " (EF seccion 13: perfil que simula/consulta != perfil que ejecuta en real;
    " restriccion por sociedad) se implementa aqui en conjunto con IAM en el tenant.
    result-%create          = if_abap_behv=>auth-allowed.
    result-%update          = if_abap_behv=>auth-allowed.
    result-%delete          = if_abap_behv=>auth-allowed.
    result-%action-Simular           = if_abap_behv=>auth-allowed.
    result-%action-Ejecutar          = if_abap_behv=>auth-allowed.
    result-%action-ExportarCambios   = if_abap_behv=>auth-allowed.
    result-%action-AplicarExenciones = if_abap_behv=>auth-allowed.
  ENDMETHOD.

  METHOD setdefaults.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        FIELDS ( IdEjecucion EstadoEjecucion ModoSimulacion ActualizarSoloPadron Provincia ModoArchivo Usuario FechaHora )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    LOOP AT lt_ejec INTO DATA(ls).
      " Defaults SOLO en la creacion real (cuando todavia no hay IdEjecucion).
      " Esta determination 'on modify { create; }' se RE-DISPARA al ACTIVAR el draft; si
      " volvieramos a defaultear ahi, pisariamos los checkboxes que el usuario desmarco
      " (para un boolean "desmarcado" = INITIAL, indistinguible de "sin setear"). Como
      " IdEjecucion se estampa en el primer create, ya-seteado => no volver a tocar nada.
      IF ls-IdEjecucion IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      APPEND VALUE #(
        %tky                 = ls-%tky
        IdEjecucion          = |EJ{ lv_now }|
        " PENDIENTE hasta que se lance Simular/Ejecutar (recien ahi pasa a EN_PROCESO). Antes nacia
        " EN_PROCESO y una ejecucion creada pero nunca lanzada parecia colgada.
        EstadoEjecucion      = COND #( WHEN ls-EstadoEjecucion IS INITIAL THEN 'PENDIENTE' ELSE ls-EstadoEjecucion )
        ModoSimulacion       = abap_false   " informativo: lo marca el proceso (ultima corrida simulada)
        ActualizarSoloPadron = 'X'
        " Sin provincia por defecto (pedido funcional): la elige el usuario.
        Provincia            = ls-Provincia
        " Siempre debe haber un Modo (Tucuman): por defecto 'A' (Acreditan). El usuario lo cambia a 'C'
        " (Coeficientes) para habilitar "Indicador CM Coef. 0".
        ModoArchivo          = COND #( WHEN ls-ModoArchivo IS INITIAL THEN zcl_arba_ret_tuc_parser=>c_modo-acreditan ELSE ls-ModoArchivo )
        Usuario              = COND #( WHEN ls-Usuario IS INITIAL THEN sy-uname ELSE ls-Usuario )
        FechaHora            = COND #( WHEN ls-FechaHora IS INITIAL THEN lv_now ELSE ls-FechaHora ) )
      TO lt_upd.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FIELDS ( IdEjecucion EstadoEjecucion ModoSimulacion ActualizarSoloPadron Provincia ModoArchivo Usuario FechaHora )
        WITH lt_upd
      REPORTED DATA(lr).
  ENDMETHOD.

  METHOD setindicadorfuera.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia IndicadorFueraPadron ProvinciaAplicada )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    LOOP AT lt_ejec INTO DATA(ls).
      " Sin indicador por defecto (pedido funcional: cambiar la provincia y olvidar el indicador daba
      " error). Solo actua cuando la provincia CAMBIO respecto de ProvinciaAplicada:
      "  - Primera eleccion de provincia (ProvinciaAplicada vacia): se conserva lo que cargo el usuario.
      "  - Cambio de provincia: se LIMPIA el indicador (el de otra provincia no corresponde).
      "  - En el grabado la determinacion re-dispara, pero Provincia = ProvinciaAplicada => no toca nada.
      IF ls-Provincia = ls-ProvinciaAplicada.
        CONTINUE.
      ENDIF.

      DATA lv_ind TYPE zcl_arba_ret_determinador=>ty_wht_code.
      lv_ind = COND #( WHEN ls-ProvinciaAplicada IS INITIAL THEN ls-IndicadorFueraPadron ELSE '' ).

      APPEND VALUE #( %tky                 = ls-%tky
                      IndicadorFueraPadron = lv_ind
                      ProvinciaAplicada    = ls-Provincia ) TO lt_upd.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FIELDS ( IndicadorFueraPadron ProvinciaAplicada )
        WITH lt_upd
      REPORTED DATA(lr).
  ENDMETHOD.

  METHOD sethidetuc.
    " HideTuc controla la visibilidad de los parametros de Tucuman (@UI.hidden: #(HideTuc)).
    " Los campos calculados NO se recomputan en draft, por eso HideTuc es un campo persistente
    " que esta determinacion mantiene: 'X' (ocultar) cuando la provincia NO es 'TUC'.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    LOOP AT lt_ejec INTO DATA(ls).
      APPEND VALUE #( %tky    = ls-%tky
                      HideTuc = COND #( WHEN ls-Provincia = 'TUC' THEN abap_false ELSE abap_true ) ) TO lt_upd.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FIELDS ( HideTuc )
        WITH lt_upd
      REPORTED DATA(lr_h).
  ENDMETHOD.

  METHOD sethidesal.
    " Salta: HideSal persistente (los calculados no se recomputan en draft, igual que HideTuc) y limpieza
    " del "Indicador Fuera de Padron No Salta" cuando la provincia deja de ser SAL.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia HideSal IndicadorFueraPadronNoSal )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).
    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    LOOP AT lt_ejec INTO DATA(ls).
      DATA(lv_es_sal) = xsdbool( ls-Provincia = zcl_arba_ret_sal_param=>c_provincia ).
      DATA(lv_hide)   = COND abap_boolean( WHEN lv_es_sal = abap_true THEN abap_false ELSE abap_true ).
      DATA(lv_ind2)   = COND #( WHEN lv_es_sal = abap_true THEN ls-IndicadorFueraPadronNoSal ELSE '' ).
      IF lv_hide = ls-HideSal AND lv_ind2 = ls-IndicadorFueraPadronNoSal.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = ls-%tky HideSal = lv_hide IndicadorFueraPadronNoSal = lv_ind2
                      %control-HideSal = if_abap_behv=>mk-on %control-IndicadorFueraPadronNoSal = if_abap_behv=>mk-on ) TO lt_upd.
    ENDLOOP.
    CHECK lt_upd IS NOT INITIAL.
    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion UPDATE FROM lt_upd
      REPORTED DATA(lr_s).
  ENDMETHOD.

  METHOD get_instance_features.
    " Parametros de Tucuman editables segun el Modo (EF 6; Redmine 33748, 02/09 y 17/09):
    "   - Modo C (Coeficientes): el archivo solo procesa los CUIT que trae -> se grisan Solo Padron,
    "     Indicador y Tipo Ret. Fuera de Padron e Ind. Ret. Exento CM (son de Acreditan).
    "   - Modo A (Acreditan): se grisa "Indicador CM Coef. 0" (solo aplica a Coeficientes).
    " Otras provincias: todo editable (ARBA/CABA/SF usan Solo Padron e Indicador Fuera de Padron).
    " Se reevalua en draft al cambiar Provincia o ModoArchivo (side effects 'affects permissions').
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia ModoArchivo )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec)
      FAILED failed.

    DATA ls_res LIKE LINE OF result.
    LOOP AT lt_ejec INTO DATA(ls).
      DATA(lv_tuc)    = xsdbool( ls-Provincia = 'TUC' ).
      DATA(lv_modo_c) = xsdbool( ls-ModoArchivo = zcl_arba_ret_tuc_parser=>c_modo-coeficientes ).
      CLEAR ls_res.
      ls_res-%tky = ls-%tky.
      ls_res-%field-ActualizarSoloPadron = COND #( WHEN lv_tuc = abap_true AND lv_modo_c = abap_true
                                                   THEN if_abap_behv=>fc-f-read_only
                                                   ELSE if_abap_behv=>fc-f-unrestricted ).
      ls_res-%field-IndicadorFueraPadron = ls_res-%field-ActualizarSoloPadron.
      ls_res-%field-TipoRetFueraPadron   = ls_res-%field-ActualizarSoloPadron.
      ls_res-%field-IndicadorExentoCM    = ls_res-%field-ActualizarSoloPadron.
      ls_res-%field-IndicadorCmCoef0     = COND #( WHEN lv_tuc = abap_true AND lv_modo_c = abap_false
                                                   THEN if_abap_behv=>fc-f-read_only
                                                   ELSE if_abap_behv=>fc-f-unrestricted ).
      " Solo con Retencion Existente: el proceso de Tucuman no lo usa.
      ls_res-%field-SoloConRetencion     = COND #( WHEN lv_tuc = abap_true
                                                   THEN if_abap_behv=>fc-f-read_only
                                                   ELSE if_abap_behv=>fc-f-unrestricted ).
      APPEND ls_res TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD settipoindfuera.
    " TipoIndFuera es el tipo por el que filtra el matchcode de "Indicador Fuera de Padron" (additionalBinding
    " en ZC_ARBA_RET_EJECUCION). En Tucuman el indicador fuera de padron es del tipo No Inscriptos
    " (TipoRetFueraPadron); en ARBA/CABA/SF es del mismo tipo del padron (TipoRetencion), como antes.
    " Es persistente (mismo motivo que HideTuc: los campos calculados no se recomputan en draft).
    " Se refresca en la UI via los side effects 'field Provincia/TipoRetencion/TipoRetFueraPadron affects'.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia TipoRetencion TipoRetFueraPadron TipoIndFuera )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    LOOP AT lt_ejec INTO DATA(ls).
      DATA(lv_tipo) = COND #( WHEN ls-Provincia = 'TUC' THEN ls-TipoRetFueraPadron ELSE ls-TipoRetencion ).
      IF lv_tipo = ls-TipoIndFuera.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky         = ls-%tky
                      TipoIndFuera = lv_tipo ) TO lt_upd.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FIELDS ( TipoIndFuera )
        WITH lt_upd
      REPORTED DATA(lr_t).
  ENDMETHOD.

  METHOD limpiarpormodo.
    " Redmine 33748 (07/10): si el usuario cambia el Modo despues de cargar datos, los parametros que pasan a
    " grisados se blanquean (no deben quedar valores ocultos que confundan). Solo Tucuman.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia ModoArchivo IndicadorFueraPadron TipoRetFueraPadron
                                IndicadorExentoCM IndicadorCmCoef0 ActualizarSoloPadron )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    LOOP AT lt_ejec INTO DATA(ls) WHERE Provincia = 'TUC'.
      IF ls-ModoArchivo = zcl_arba_ret_tuc_parser=>c_modo-coeficientes.
        " Solo Padron queda tildado: Coeficientes procesa solo los CUIT del archivo.
        IF ls-IndicadorFueraPadron IS INITIAL AND ls-TipoRetFueraPadron IS INITIAL AND ls-IndicadorExentoCM IS INITIAL
           AND ls-ActualizarSoloPadron = abap_true.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( %tky                          = ls-%tky
                        IndicadorFueraPadron          = ''
                        TipoRetFueraPadron            = ''
                        IndicadorExentoCM             = ''
                        ActualizarSoloPadron          = abap_true
                        %control-IndicadorFueraPadron = if_abap_behv=>mk-on
                        %control-TipoRetFueraPadron   = if_abap_behv=>mk-on
                        %control-IndicadorExentoCM    = if_abap_behv=>mk-on
                        %control-ActualizarSoloPadron = if_abap_behv=>mk-on ) TO lt_upd.
      ELSEIF ls-IndicadorCmCoef0 IS NOT INITIAL.
        APPEND VALUE #( %tky                      = ls-%tky
                        IndicadorCmCoef0          = ''
                        %control-IndicadorCmCoef0 = if_abap_behv=>mk-on ) TO lt_upd.
      ENDIF.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FROM lt_upd
      REPORTED DATA(lr_m).
  ENDMETHOD.

  METHOD limpiarindfuera.
    " Tucuman: el Indicador Fuera de Padron es del Tipo Ret. Fuera de Padron. Si cambia el tipo y el indicador
    " cargado no es de ese tipo, se limpia (mismo criterio que al cambiar la Provincia).
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia TipoRetFueraPadron IndicadorFueraPadron )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.
    DATA(lo_det) = NEW zcl_arba_ret_determinador( ).
    LOOP AT lt_ejec INTO DATA(ls) WHERE Provincia = 'TUC' AND IndicadorFueraPadron IS NOT INITIAL.
      DATA lv_est TYPE c LENGTH 3.
      CLEAR lv_est.
      IF ls-TipoRetFueraPadron IS NOT INITIAL.
        lo_det->obtener_alicuota_indicador( EXPORTING iv_tipo_ret  = ls-TipoRetFueraPadron
                                                      iv_indicador = ls-IndicadorFueraPadron
                                            IMPORTING ev_estado    = lv_est ).
        IF lv_est IS INITIAL.
          CONTINUE.   " el indicador es del tipo: se conserva
        ENDIF.
      ENDIF.
      APPEND VALUE #( %tky                          = ls-%tky
                      IndicadorFueraPadron          = ''
                      %control-IndicadorFueraPadron = if_abap_behv=>mk-on ) TO lt_upd.
    ENDLOOP.

    CHECK lt_upd IS NOT INITIAL.

    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FROM lt_upd
      REPORTED DATA(lr_i).
  ENDMETHOD.

  METHOD validarparametrostuc.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia TipoRetencion ModoArchivo ActualizarSoloPadron
                                TipoRetFueraPadron IndicadorFueraPadron )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    LOOP AT lt_ejec INTO DATA(ls).
      APPEND VALUE #( %tky = ls-%tky %state_area = 'VAL_TUC' ) TO reported-ejecucion.
      IF ls-Provincia <> 'TUC'.
        CONTINUE.
      ENDIF.

      DATA lv_msg   TYPE string.
      DATA lv_campo TYPE string.
      CLEAR: lv_msg, lv_campo.

      " Tipo de Retencion: debe tener indicadores de Convenio Multilateral en la tabla de Tucuman (el 24).
      IF ls-TipoRetencion IS NOT INITIAL.
        SELECT SINGLE @abap_true FROM zi_arba_ret_tuc_clcm
          WHERE withholdingtaxtype = @ls-TipoRetencion AND convmult = 'X'
          INTO @DATA(lv_es_tuc).
        IF sy-subrc <> 0.
          lv_msg = |El Tipo de Retención { ls-TipoRetencion } no corresponde al padrón de Tucumán|. lv_campo = 'TIPO'.
        ENDIF.
      ENDIF.

      " El tipo de fuera de padron tiene que ser otro (Redmine 33748, nota #57): con el mismo tipo, el fuera
      " de padron le daba el tipo de padron por region y la baja del tipo de fuera de padron se lo sacaria a
      " todo el padron.
      IF lv_msg IS INITIAL AND ls-TipoRetFueraPadron IS NOT INITIAL AND ls-TipoRetFueraPadron = ls-TipoRetencion.
        lv_msg = 'El Tipo Ret. Fuera de Padrón tiene que ser distinto del Tipo de Retención'. lv_campo = 'TIPOFP'.
      ENDIF.

      " Modo A sin Solo Padron (sincronizacion completa): Tipo e Indicador Fuera de Padron obligatorios.
      IF lv_msg IS INITIAL AND ls-ModoArchivo <> zcl_arba_ret_tuc_parser=>c_modo-coeficientes.
        IF ls-ActualizarSoloPadron = abap_false AND ls-TipoRetFueraPadron IS INITIAL.
          lv_msg = 'Ingrese el Tipo Ret. Fuera de Padrón'. lv_campo = 'TIPOFP'.
        ELSEIF ls-ActualizarSoloPadron = abap_false AND ls-IndicadorFueraPadron IS INITIAL.
          lv_msg = 'Ingrese el Indicador Fuera de Padrón'. lv_campo = 'IND'.
        ELSEIF ls-IndicadorFueraPadron IS NOT INITIAL AND ls-TipoRetFueraPadron IS NOT INITIAL.
          DATA lv_est TYPE c LENGTH 3.
          CLEAR lv_est.
          NEW zcl_arba_ret_determinador( )->obtener_alicuota_indicador(
            EXPORTING iv_tipo_ret  = ls-TipoRetFueraPadron
                      iv_indicador = ls-IndicadorFueraPadron
            IMPORTING ev_estado    = lv_est ).
          IF lv_est IS NOT INITIAL.
            lv_msg = |El Indicador { ls-IndicadorFueraPadron } no corresponde al Tipo { ls-TipoRetFueraPadron }|. lv_campo = 'IND'.
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_msg IS INITIAL.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = ls-%tky ) TO failed-ejecucion.
      APPEND VALUE #( %tky        = ls-%tky
                      %state_area = 'VAL_TUC'
                      %msg        = msg_texto( iv_severity = if_abap_behv_message=>severity-error
                                               iv_texto    = lv_msg )
                      %element-TipoRetencion        = COND #( WHEN lv_campo = 'TIPO'   THEN if_abap_behv=>mk-on )
                      %element-TipoRetFueraPadron   = COND #( WHEN lv_campo = 'TIPOFP' THEN if_abap_behv=>mk-on )
                      %element-IndicadorFueraPadron = COND #( WHEN lv_campo = 'IND'    THEN if_abap_behv=>mk-on ) )
             TO reported-ejecucion.
    ENDLOOP.
  ENDMETHOD.

  METHOD simular.
    " Chequeos (ya procesada en real, proceso en curso, parametros, archivo): motivo_no_lanzable.
    LOOP AT keys INTO DATA(k).
      DATA(lv_motivo) = motivo_no_lanzable( k-EjecucionUUID ).
      IF lv_motivo IS NOT INITIAL.
        APPEND VALUE #( %tky = k-%tky ) TO failed-ejecucion.
        APPEND VALUE #( %tky = k-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = lv_motivo ) )
               TO reported-ejecucion.
        CONTINUE.
      ENDIF.
      lanzar_job( iv_uuid = k-EjecucionUUID iv_simular = abap_true ).
    ENDLOOP.

    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_res).
    result = VALUE #( FOR l IN lt_res ( %tky = l-%tky %param = CORRESPONDING #( l ) ) ).
  ENDMETHOD.

  METHOD ejecutar.
    " Chequeos (ya procesada en real, proceso en curso, parametros, archivo): motivo_no_lanzable.
    LOOP AT keys INTO DATA(k).
      DATA(lv_motivo) = motivo_no_lanzable( k-EjecucionUUID ).
      IF lv_motivo IS NOT INITIAL.
        APPEND VALUE #( %tky = k-%tky ) TO failed-ejecucion.
        APPEND VALUE #( %tky = k-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = lv_motivo ) )
               TO reported-ejecucion.
        CONTINUE.
      ENDIF.
      lanzar_job( iv_uuid = k-EjecucionUUID iv_simular = abap_false ).
    ENDLOOP.

    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_res).
    result = VALUE #( FOR l IN lt_res ( %tky = l-%tky %param = CORRESPONDING #( l ) ) ).
  ENDMETHOD.

  METHOD exportarcambios.
    DATA(lo_exporter) = NEW zcl_arba_ret_exporter( ).
    DATA lt_upd TYPE TABLE FOR UPDATE zi_arba_ret_ejecucion.

    LOOP AT keys INTO DATA(k).
      " ID de ejecucion (para el nombre del archivo)
      READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
        ENTITY Ejecucion FIELDS ( IdEjecucion Provincia TipoRetencion Sociedad ActualizarSoloPadron
                                  ModoSimulacion EstadoEjecucion TotalLeidos TotalNoEncontrados FechaHora
                                  ModoArchivo TipoRetFueraPadron ProvDesde ProvHasta )
          WITH VALUE #( ( EjecucionUUID = k-EjecucionUUID ) )
        RESULT DATA(lt_ejec).

      " Solo corridas REALES finalizadas: la BAdI de la app estandar toma los codigos de la ultima
      " ejecucion real (no de simulaciones). Exportar una simulacion daria un archivo que no coincide
      " con lo que aplica la BAdI.
      IF lt_ejec IS NOT INITIAL
         AND ( lt_ejec[ 1 ]-ModoSimulacion = abap_true
               OR NOT ( lt_ejec[ 1 ]-EstadoEjecucion = 'OK' OR lt_ejec[ 1 ]-EstadoEjecucion = 'OK_CON_ERRORES' ) ).
        APPEND VALUE #( %tky = k-%tky ) TO failed-ejecucion.
        APPEND VALUE #( %tky = k-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'Solo se exporta una ejecucion real finalizada' ) )
               TO reported-ejecucion.
        CONTINUE.
      ENDIF.
      DATA lv_id       TYPE string.
      DATA lv_prov     TYPE c LENGTH 4.
      DATA lv_tipo_pad TYPE c LENGTH 2.
      DATA lv_soc      TYPE bukrs.
      DATA lv_solo     TYPE abap_boolean.
      DATA lv_leidos   TYPE i.
      DATA lv_noenc    TYPE i.
      CLEAR: lv_id, lv_prov, lv_tipo_pad, lv_soc, lv_solo, lv_leidos, lv_noenc.
      IF lt_ejec IS NOT INITIAL.
        lv_id       = lt_ejec[ 1 ]-IdEjecucion.
        lv_prov     = lt_ejec[ 1 ]-Provincia.
        lv_tipo_pad = lt_ejec[ 1 ]-TipoRetencion.
        lv_soc      = lt_ejec[ 1 ]-Sociedad.
        lv_solo     = lt_ejec[ 1 ]-ActualizarSoloPadron.
        lv_leidos   = lt_ejec[ 1 ]-TotalLeidos.
        lv_noenc    = lt_ejec[ 1 ]-TotalNoEncontrados.
      ENDIF.
      IF lv_id IS INITIAL.
        lv_id = |{ k-EjecucionUUID }|.
      ENDIF.

      " El .txt es un SNAPSHOT COMPLETO de quien DEBE tener el tipo. La app estandar BORRA por
      " AUSENCIA: a todo titular del tipo que NO este en el archivo le elimina el tipo + sus partidas.
      " Por eso se incluyen:
      "   'ACT' -> cambios (alta / cambio de codigo / fuera-de-padron)
      "   'SCB' -> titulares sin cambio (in-padron ya correctos + fuera-de-padron ya en el maximo)
      "   'PCF' -> in-padron cuya alicuota no resuelve a un codigo unico (0%, ambiguo, sin config): se
      "            incluye con la alicuota del archivo para que la estandar NO lo borre; la BAdI, al dar
      "            PCF, deja el codigo ACTUAL -> el proveedor se MANTIENE sin cambio (y el PCF queda
      "            logueado para revisar la config). Sin esto, un proveedor a 0% (p.ej.) se borraba.
      "            EXCEPTO caso '1' (proveedor SIN el tipo): no hay nada que conservar y en la estandar
      "            aparecia con el indicador nuevo vacio -> no va al archivo (queda en el log y en el Resumen).
      " Se EXCLUYE 'REG' (cambio de regimen) a proposito: al no ir en el archivo, la estandar le borra
      " el tipo viejo (maestro + partidas). El log ya esta persistido por el job; se lee directo.
      SELECT cuit, alicuota_nueva, tipo_contribuyente, marca_alta_baja, marca_cambio_alic,
             nro_grupo, fecha_publicacion, vigencia_desde, vigencia_hasta, tipo_ret,
             estado, indicador_anterior, caso, indicador_nuevo
        FROM zarba_ret_log
        WHERE ejecucion_uuid = @k-EjecucionUUID
          AND ( estado IN ( 'ACT', 'SCB' ) OR ( estado = 'PCF' AND caso <> '1' ) )
        ORDER BY nro_linea, cuit
        INTO TABLE @DATA(lt_log).

      " Redmine 33756 (09/10): un PCF (alicuota sin indicador equivalente) es un error insalvable y NO debe
      " llegar a la grilla de la app estandar. Con la alicuota del ARCHIVO la estandar lo mostraba (alicuota
      " distinta a la del codigo actual) aunque el codigo no cambie. Va con la alicuota de su codigo ACTUAL,
      " igual que un keeper: sin cambio -> la estandar no lo muestra ni lo borra. Sin codigo actual (no es
      " titular del tipo; p.ej. Tucuman, que no informa caso) no hay nada que conservar -> fuera del archivo.
      DATA(lo_det_pcf) = NEW zcl_arba_ret_determinador( ).
      LOOP AT lt_log ASSIGNING FIELD-SYMBOL(<ls_pcf>) WHERE estado = 'PCF'.
        IF <ls_pcf>-indicador_anterior IS INITIAL.
          DELETE lt_log.
          CONTINUE.
        ENDIF.
        DATA lv_alic_pcf TYPE zcl_arba_ret_determinador=>ty_alicuota.
        DATA lv_est_pcf  TYPE c LENGTH 3.
        DATA lv_msg_pcf  TYPE string.
        CLEAR: lv_alic_pcf, lv_est_pcf, lv_msg_pcf.
        lo_det_pcf->obtener_alicuota_indicador(
          EXPORTING iv_tipo_ret  = CONV zcl_arba_ret_determinador=>ty_wht_type(
                                     COND #( WHEN <ls_pcf>-tipo_ret IS INITIAL THEN lv_tipo_pad ELSE <ls_pcf>-tipo_ret ) )
                    iv_indicador = <ls_pcf>-indicador_anterior
          IMPORTING ev_alicuota  = lv_alic_pcf
                    ev_estado    = lv_est_pcf
                    ev_mensaje   = lv_msg_pcf ).
        IF lv_est_pcf IS INITIAL.
          <ls_pcf>-alicuota_nueva = lv_alic_pcf.
        ENDIF.
      ENDLOOP.

      " Sin filas exportables del padron: no hay nada que aplicar. En las provincias que lo piden
      " (export_requiere_padron) NO se genera el .zip y se avisa con error; si no, el archivo saldria solo
      " con los keepers (sin cambios) y la estandar no mostraria nada para actualizar (Redmine 33748, 09/10:
      " archivo real con 3 CUIT que no son proveedores -> 3 NOE -> .zip con 3 keepers -> vista previa vacia).
      IF lt_log IS INITIAL AND export_requiere_padron( lv_prov ) = abap_true.
        APPEND VALUE #( %tky = k-%tky ) TO failed-ejecucion.
        " Mensaje para el usuario final, sin vincular a la instancia: asi no muestra el ID tecnico de la corrida.
        APPEND msg_texto(
                 iv_severity = if_abap_behv_message=>severity-error
                 iv_texto    = COND #( WHEN lv_leidos > 0 AND lv_noenc = lv_leidos
                                    THEN `No se generó el archivo: ningún CUIT del padrón es proveedor en SAP. Ver "No Encontrados" en el Resumen.`
                                    ELSE `No se generó el archivo: el padrón no trajo cambios para aplicar.` ) )
               TO reported-%other.
        CONTINUE.
      ENDIF.

      DATA(lv_fname) = |padron_cambios_{ lv_id }|.
      " Tucuman: nombre legible (provincia, tipo, fecha y hora de la corrida) en vez del ID tecnico de la
      " ejecucion (Ivan 19/10: el usuario final no es de sistemas). La fecha es la de "Fecha y Hora".
      DATA lv_fstamp TYPE string.
      CLEAR lv_fstamp.
      IF lv_prov = 'TUC' AND lt_ejec IS NOT INITIAL.
        DATA lv_ts_c TYPE c LENGTH 14.
        lv_ts_c   = CONV timestamp( lt_ejec[ 1 ]-FechaHora ).
        lv_fstamp = |{ lv_ts_c+6(2) }-{ lv_ts_c+4(2) }-{ lv_ts_c(4) }_{ lv_ts_c+8(2) }-{ lv_ts_c+10(2) }|.
        lv_fname  = |Padron_Tucuman_{ lv_fstamp }|.
      ENDIF.
      " Nombre de la descarga y tipos que lleva (Tucuman: el nombre dice el tipo, ver mas abajo).
      DATA(lv_expname) = |{ lv_fname }.zip|.
      DATA lv_exp_tipos TYPE string.
      CLEAR lv_exp_tipos.
      DATA lv_zip TYPE xstring.
      " Sin registros para actualizar (todos ya tienen el indicador correcto y no hay bajas por ausencia): no
      " se genera el .zip, asi el usuario sabe que no tiene que correr Actualizar Codigos y Partidas (Redmine
      " 33748, 03/11). Vale para todas las provincias; en Tucuman se evalua por tipo (24 / TN).
      DATA(lv_msg_sin_cambios) = `No se generó el archivo: no hay registros para actualizar (ya tienen el indicador correcto). No hace falta correr Actualizar Códigos y Partidas.`.
      " Mensajes informativos del export: se informan solo si el archivo se genera.
      DATA lt_rep_exp LIKE reported-ejecucion.
      CLEAR lt_rep_exp.

      " Tucuman puede llevar DOS tipos en la misma corrida (24 padron + TN fuera de padron): se exporta
      " una entrada .txt por tipo, porque la app estandar se corre una vez por tipo (cada snapshot da
      " de alta/baja SU tipo por presencia/ausencia). Resto / un solo tipo: un unico .txt. tipo_ret
      " vacio (corridas anteriores) se asume el tipo de padron de la ejecucion.
      " Tucuman (Redmine 33748): cada archivo lleva SIEMPRE a los titulares actuales del tipo que no vienen
      " en el export (keepers), en todos los modos y de todas las sociedades: la app estandar borra por
      " ausencia. Los que pasan de un tipo al otro (24 <-> TN) estan en el export, por eso no son keepers.
      DATA lt_exp_tuc   TYPE ty_cuit_tt.
      DATA lv_cons_t    TYPE i.
      DATA lv_sincuit_t TYPE i.
      CLEAR: lt_exp_tuc, lv_cons_t, lv_sincuit_t.
      IF lv_prov = 'TUC'.
        LOOP AT lt_log INTO DATA(ls_ct).
          APPEND ls_ct-cuit TO lt_exp_tuc.
        ENDLOOP.
      ENDIF.

      DATA lt_tipos TYPE SORTED TABLE OF zarba_ret_log-tipo_ret WITH UNIQUE KEY table_line.
      CLEAR lt_tipos.
      IF lv_prov = 'TUC'.
        " El tipo de padron se evalua siempre (puede tener bajas aunque no haya filas del archivo).
        INSERT CONV #( lv_tipo_pad ) INTO TABLE lt_tipos.
        LOOP AT lt_log INTO DATA(ls_t).
          INSERT COND #( WHEN ls_t-tipo_ret IS INITIAL THEN lv_tipo_pad ELSE ls_t-tipo_ret ) INTO TABLE lt_tipos.
        ENDLOOP.
      ENDIF.

      " Tucuman va siempre por aca (aunque haya un solo tipo): cada tipo genera su archivo solo si tiene
      " registros para actualizar.
      IF lines( lt_tipos ) > 1 OR lv_prov = 'TUC'.
        DATA lt_entries TYPE zcl_arba_ret_exporter=>ty_zip_entries.
        DATA lv_tipos_sin TYPE string.
        CLEAR: lt_entries, lv_tipos_sin.
        " Tucuman (nota #57): CUIT que vinieron en el archivo (cualquier estado; las filas del archivo tienen
        " nro de linea) y proveedores cuya alta del tipo de fuera de padron fallo u se omitio (no pierden el
        " tipo de padron: quedarian sin ninguno).
        DATA lt_cuit_arch TYPE ty_cuit_tt.
        DATA lt_proteger  TYPE zcl_arba_ret_alta=>ty_sup_tt.
        DATA lv_bajas_pad TYPE i.
        DATA lv_r2        TYPE abap_boolean.
        CLEAR: lt_cuit_arch, lt_proteger, lv_bajas_pad, lv_r2.
        " Baja del tipo de padron a los que no vienen en el archivo (R2): solo una corrida completa de
        " Acreditan con un tipo de fuera de padron distinto (corridas viejas 24/24 o Modo C no la tienen).
        IF lv_prov = 'TUC' AND lv_solo = abap_false AND lt_ejec IS NOT INITIAL
           AND lt_ejec[ 1 ]-ModoArchivo <> zcl_arba_ret_tuc_parser=>c_modo-coeficientes
           AND lt_ejec[ 1 ]-TipoRetFueraPadron IS NOT INITIAL
           AND lt_ejec[ 1 ]-TipoRetFueraPadron <> lv_tipo_pad.
          lv_r2 = abap_true.
          " Si no se pudo leer la region, el fuera de padron no dio las altas del TN: sin R2, para que nadie
          " quede sin ningun tipo (mismo blindaje que procesar_fuera_padron).
          SELECT SINGLE @abap_true FROM zarba_ret_log
            WHERE ejecucion_uuid = @k-EjecucionUUID AND caso = '3' AND estado = 'OMI' AND proveedor = @space
            INTO @DATA(lv_sin_region).
          IF sy-subrc = 0 AND lv_sin_region = abap_true.
            lv_r2 = abap_false.
            APPEND msg_texto(
                     iv_severity = if_abap_behv_message=>severity-warning
                     iv_texto    = |No se dan de baja del Tipo { lv_tipo_pad } los proveedores que no vienen en el padrón: en la corrida no se pudo leer la región.| )
                   TO reported-%other.
          ENDIF.
        ENDIF.
        IF lv_r2 = abap_true.
          SELECT DISTINCT cuit FROM zarba_ret_log
            WHERE ejecucion_uuid = @k-EjecucionUUID AND nro_linea > 0 AND cuit <> @space
            INTO TABLE @lt_cuit_arch.
          SELECT DISTINCT proveedor FROM zarba_ret_log
            WHERE ejecucion_uuid = @k-EjecucionUUID AND caso = '1' AND tipo_ret <> @lv_tipo_pad
              AND tipo_ret <> @space AND estado IN ( 'ETE', 'OMI' ) AND proveedor <> @space
            INTO TABLE @lt_proteger.
        ENDIF.
        LOOP AT lt_tipos INTO DATA(lv_tipo).
          DATA lt_rows_t   TYPE zcl_arba_ret_exporter=>ty_rows.
          DATA lt_cuit_t   TYPE ty_cuit_tt.
          DATA lv_cambio_t TYPE abap_boolean.
          CLEAR: lt_rows_t, lt_cuit_t, lv_cambio_t.
          LOOP AT lt_log INTO DATA(ls_r).
            DATA(lv_eff) = COND #( WHEN ls_r-tipo_ret IS INITIAL THEN lv_tipo_pad ELSE ls_r-tipo_ret ).
            IF lv_eff <> lv_tipo.
              CONTINUE.
            ENDIF.
            APPEND ls_r-cuit TO lt_cuit_t.
            IF es_cambio_std( iv_estado  = ls_r-estado iv_caso = ls_r-caso
                              iv_ind_ant = ls_r-indicador_anterior iv_ind_nue = ls_r-indicador_nuevo ) = abap_true.
              lv_cambio_t = abap_true.
            ENDIF.
            APPEND VALUE #( cuit               = ls_r-cuit
                            alicuota           = ls_r-alicuota_nueva
                            tipo_contribuyente = ls_r-tipo_contribuyente
                            marca_alta_baja    = ls_r-marca_alta_baja
                            marca_cambio_alic  = ls_r-marca_cambio_alic
                            nro_grupo          = ls_r-nro_grupo
                            fecha_publicacion  = ls_r-fecha_publicacion
                            vigencia_desde     = ls_r-vigencia_desde
                            vigencia_hasta     = ls_r-vigencia_hasta ) TO lt_rows_t.
          ENDLOOP.
          IF lv_prov = 'TUC'.
            DATA lt_keep_t TYPE zcl_arba_ret_exporter=>ty_rows.
            DATA lv_c_t    TYPE i.
            DATA lv_s_t    TYPE i.
            DATA lv_b_t    TYPE i.
            keepers_tuc( EXPORTING iv_sociedad     = lv_soc
                                   iv_tipo         = lv_tipo
                                   it_export_cuit  = lt_exp_tuc
                                   it_cuit_tipo    = lt_cuit_t
                                   iv_bajas_padron = xsdbool( lv_r2 = abap_true AND lv_tipo = lv_tipo_pad )
                                   it_cuit_archivo = lt_cuit_arch
                                   it_proteger     = lt_proteger
                                   iv_prov_desde   = lt_ejec[ 1 ]-ProvDesde
                                   iv_prov_hasta   = lt_ejec[ 1 ]-ProvHasta
                         IMPORTING et_rows = lt_keep_t ev_conservados = lv_c_t ev_sin_cuit = lv_s_t ev_bajas = lv_b_t ).
            APPEND LINES OF lt_keep_t TO lt_rows_t.
            " Sin cambios de codigo ni bajas en este tipo: no se genera su archivo (03/11: salia el .zip del
            " TN solo con titulares que quedaban igual y la estandar no mostraba nada). Sin filas tampoco: la
            " estandar rechaza el .txt vacio.
            IF lt_rows_t IS INITIAL
               OR ( lv_cambio_t = abap_false
                    AND hay_bajas_por_ausencia( iv_sociedad = lv_soc iv_tipo = lv_tipo iv_todas_soc = abap_true
                                                it_rows = lt_rows_t ) = abap_false ).
              lv_tipos_sin = COND #( WHEN lv_tipos_sin IS INITIAL THEN lv_tipo ELSE |{ lv_tipos_sin } y { lv_tipo }| ).
              CONTINUE.
            ENDIF.
            lv_cons_t    = lv_cons_t + lv_c_t.
            lv_sincuit_t = lv_sincuit_t + lv_s_t.
            IF lv_tipo = lv_tipo_pad.
              lv_bajas_pad = lv_bajas_pad + lv_b_t.
            ENDIF.
          ENDIF.
          IF lt_rows_t IS NOT INITIAL.
            lv_exp_tipos = COND #( WHEN lv_exp_tipos IS INITIAL THEN lv_tipo ELSE |{ lv_exp_tipos } y { lv_tipo }| ).
          ENDIF.
          APPEND VALUE #( name = COND string( WHEN lv_prov = 'TUC' THEN |Padron_Tucuman_Tipo{ lv_tipo }_{ lv_fstamp }.txt|
                                              ELSE |{ lv_fname }_{ lv_tipo }.txt| )
                          txt  = lo_exporter->build_txt( it_rows = lt_rows_t iv_provincia = lv_prov ) ) TO lt_entries.
        ENDLOOP.
        IF lt_entries IS INITIAL.
          APPEND VALUE #( %tky = k-%tky ) TO failed-ejecucion.
          APPEND msg_texto( iv_severity = if_abap_behv_message=>severity-error iv_texto = lv_msg_sin_cambios )
                 TO reported-%other.
          CONTINUE.
        ENDIF.
        IF lv_prov = 'TUC'.
          " La app estandar acepta un .zip con UN solo .txt y rechaza los .txt vacios: se arma un .zip por
          " tipo (sin los vacios) dentro del .zip descargable. Si queda uno solo, se entrega ese directo.
          DATA lt_inner   TYPE STANDARD TABLE OF xstring WITH EMPTY KEY.
          DATA lt_inner_n TYPE string_table.
          CLEAR: lt_inner, lt_inner_n.
          LOOP AT lt_entries INTO DATA(ls_en) WHERE txt IS NOT INITIAL.
            APPEND lo_exporter->build_zip( iv_txt = ls_en-txt iv_entryname = ls_en-name ) TO lt_inner.
            APPEND replace( val = ls_en-name sub = '.txt' with = '.zip' ) TO lt_inner_n.
          ENDLOOP.
          IF lines( lt_inner ) = 1.
            lv_zip     = lt_inner[ 1 ].
            lv_expname = lt_inner_n[ 1 ].
          ELSE.
            DATA(lo_outer) = NEW cl_abap_zip( ).
            LOOP AT lt_inner INTO DATA(lv_inner).
              DATA(lv_ix) = sy-tabix.
              lo_outer->add( name = lt_inner_n[ lv_ix ] content = lv_inner ).
            ENDLOOP.
            lv_zip = lo_outer->save( ).
          ENDIF.
        ELSE.
          lv_zip = lo_exporter->build_zip_multi( it_entries = lt_entries ).
        ENDIF.
      ELSE.
        DATA(lt_rows) = VALUE zcl_arba_ret_exporter=>ty_rows(
          FOR ls IN lt_log (
            cuit               = ls-cuit
            alicuota           = ls-alicuota_nueva
            tipo_contribuyente = ls-tipo_contribuyente
            marca_alta_baja    = ls-marca_alta_baja
            marca_cambio_alic  = ls-marca_cambio_alic
            nro_grupo          = ls-nro_grupo
            fecha_publicacion  = ls-fecha_publicacion
            vigencia_desde     = ls-vigencia_desde
            vigencia_hasta     = ls-vigencia_hasta ) ).

        " FIX borrado-por-ausencia: con "Solo Padron" (actualizacion parcial) los titulares del tipo que
        " NO vienen en el archivo NO deben borrarse. Se agregan al snapshot como KEEPERS (sin cambio) para
        " que la app estandar los deje tal cual. Generico ARBA/CABA/SF; Tucuman usa su propio mecanismo (TN).
        IF lv_prov = 'TUC'.
          DATA lt_keep_1 TYPE zcl_arba_ret_exporter=>ty_rows.
          keepers_tuc( EXPORTING iv_sociedad = lv_soc iv_tipo = CONV #( lv_tipo_pad ) it_export_cuit = lt_exp_tuc
                       IMPORTING et_rows = lt_keep_1 ev_conservados = lv_cons_t ev_sin_cuit = lv_sincuit_t ).
          APPEND LINES OF lt_keep_1 TO lt_rows.
        ENDIF.

        " #33749 H3b - ORIGINAL (se conserva comentado):
        " IF lv_solo = abap_true AND lv_prov <> 'TUC' AND lv_prov <> zcl_arba_ret_sal_param=>c_provincia.
        " #33749 H3b - Entre Rios excluido de keepers de una sociedad.
        IF lv_solo = abap_true AND lv_prov <> 'TUC' AND lv_prov <> zcl_arba_ret_sal_param=>c_provincia
           AND lv_prov <> zcl_arba_ret_er_param=>c_provincia.
          DATA lt_exp_cuit TYPE ty_cuit_tt.
          DATA lt_reg_cuit TYPE ty_cuit_tt.
          CLEAR: lt_exp_cuit, lt_reg_cuit.
          LOOP AT lt_log INTO DATA(ls_c).
            APPEND ls_c-cuit TO lt_exp_cuit.
          ENDLOOP.
          " REG (Santa Fe cambio de regimen): NO son keepers -> se dejan borrar por ausencia a proposito.
          SELECT cuit FROM zarba_ret_log
            WHERE ejecucion_uuid = @k-EjecucionUUID AND estado = 'REG'
            INTO TABLE @DATA(lt_reg_raw).
          LOOP AT lt_reg_raw INTO DATA(ls_reg).
            APPEND ls_reg-cuit TO lt_reg_cuit.
          ENDLOOP.

          DATA lt_keepers TYPE zcl_arba_ret_exporter=>ty_rows.
          DATA lv_cons    TYPE i.
          DATA lv_sincuit TYPE i.
          keepers_para_export(
            EXPORTING iv_sociedad    = lv_soc
                      iv_tipo        = lv_tipo_pad
                      it_export_cuit = lt_exp_cuit
                      it_reg_cuit    = lt_reg_cuit
            IMPORTING et_rows        = lt_keepers
                      ev_conservados = lv_cons
                      ev_sin_cuit    = lv_sincuit ).
          " Las lineas de conservacion llevan las fechas de la corrida (publicacion / vigencia) para que
          " se vean como el resto del archivo; la estandar solo usa CUIT y alicuota.
          IF lt_keepers IS NOT INITIAL.
            SELECT SINGLE fecha_publicacion, vigencia_desde, vigencia_hasta FROM zarba_ret_log
              WHERE ejecucion_uuid = @k-EjecucionUUID AND vigencia_hasta <> '00000000'
              INTO @DATA(ls_fechas).
            IF sy-subrc = 0.
              LOOP AT lt_keepers ASSIGNING FIELD-SYMBOL(<ls_keeper>).
                <ls_keeper>-fecha_publicacion = ls_fechas-fecha_publicacion.
                <ls_keeper>-vigencia_desde    = ls_fechas-vigencia_desde.
                <ls_keeper>-vigencia_hasta    = ls_fechas-vigencia_hasta.
              ENDLOOP.
            ENDIF.
          ENDIF.
          APPEND LINES OF lt_keepers TO lt_rows.

          " Contador + advertencia (los keepers NO van al Log de Auditoria; solo al snapshot del export).
          " Textos cortos: new_message_with_text recorta a ~50 caracteres.
          APPEND VALUE #( %tky = k-%tky
                          %msg = new_message_with_text(
                                   severity = if_abap_behv_message=>severity-information
                                   text     = |Exportado: { lines( lt_log ) } del padrón + { lv_cons } conservados| ) )
                 TO lt_rep_exp.
          IF lv_sincuit > 0.
            APPEND VALUE #( %tky = k-%tky
                            %msg = new_message_with_text(
                                     severity = if_abap_behv_message=>severity-warning
                                     text     = |Atención: { lv_sincuit } titulares sin CUIT (se borrarían)| ) )
                   TO lt_rep_exp.
          ENDIF.
        ENDIF.

        " Redmine 33756 (09/10): en modo completo, un CUIT del archivo RECHAZADO (REV / DUP: error insalvable)
        " no va en el snapshot -> si el proveedor ya es titular del tipo, la estandar le proponia la BAJA por
        " ausencia. Se lo conserva sin cambio (keeper con la alicuota de su codigo actual). En "Solo Padron" y
        " en Tucuman ya lo cubren los keepers de todos los titulares.
        " #33749 H3c - ORIGINAL (se conserva comentado):
        " IF lv_solo = abap_false AND lv_prov <> 'TUC' AND lv_prov <> zcl_arba_ret_sal_param=>c_provincia.
        " #33749 H3c - Entre Rios excluido del rescate de REV/DUP de una sociedad.
        IF lv_solo = abap_false AND lv_prov <> 'TUC' AND lv_prov <> zcl_arba_ret_sal_param=>c_provincia
           AND lv_prov <> zcl_arba_ret_er_param=>c_provincia.
          SELECT cuit FROM zarba_ret_log
            WHERE ejecucion_uuid = @k-EjecucionUUID AND estado IN ( 'REV', 'DUP' ) AND cuit <> @space
            INTO TABLE @DATA(lt_rech_raw).
          IF lt_rech_raw IS NOT INITIAL.
            DATA lt_exp_full  TYPE ty_cuit_tt.
            DATA lt_keep_rech TYPE zcl_arba_ret_exporter=>ty_rows.
            DATA lv_cons_rech TYPE i.
            DATA lv_sc_rech   TYPE i.
            CLEAR: lt_exp_full, lt_keep_rech, lv_cons_rech, lv_sc_rech.
            LOOP AT lt_log INTO DATA(ls_cf).
              APPEND ls_cf-cuit TO lt_exp_full.
            ENDLOOP.
            keepers_para_export(
              EXPORTING iv_sociedad    = lv_soc
                        iv_tipo        = lv_tipo_pad
                        it_export_cuit = lt_exp_full
                        it_reg_cuit    = VALUE #( )
              IMPORTING et_rows        = lt_keep_rech
                        ev_conservados = lv_cons_rech
                        ev_sin_cuit    = lv_sc_rech ).
            lv_cons_rech = 0.
            LOOP AT lt_keep_rech INTO DATA(ls_kr).
              IF line_exists( lt_rech_raw[ cuit = ls_kr-cuit ] ).
                APPEND ls_kr TO lt_rows.
                lv_cons_rech = lv_cons_rech + 1.
              ENDIF.
            ENDLOOP.
            IF lv_cons_rech > 0.
              APPEND VALUE #( %tky = k-%tky
                              %msg = new_message_with_text(
                                       severity = if_abap_behv_message=>severity-information
                                       text     = |{ lv_cons_rech } rechazados conservados sin cambio| ) )
                     TO lt_rep_exp.
            ENDIF.
          ENDIF.
        ENDIF.

        " #33749 H3d - Comentario ORIGINAL:
        " Salta: nunca quita el tipo por ausencia -> se conservan TODOS los titulares del tipo que no estan en el
        " archivo, de TODAS las sociedades (ZCL_ARBA_RET_SAL_EXPORT). Excluye los CUIT ya presentes: sin duplicados.
        " #33749 H3d - Salta y Entre Rios: conservan titulares del tipo de TODAS las sociedades.
        " Excluye los CUIT ya presentes; reutiliza ZCL_ARBA_RET_SAL_EXPORT sin modificar esa clase.
        " IF lv_prov = zcl_arba_ret_sal_param=>c_provincia.  " ORIGINAL
        IF lv_prov = zcl_arba_ret_sal_param=>c_provincia
           OR lv_prov = zcl_arba_ret_er_param=>c_provincia.
          DATA lt_keep_sal TYPE zcl_arba_ret_exporter=>ty_rows.
          DATA lv_sc_sal   TYPE i.
          CLEAR: lt_keep_sal, lv_sc_sal.
          NEW zcl_arba_ret_sal_export( )->keepers( EXPORTING iv_sociedad = lv_soc
                                                             iv_tipo     = CONV #( lv_tipo_pad )
                                                             it_rows     = lt_rows
                                                   IMPORTING et_rows     = lt_keep_sal
                                                             ev_sin_cuit = lv_sc_sal ).
          APPEND LINES OF lt_keep_sal TO lt_rows.
          APPEND VALUE #( %tky = k-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-information
                                                        text     = |Exportado: { lines( lt_log ) } del padrón + { lines( lt_keep_sal ) } conservados| ) )
                 TO lt_rep_exp.
          IF lv_sc_sal > 0.
            APPEND VALUE #( %tky = k-%tky
                            %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                          text     = |Atencion: { lv_sc_sal } titulares sin CUIT| ) )
                   TO lt_rep_exp.
          ENDIF.
        ENDIF.

        " Sin cambios de codigo ni bajas por ausencia: no se genera el .zip (ver lv_msg_sin_cambios).
        DATA lv_cambio TYPE abap_boolean.
        CLEAR lv_cambio.
        LOOP AT lt_log INTO DATA(ls_cam).
          IF es_cambio_std( iv_estado  = ls_cam-estado iv_caso = ls_cam-caso
                            iv_ind_ant = ls_cam-indicador_anterior iv_ind_nue = ls_cam-indicador_nuevo ) = abap_true.
            lv_cambio = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_cambio = abap_false
           AND hay_bajas_por_ausencia( iv_sociedad  = lv_soc
                                       iv_tipo      = CONV #( lv_tipo_pad )
                                       " #33749 H3f - ORIGINAL (se conserva comentado):
                                       " iv_todas_soc = xsdbool( lv_prov = zcl_arba_ret_sal_param=>c_provincia )
                                       " #33749 H3f - Entre Rios considera titulares de todas las sociedades.
                                       iv_todas_soc = xsdbool( lv_prov = zcl_arba_ret_sal_param=>c_provincia
                                                             OR lv_prov = zcl_arba_ret_er_param=>c_provincia )
                                       it_rows      = lt_rows ) = abap_false.
          APPEND VALUE #( %tky = k-%tky ) TO failed-ejecucion.
          APPEND msg_texto( iv_severity = if_abap_behv_message=>severity-error iv_texto = lv_msg_sin_cambios )
                 TO reported-%other.
          CONTINUE.
        ENDIF.
        APPEND LINES OF lt_rep_exp TO reported-ejecucion.

        " Tucuman: el .txt y el .zip llevan el tipo (Redmine 33748, 15/10: la estandar acepta el archivo con
        " cualquier tipo sin avisar; cargado con TN, el archivo del 24 proponia TN para todos sus titulares).
        DATA(lv_entry) = COND string( WHEN lv_prov = 'TUC' THEN |Padron_Tucuman_Tipo{ lv_tipo_pad }_{ lv_fstamp }| ELSE lv_fname ).
        IF lv_prov = 'TUC'.
          lv_expname   = |{ lv_entry }.zip|.
          lv_exp_tipos = lv_tipo_pad.
        ENDIF.
        lv_zip = lo_exporter->build_zip( iv_txt       = lo_exporter->build_txt( it_rows = lt_rows iv_provincia = lv_prov )
                                         iv_entryname = |{ lv_entry }.txt| ).
      ENDIF.

      IF lv_prov = 'TUC'.
        " Mensajes para el usuario final (Ivan 19/10): que digan que hacer, sin jerga y sin el ID tecnico de
        " la corrida (van sin vincular a la instancia).
        IF lv_exp_tipos IS NOT INITIAL.
          APPEND msg_texto(
                   iv_severity = if_abap_behv_message=>severity-information
                   iv_texto    = COND #( WHEN lv_exp_tipos CS ' y '
                                      THEN |Se generaron 2 archivos (Tipo { lv_exp_tipos }). Cárguelos por separado en Actualizar Códigos y Partidas, cada uno con su tipo.|
                                      ELSE |Archivo listo. Cárguelo en Actualizar Códigos y Partidas con el Tipo de retención { lv_exp_tipos }.| ) )
                 TO reported-%other.
        ENDIF.
        IF lv_exp_tipos IS NOT INITIAL AND lv_bajas_pad > 0.
          APPEND msg_texto(
                   iv_severity = if_abap_behv_message=>severity-warning
                   iv_texto    = |El archivo del Tipo { lv_tipo_pad } da de baja el tipo a { lv_bajas_pad } proveedores que no vienen en el padrón. Revíselos en la vista previa antes de actualizar.| )
                 TO reported-%other.
        ENDIF.
        IF lv_exp_tipos IS NOT INITIAL AND lv_tipos_sin IS NOT INITIAL.
          APPEND msg_texto(
                   iv_severity = if_abap_behv_message=>severity-information
                   iv_texto    = |El Tipo { lv_tipos_sin } no tiene registros para actualizar: no se generó su archivo.| )
                 TO reported-%other.
        ENDIF.
        IF lv_sincuit_t > 0.
          APPEND msg_texto(
                   iv_severity = if_abap_behv_message=>severity-warning
                   iv_texto    = |Atención: { lv_sincuit_t } proveedores con el tipo no tienen CUIT cargado; al cargar el archivo se les quitaría el tipo.| )
                 TO reported-%other.
        ENDIF.
      ENDIF.
      APPEND VALUE #( %tky           = k-%tky
                      ExportContent  = lv_zip
                      ExportMime     = 'application/zip'
                      ExportFilename = lv_expname ) TO lt_upd.
    ENDLOOP.

    " Escritura de los campos de export (readonly -> IN LOCAL MODE, valido en el handler).
    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FIELDS ( ExportContent ExportMime ExportFilename )
        WITH lt_upd
      REPORTED DATA(lr).

    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_res).
    result = VALUE #( FOR l IN lt_res ( %tky = l-%tky %param = CORRESPONDING #( l ) ) ).
  ENDMETHOD.



  METHOD keepers_para_export.
    CLEAR: et_rows, ev_conservados, ev_sin_cuit.

    DATA(lo_bp)  = NEW zcl_arba_ret_bp_updater( ).
    DATA(lo_det) = NEW zcl_arba_ret_determinador( ).
    lo_bp->preparar( iv_sociedad = iv_sociedad iv_tipo_ret = iv_tipo ).

    " Cache codigo -> alicuota (pocos codigos por tipo; evita recomputar por titular).
    TYPES: BEGIN OF ty_alic_c,
             cod  TYPE zcl_arba_ret_determinador=>ty_wht_code,
             alic TYPE zcl_arba_ret_exporter=>ty_alicuota,
           END OF ty_alic_c.
    DATA lt_alic TYPE HASHED TABLE OF ty_alic_c WITH UNIQUE KEY cod.

    LOOP AT lo_bp->leer_titulares_tipo( iv_sociedad = iv_sociedad iv_tipo = iv_tipo ) INTO DATA(ls_h).
      " Titular sin CUIT AR1A: no se puede exportar -> la estandar lo borraria. Se cuenta para advertir.
      IF ls_h-cuit IS INITIAL.
        ev_sin_cuit = ev_sin_cuit + 1.
        CONTINUE.
      ENDIF.
      " Ya esta en el export (vino del archivo) o es un REG (Santa Fe: baja a proposito) -> no es keeper.
      IF line_exists( it_export_cuit[ table_line = ls_h-cuit ] )
      OR line_exists( it_reg_cuit[ table_line = ls_h-cuit ] ).
        CONTINUE.
      ENDIF.
      " Alicuota del codigo ACTUAL del titular (cache): deja la linea como no-op incluso sin la BAdI.
      READ TABLE lt_alic INTO DATA(ls_alic) WITH KEY cod = ls_h-indicador.
      IF sy-subrc <> 0.
        DATA lv_alic TYPE zcl_arba_ret_exporter=>ty_alicuota.
        DATA lv_est  TYPE c LENGTH 3.
        DATA lv_msg  TYPE string.
        CLEAR: lv_alic, lv_est, lv_msg.
        lo_det->obtener_alicuota_indicador(
          EXPORTING iv_tipo_ret  = iv_tipo
                    iv_indicador = ls_h-indicador
          IMPORTING ev_alicuota  = lv_alic
                    ev_estado    = lv_est
                    ev_mensaje   = lv_msg ).
        ls_alic = VALUE #( cod = ls_h-indicador alic = lv_alic ).
        INSERT ls_alic INTO TABLE lt_alic.
      ENDIF.
      " Keeper: CUIT + alicuota actual, resto vacio. La BAdI, al no hallar el CUIT en el mapa de la
      " corrida, devuelve el codigo actual -> la estandar lo deja sin cambio (no lo borra).
      APPEND VALUE #( cuit = ls_h-cuit alicuota = ls_alic-alic ) TO et_rows.
      ev_conservados = ev_conservados + 1.
    ENDLOOP.
  ENDMETHOD.

  METHOD keepers_tuc.
    " Titulares del tipo en todas las sociedades (verificado en KMZ el 08/10: corriendo la estandar para la
    " 3110 proponia borrar a Seidor, titular del 24 en la 01AR). Cada uno va una sola vez, con la alicuota de
    " su codigo actual: la BAdI, al no hallar el CUIT en la corrida, le deja el codigo actual (sin cambio).
    CLEAR: et_rows, ev_conservados, ev_sin_cuit, ev_bajas.
    DATA(lo_bp)  = NEW zcl_arba_ret_bp_updater( ).
    DATA(lo_det) = NEW zcl_arba_ret_determinador( ).
    lo_bp->preparar( iv_sociedad = iv_sociedad iv_tipo_ret = CONV #( iv_tipo ) ).

    SELECT DISTINCT companycode FROM i_supplierwithholdingtax
      WHERE withholdingtaxtype = @iv_tipo
      INTO TABLE @DATA(lt_soc).

    DATA(lv_por_soc) = xsdbool( it_cuit_tipo IS SUPPLIED ).
    " Candidatos a baja (R2). Se cuentan al final: si el mismo CUIT se conserva por otra sociedad, va en el
    " archivo y la estandar no le saca el tipo.
    DATA lt_baja TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_cuit WITH UNIQUE KEY table_line.

    TYPES: BEGIN OF ty_alic_c,
             cod  TYPE zcl_arba_ret_determinador=>ty_wht_code,
             alic TYPE zcl_arba_ret_exporter=>ty_alicuota,
           END OF ty_alic_c.
    DATA lt_alic   TYPE HASHED TABLE OF ty_alic_c WITH UNIQUE KEY cod.
    DATA lt_vistos TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_cuit WITH UNIQUE KEY table_line.

    LOOP AT lt_soc INTO DATA(ls_soc).
      LOOP AT lo_bp->leer_titulares_tipo( iv_sociedad = ls_soc-companycode iv_tipo = CONV #( iv_tipo ) ) INTO DATA(ls_h).
        IF ls_h-cuit IS INITIAL.
          ev_sin_cuit = ev_sin_cuit + 1.
          CONTINUE.
        ENDIF.
        IF line_exists( lt_vistos[ table_line = ls_h-cuit ] ).
          CONTINUE.
        ENDIF.
        IF lv_por_soc = abap_false OR ls_soc-companycode = iv_sociedad.
          " Sociedad de la corrida: va en el archivo (este u otro tipo) -> no es keeper. Si va con el otro tipo,
          " pierde este (se cuenta para el aviso).
          IF line_exists( it_export_cuit[ table_line = ls_h-cuit ] ).
            IF lv_por_soc = abap_true AND NOT line_exists( it_cuit_tipo[ table_line = ls_h-cuit ] ).
              INSERT ls_h-cuit INTO TABLE lt_baja.
            ENDIF.
            CONTINUE.
          ENDIF.
          " Tipo de padron sin "Solo Padron": el que no viene en el archivo pierde el tipo (nota #57). Fuera
          " del filtro Desde/Hasta no se toca nada.
          IF iv_bajas_padron = abap_true
             AND NOT line_exists( it_cuit_archivo[ table_line = ls_h-cuit ] )
             AND NOT line_exists( it_proteger[ table_line = ls_h-supplier ] )
             AND NOT ( iv_prov_desde IS NOT INITIAL AND ls_h-supplier < iv_prov_desde )
             AND NOT ( iv_prov_hasta IS NOT INITIAL AND ls_h-supplier > iv_prov_hasta ).
            INSERT ls_h-cuit INTO TABLE lt_baja.
            CONTINUE.
          ENDIF.
        ELSEIF line_exists( it_cuit_tipo[ table_line = ls_h-cuit ] ).
          " Otra sociedad: ya va en el archivo de este tipo.
          CONTINUE.
        ENDIF.
        INSERT ls_h-cuit INTO TABLE lt_vistos.
        READ TABLE lt_alic INTO DATA(ls_alic) WITH KEY cod = ls_h-indicador.
        IF sy-subrc <> 0.
          DATA lv_alic TYPE zcl_arba_ret_exporter=>ty_alicuota.
          DATA lv_est  TYPE c LENGTH 3.
          DATA lv_msg  TYPE string.
          CLEAR: lv_alic, lv_est, lv_msg.
          lo_det->obtener_alicuota_indicador(
            EXPORTING iv_tipo_ret  = CONV #( iv_tipo )
                      iv_indicador = ls_h-indicador
            IMPORTING ev_alicuota  = lv_alic
                      ev_estado    = lv_est
                      ev_mensaje   = lv_msg ).
          ls_alic = VALUE #( cod = ls_h-indicador alic = lv_alic ).
          INSERT ls_alic INTO TABLE lt_alic.
        ENDIF.
        APPEND VALUE #( cuit = ls_h-cuit alicuota = ls_alic-alic ) TO et_rows.
        ev_conservados = ev_conservados + 1.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_baja INTO DATA(lv_cuit_baja).
      IF NOT line_exists( lt_vistos[ table_line = lv_cuit_baja ] ).
        ev_bajas = ev_bajas + 1.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD msg_texto.
    " Cada variable lleva hasta 50 caracteres. El corte nunca cae junto a un espacio (al armar el mensaje
    " los espacios de borde de una variable se pueden perder y las palabras quedarian pegadas).
    TYPES ty_v TYPE c LENGTH 50.
    DATA lt_v   TYPE STANDARD TABLE OF ty_v WITH EMPTY KEY.
    DATA lv_off TYPE i.
    DATA(lv_len) = strlen( iv_texto ).
    WHILE lv_off < lv_len AND lines( lt_v ) < 4.
      DATA(lv_n) = nmin( val1 = 50 val2 = lv_len - lv_off ).
      WHILE lv_n > 1 AND lv_off + lv_n < lv_len
        AND (    substring( val = iv_texto off = lv_off + lv_n - 1 len = 1 ) = ` `
              OR substring( val = iv_texto off = lv_off + lv_n     len = 1 ) = ` ` ).
        lv_n = lv_n - 1.
      ENDWHILE.
      APPEND CONV ty_v( substring( val = iv_texto off = lv_off len = lv_n ) ) TO lt_v.
      lv_off = lv_off + lv_n.
    ENDWHILE.
    WHILE lines( lt_v ) < 4.
      APPEND INITIAL LINE TO lt_v.
    ENDWHILE.
    ro_msg = new_message( id       = 'ZARBA_RET_TUC'
                          number   = '000'
                          severity = iv_severity
                          v1       = lt_v[ 1 ]
                          v2       = lt_v[ 2 ]
                          v3       = lt_v[ 3 ]
                          v4       = lt_v[ 4 ] ).
  ENDMETHOD.

  METHOD export_requiere_padron.
    CASE iv_prov.
      WHEN 'TUC'.
        rv_req = abap_true.
      WHEN OTHERS.
        rv_req = abap_false.
    ENDCASE.
  ENDMETHOD.

  METHOD es_cambio_std.
    rv_cam = xsdbool( iv_estado = 'ACT' AND iv_caso <> '1' AND iv_caso <> '4' AND iv_ind_nue <> iv_ind_ant ).
  ENDMETHOD.

  METHOD hay_bajas_por_ausencia.
    DATA lt_cuit TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_cuit WITH UNIQUE KEY table_line.
    LOOP AT it_rows INTO DATA(ls_r).
      INSERT ls_r-cuit INTO TABLE lt_cuit.
    ENDLOOP.

    DATA lt_soc TYPE STANDARD TABLE OF bukrs WITH EMPTY KEY.
    IF iv_todas_soc = abap_true.
      SELECT DISTINCT companycode FROM i_supplierwithholdingtax
        WHERE withholdingtaxtype = @iv_tipo
        INTO TABLE @lt_soc.
    ELSE.
      lt_soc = VALUE #( ( iv_sociedad ) ).
    ENDIF.

    DATA(lo_bp) = NEW zcl_arba_ret_bp_updater( ).
    lo_bp->preparar( iv_sociedad = iv_sociedad iv_tipo_ret = CONV #( iv_tipo ) ).
    LOOP AT lt_soc INTO DATA(lv_soc).
      LOOP AT lo_bp->leer_titulares_tipo( iv_sociedad = lv_soc iv_tipo = CONV #( iv_tipo ) ) INTO DATA(ls_h).
        " Un titular sin CUIT nunca esta en el archivo: tambien lo borra la estandar.
        IF ls_h-cuit IS INITIAL OR NOT line_exists( lt_cuit[ table_line = ls_h-cuit ] ).
          rv_hay = abap_true.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
"""""""""""""""""""""""""
*  METHOD aplicarexenciones.
*    " Aplica por API (A_SupplierWithHoldingTax) los casos de Coeficientes que la app estandar no hace:
*    " destilde de sujeto (Excluido) y exencion (coef < 1). Lee el log de la ejecucion. Correr DESPUES
*    " de "Actualizar Codigos y Partidas". No modifica datos del propio BO; el detalle vuelve como mensaje.
*    LOOP AT keys INTO DATA(k).
*      DATA(ls_res) = NEW zcl_arba_ret_tuc_exencion( )->aplicar( iv_ejecucion_uuid = k-EjecucionUUID ).
*      " Sin vincular a la instancia: el usuario ve el resultado sin el ID tecnico de la corrida.
*      APPEND msg_texto(
*               iv_severity = COND #( WHEN ls_res-errores > 0 THEN if_abap_behv_message=>severity-warning
*                                     ELSE if_abap_behv_message=>severity-information )
*               iv_texto    = ls_res-mensaje )
*             TO reported-%other.
*    ENDLOOP.
*
*    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
*      ENTITY Ejecucion ALL FIELDS WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_res).
*    result = VALUE #( FOR l IN lt_res ( %tky = l-%tky %param = CORRESPONDING #( l ) ) ).
*  ENDMETHOD.
METHOD aplicarexenciones.

  " Aplica por API lo que la app estandar no hace.
  " Ejecutar DESPUES de Actualizar Codigos y Partidas.

  READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
    ENTITY Ejecucion FIELDS ( Provincia )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_prov).

  LOOP AT keys INTO DATA(k).

    DATA(lv_prov) = VALUE #(
      lt_prov[ %tky = k-%tky ]-Provincia OPTIONAL ).

    DATA lv_msg TYPE string.
    DATA lv_err TYPE i.

    CLEAR: lv_msg, lv_err.

    IF lv_prov = zcl_arba_ret_er_param=>c_provincia.

      DATA(ls_er) = NEW zcl_arba_ret_er_sujeto( )->aplicar(
        iv_ejecucion_uuid = k-EjecucionUUID ).

      lv_msg = ls_er-mensaje.
      lv_err = ls_er-errores.

    ELSE.

      DATA(ls_res) = NEW zcl_arba_ret_tuc_exencion( )->aplicar(
        iv_ejecucion_uuid = k-EjecucionUUID ).

      lv_msg = ls_res-mensaje.
      lv_err = ls_res-errores.

    ENDIF.

    APPEND msg_texto(
      iv_severity = COND #(
        WHEN lv_err > 0
          THEN if_abap_behv_message=>severity-warning
        ELSE if_abap_behv_message=>severity-information )
      iv_texto = lv_msg )
      TO reported-%other.

  ENDLOOP.

  READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
    ENTITY Ejecucion ALL FIELDS
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_res).

  result = VALUE #(
    FOR l IN lt_res
    ( %tky = l-%tky
      %param = CORRESPONDING #( l ) ) ).

ENDMETHOD.
"""""""""""""""""
  METHOD validarparametros.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( Provincia Sociedad TipoRetencion IndicadorFueraPadron ActualizarSoloPadron
                                IndicadorFueraPadronNoSal )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ejec).

    LOOP AT lt_ejec INTO DATA(ls).
      APPEND VALUE #( %tky = ls-%tky %state_area = 'VAL_PARAM' ) TO reported-ejecucion.
      error_parametros( EXPORTING iv_provincia = ls-Provincia
                                  iv_sociedad  = ls-Sociedad
                                  iv_tipo      = ls-TipoRetencion
                                  iv_indicador = ls-IndicadorFueraPadron
                                  iv_solo      = ls-ActualizarSoloPadron
                                  iv_ind_no_sal = ls-IndicadorFueraPadronNoSal
                        IMPORTING ev_msg       = DATA(lv_msg)
                                  ev_campo     = DATA(lv_campo) ).
      IF lv_msg IS INITIAL.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( %tky = ls-%tky ) TO failed-ejecucion.
      APPEND VALUE #( %tky        = ls-%tky
                      %state_area = 'VAL_PARAM'
                      %msg        = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                           text     = lv_msg )
                      %element-Provincia            = COND #( WHEN lv_campo = 'PROV' THEN if_abap_behv=>mk-on )
                      %element-Sociedad             = COND #( WHEN lv_campo = 'SOC'  THEN if_abap_behv=>mk-on )
                      %element-TipoRetencion        = COND #( WHEN lv_campo = 'TIPO' THEN if_abap_behv=>mk-on )
                      %element-IndicadorFueraPadron = COND #( WHEN lv_campo = 'IND'  THEN if_abap_behv=>mk-on )
                      %element-IndicadorFueraPadronNoSal = COND #( WHEN lv_campo = 'IND2' THEN if_abap_behv=>mk-on ) )
             TO reported-ejecucion.
    ENDLOOP.
  ENDMETHOD.

  METHOD error_parametros.
    CLEAR: ev_msg, ev_campo.
    IF iv_provincia IS INITIAL.
      ev_msg = 'Ingrese la Provincia'. ev_campo = 'PROV'. RETURN.
    ENDIF.
    " Padrones habilitados por cliente (17/10): tabla de customizing ZARBA_RET_PROV (Custom Business
    " Configurations). Provincia cargada con Activa vacia -> no habilitada. Sin fila -> habilitada (como antes).
    SELECT SINGLE activa FROM zarba_ret_prov WHERE provincia = @iv_provincia INTO @DATA(lv_activa).
    IF sy-subrc = 0 AND lv_activa = abap_false.
      ev_msg = |Padron { iv_provincia } no habilitado en este sistema|. ev_campo = 'PROV'. RETURN.
    ENDIF.
    IF iv_sociedad IS INITIAL.
      ev_msg = 'Ingrese la Sociedad'. ev_campo = 'SOC'. RETURN.
    ENDIF.
    IF iv_tipo IS INITIAL.
      ev_msg = 'Ingrese el Tipo de Retencion'. ev_campo = 'TIPO'. RETURN.
    ENDIF.
    " Tucuman (Ivan) tiene sus propios parametros (Tipo Ret. Fuera de Padron / Modo): no se valida aca.
    IF iv_provincia = 'TUC'.
      RETURN.
    ENDIF.
    IF iv_solo = abap_false AND iv_indicador IS INITIAL.
      ev_msg = 'Ingrese el Indicador Fuera de Padron'. ev_campo = 'IND'. RETURN.
    ENDIF.
    IF iv_indicador IS NOT INITIAL.
      DATA lv_est TYPE c LENGTH 3.
      NEW zcl_arba_ret_determinador( )->obtener_alicuota_indicador(
        EXPORTING iv_tipo_ret  = iv_tipo
                  iv_indicador = iv_indicador
        IMPORTING ev_estado    = lv_est ).
      IF lv_est IS NOT INITIAL.
        ev_msg = |Indicador { iv_indicador } no es del tipo { iv_tipo }|. ev_campo = 'IND'. RETURN.
      ENDIF.
    ENDIF.
    " Salta: segundo indicador fuera de padron (otra region) y condiciones configuradas para el tipo.
    IF iv_provincia = zcl_arba_ret_sal_param=>c_provincia.
      zcl_arba_ret_sal_param=>error_parametros( EXPORTING iv_tipo = iv_tipo iv_ind_no_sal = iv_ind_no_sal iv_solo = iv_solo
                                                IMPORTING ev_msg = ev_msg ev_campo = ev_campo ).
    ENDIF.
    " Entre Rios: validar alicuotas CM y CL
IF iv_provincia = zcl_arba_ret_er_param=>c_provincia
   AND ev_msg IS INITIAL.

  zcl_arba_ret_er_param=>error_parametros(
    EXPORTING iv_tipo  = iv_tipo
    IMPORTING ev_msg   = ev_msg
              ev_campo = ev_campo ).

ENDIF.
  ENDMETHOD.

  METHOD motivo_no_lanzable.
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( ModoSimulacion EstadoEjecucion LastChangedAt Provincia Sociedad TipoRetencion
                                IndicadorFueraPadron ActualizarSoloPadron Archivo IndicadorFueraPadronNoSal
                                TipoRetFueraPadron )
        WITH VALUE #( ( EjecucionUUID = iv_uuid ) )   " instancia ACTIVA (la que lee el job)
      RESULT DATA(lt_ejec).
    IF lt_ejec IS INITIAL.
      rv_msg = 'Grabe la ejecucion antes de procesarla'. RETURN.
    ENDIF.
    DATA(ls) = lt_ejec[ 1 ].

    " Una ejecucion ya procesada en REAL no se vuelve a correr: el job reemplaza el log (la BAdI y el
    " export perderian la corrida real) y el archivo ya no se conserva. Para reprocesar: nueva ejecucion.
    IF ls-ModoSimulacion = abap_false
       AND ( ls-EstadoEjecucion = 'OK' OR ls-EstadoEjecucion = 'OK_CON_ERRORES' ).
      rv_msg = 'Ya procesada en real: cree una nueva ejecucion'. RETURN.
    ENDIF.

    " Proceso en curso: un 2do job sobre la misma ejecucion pisaba el estado (el 1ro borra el archivo al
    " terminar -> el 2do daba FALLIDA). Pasadas 2 horas sin cambios se asume colgado y se permite relanzar.
    IF ls-EstadoEjecucion = 'EN_PROCESO'.
      DATA lv_now TYPE timestampl.
      GET TIME STAMP FIELD lv_now.
      IF cl_abap_tstmp=>subtract( tstmp1 = lv_now tstmp2 = ls-LastChangedAt ) < 7200.
        rv_msg = 'Proceso en curso: espere y actualice'. RETURN.
      ENDIF.
    ENDIF.

    error_parametros( EXPORTING iv_provincia = ls-Provincia
                                iv_sociedad  = ls-Sociedad
                                iv_tipo      = ls-TipoRetencion
                                iv_indicador = ls-IndicadorFueraPadron
                                iv_solo      = ls-ActualizarSoloPadron
                                iv_ind_no_sal = ls-IndicadorFueraPadronNoSal
                      IMPORTING ev_msg       = rv_msg ).
    IF rv_msg IS NOT INITIAL.
      RETURN.
    ENDIF.

    " Tucuman: el tipo de fuera de padron tiene que ser otro (ver validarparametrostuc; nota #57).
    IF ls-Provincia = 'TUC' AND ls-TipoRetFueraPadron IS NOT INITIAL AND ls-TipoRetFueraPadron = ls-TipoRetencion.
      rv_msg = 'Tipo Ret. Fuera de Padron igual al Tipo de Retencion'. RETURN.
    ENDIF.

    IF xstrlen( ls-Archivo ) = 0.
      rv_msg = 'Adjunte el archivo del padron'.
    ENDIF.
  ENDMETHOD.

  METHOD lanzar_job.
    " 1) Leer el ID de ejecucion (parametro del job)
    READ ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion FIELDS ( IdEjecucion )
        WITH VALUE #( ( EjecucionUUID = iv_uuid ) )
      RESULT DATA(lt_ejec).
    IF lt_ejec IS INITIAL.
      RETURN.
    ENDIF.

    " 2) Guardar la intencion en el buffer (se agenda en el saver, fase de save)
    IF NOT line_exists( gt_pending[ uuid = iv_uuid ] ).
      APPEND VALUE #( uuid = iv_uuid id_ejec = lt_ejec[ 1 ]-IdEjecucion simular = iv_simular ) TO gt_pending.
    ENDIF.

    " 3) Marcar EN_PROCESO (readonly -> requiere IN LOCAL MODE, valido en el handler)
    MODIFY ENTITIES OF zi_arba_ret_ejecucion IN LOCAL MODE
      ENTITY Ejecucion
        UPDATE FIELDS ( EstadoEjecucion )
        WITH VALUE #( ( EjecucionUUID = iv_uuid EstadoEjecucion = 'EN_PROCESO' ) )
      REPORTED DATA(lr).
  ENDMETHOD.

ENDCLASS.


"======================================================================
" Saver: agenda los Application Jobs en la FASE DE SAVE (unica fase donde
" cl_apj_rt_api=>schedule_job es legal, por hacer MODIFY + COMMIT).
"======================================================================
CLASS lsc_ejecucion DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.

CLASS lsc_ejecucion IMPLEMENTATION.

  METHOD save_modified.
    LOOP AT lhc_ejecucion=>gt_pending INTO DATA(ls_pend).
      DATA lt_param TYPE cl_apj_rt_api=>tt_job_parameter_value.
      lt_param = VALUE #(
        ( name = 'ID_EJEC' t_value = VALUE #( ( sign = 'I' option = 'EQ' low = ls_pend-id_ejec ) ) )
        ( name = 'SIMULAR' t_value = VALUE #( ( sign = 'I' option = 'EQ'
                                                low = COND #( WHEN ls_pend-simular = abap_true THEN 'X' ELSE '' ) ) ) ) ).

      DATA(ls_start) = VALUE cl_apj_rt_api=>ty_start_info( start_immediately = abap_true ).

      TRY.
          cl_apj_rt_api=>schedule_job(
            EXPORTING iv_job_template_name   = 'ZARBA_RET_PROC'
                      iv_job_text            = 'Procesamiento padron ARBA Retenciones'
                      is_start_info          = ls_start
                      it_job_parameter_value = lt_param
            IMPORTING ev_jobname             = DATA(lv_jobname)
                      ev_jobcount            = DATA(lv_jobcount) ).
        CATCH cx_apj_rt INTO DATA(lx).
          " No se pudo agendar (p. ej. plantilla ZARBA_RET_PROC inexistente): no hay nada procesando ->
          " vuelve a PENDIENTE (si no, quedaba EN_PROCESO para siempre) y se avisa en pantalla.
          UPDATE zarba_ret_ejec SET estado_ejecucion = 'PENDIENTE'
            WHERE ejecucion_uuid = @ls_pend-uuid AND estado_ejecucion = 'EN_PROCESO'.
          APPEND VALUE #( EjecucionUUID = ls_pend-uuid
                          %msg = new_message_with_text(
                                   severity = if_abap_behv_message=>severity-error
                                   text     = 'No se pudo lanzar el proceso: reintente' ) )
                 TO reported-ejecucion.
      ENDTRY.
    ENDLOOP.

    CLEAR lhc_ejecucion=>gt_pending.
  ENDMETHOD.

ENDCLASS.




