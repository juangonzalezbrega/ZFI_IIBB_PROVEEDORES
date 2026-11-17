"! Motor de procesamiento del padron IIBB Tucuman (Acreditan y Coeficientes). Autocontenido:
"! se lo invoca desde el Application Job cuando la ejecucion es de provincia 'TUC'. Determina el
"! indicador y persiste el log; el apply (maestro + partidas) lo hace la app estandar + BAdI, como
"! el resto del proyecto. Reusa el gateway de proveedores (ZCL_ARBA_RET_BP_UPDATER) y los tipos de
"! log/KPI de ZCL_ARBA_RET_PROC_APP para escribir en las mismas tablas.
"!
"! Limitaciones conocidas (por el mecanismo app estandar + BAdI, solo aplica el CODIGO):
"!   - Coeficientes: exencion (coef<1), ajuste de base imponible (coef=1) y destildar sujeto
"!     (excluido) se DETERMINAN y quedan logueados como pendientes (requieren API).
"! Fuera de padron (EF caso 6) y baja del tipo No Inscriptos (caso 7): con "Actualizar Solo Padron"
"! desactivado, se determinan sobre el universo por REGION 14 (domicilio) + los titulares TN actuales,
"! y se aplican por la app estandar del tipo TN (el snapshot exportado da de alta/baja el tipo por
"! presencia/ausencia). La lectura de region esta blindada: si no esta autorizada, no se generan altas
"! por region (solo se conservan los TN actuales) y queda logueado; nunca produce un snapshot vacio.
CLASS zcl_arba_ret_tuc_proc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_parser       TYPE REF TO zcl_arba_ret_tuc_parser       OPTIONAL
                io_validator    TYPE REF TO zcl_arba_ret_tuc_validator    OPTIONAL
                io_determinador TYPE REF TO zcl_arba_ret_tuc_determinador OPTIONAL
                io_bp_updater   TYPE REF TO zcl_arba_ret_bp_updater       OPTIONAL.

    "! Punto de entrada desde el job: procesa la ejecucion completa.
    METHODS procesar
      IMPORTING is_ejec    TYPE zarba_ret_ejec
                iv_simular TYPE abap_boolean.

  PRIVATE SECTION.
    DATA mo_parser       TYPE REF TO zcl_arba_ret_tuc_parser.
    DATA mo_validator    TYPE REF TO zcl_arba_ret_tuc_validator.
    DATA mo_determinador TYPE REF TO zcl_arba_ret_tuc_determinador.
    DATA mo_bp           TYPE REF TO zcl_arba_ret_bp_updater.

    "! Region (domicilio) de Tucuman para el caso 6 (fuera de padron). EF: REGION 14. Confirmar el
    "! codigo real contra el tenant del cliente (GZ3): es dato de direccion del BP, custom por tenant.
    CONSTANTS c_region_tuc TYPE c LENGTH 3 VALUE '14'.

    METHODS procesar_registro
      IMPORTING is_ejec   TYPE zarba_ret_ejec
                is_record TYPE zcl_arba_ret_tuc_parser=>ty_record
                is_val    TYPE zcl_arba_ret_tuc_validator=>ty_val_result
      CHANGING  ct_log    TYPE zcl_arba_ret_proc_app=>ty_log_tt
                cs_kpi    TYPE zcl_arba_ret_proc_app=>ty_kpi.

    "! Fuera de padron (EF caso 6) + baja del tipo No Inscriptos (caso 7). Solo Acreditan con "Actualizar
    "! Solo Padron" desactivado: a los proveedores de la sociedad con domicilio en Tucuman (region 14) cuyo
    "! CUIT NO esta en el archivo les asigna el tipo TN; los titulares TN actuales se conservan (keepers)
    "! salvo que ahora esten en el padron (ahi se los excluye del snapshot -> la app estandar les da de
    "! baja el TN). Blindaje: si la region no es legible/autorizada, no genera altas por region.
    METHODS procesar_fuera_padron
      IMPORTING is_ejec        TYPE zarba_ret_ejec
                it_cuit_padron TYPE zcl_arba_ret_proc_app=>ty_cuit_set
      CHANGING  ct_log         TYPE zcl_arba_ret_proc_app=>ty_log_tt
                cs_kpi         TYPE zcl_arba_ret_proc_app=>ty_kpi.

    "! Baja del tipo de fuera de padron (TN) a los proveedores que vienen en el padron (Redmine 33748, nota
    "! #57), con y sin "Actualizar Solo Padron": filas 'BAJ' que Ejecutar aplica por API
    "! (ZCL_ARBA_RET_ALTA->aplicar_bajas). Solo a quienes quedan con el tipo de padron (fila SCB, ACT o PCF
    "! con indicador actual): sacarle el TN a un rechazado lo dejaria sin ningun tipo.
    METHODS procesar_bajas
      IMPORTING is_ejec TYPE zarba_ret_ejec
      CHANGING  ct_log  TYPE zcl_arba_ret_proc_app=>ty_log_tt
                cs_kpi  TYPE zcl_arba_ret_proc_app=>ty_kpi.

    METHODS base_log_row
      IMPORTING is_record     TYPE zcl_arba_ret_tuc_parser=>ty_record
      RETURNING VALUE(rs_row) TYPE zcl_arba_ret_proc_app=>ty_log_row.

    METHODS persistir_log
      IMPORTING iv_uuid TYPE sysuuid_x16
                it_log  TYPE zcl_arba_ret_proc_app=>ty_log_tt.

    METHODS finalizar
      IMPORTING iv_uuid    TYPE sysuuid_x16
                iv_estado  TYPE zcl_arba_ret_proc_app=>ty_estado_ejec
                is_kpi     TYPE zcl_arba_ret_proc_app=>ty_kpi
                iv_simular TYPE abap_boolean
                iv_archivo TYPE xstring.
ENDCLASS.



CLASS ZCL_ARBA_RET_TUC_PROC IMPLEMENTATION.


  METHOD constructor.
    mo_parser       = COND #( WHEN io_parser IS BOUND THEN io_parser ELSE NEW zcl_arba_ret_tuc_parser( ) ).
    mo_validator    = COND #( WHEN io_validator IS BOUND THEN io_validator ELSE NEW zcl_arba_ret_tuc_validator( ) ).
    mo_determinador = COND #( WHEN io_determinador IS BOUND THEN io_determinador ELSE NEW zcl_arba_ret_tuc_determinador( ) ).
    mo_bp           = COND #( WHEN io_bp_updater IS BOUND THEN io_bp_updater ELSE NEW zcl_arba_ret_bp_updater( ) ).
  ENDMETHOD.


  METHOD procesar.
    " Modo de archivo: 'C' Coeficientes ; 'A' Acreditan (default).
    mo_parser->set_modo( COND #( WHEN is_ejec-modo_archivo = 'C'
                                 THEN zcl_arba_ret_tuc_parser=>c_modo-coeficientes
                                 ELSE zcl_arba_ret_tuc_parser=>c_modo-acreditan ) ).

    " Archivo vacio -> FALLIDA
    IF xstrlen( is_ejec-archivo ) = 0.
      finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                 iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
      RETURN.
    ENDIF.

    " Padron Tucuman en ISO-8859-1 (Latin-1), como ARBA/CABA (evita dump por acentos/Ñ).
    DATA(lv_text) = cl_abap_conv_codepage=>create_in( codepage = 'ISO-8859-1' )->convert( source = is_ejec-archivo ).

    DATA lt_rec TYPE zcl_arba_ret_tuc_parser=>ty_record_tt.
    mo_parser->parse_file( EXPORTING iv_content = lv_text IMPORTING et_records = lt_rec ).

    DATA ls_kpi TYPE zcl_arba_ret_proc_app=>ty_kpi.
    ls_kpi-leidos = lines( lt_rec ).
    IF ls_kpi-leidos = 0.
      finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = 'FALLIDA' is_kpi = VALUE #( )
                 iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
      RETURN.
    ENDIF.

    " Precarga de proveedores + retencion actual del tipo de padron (24).
    mo_bp->preparar( iv_sociedad = is_ejec-sociedad iv_tipo_ret = is_ejec-tipo_retencion ).

    DATA lt_log TYPE zcl_arba_ret_proc_app=>ty_log_tt.
    LOOP AT lt_rec INTO DATA(ls_rec).
      procesar_registro(
        EXPORTING is_ejec   = is_ejec
                  is_record = ls_rec
                  is_val    = mo_validator->validate_record( ls_rec )
        CHANGING  ct_log    = lt_log
                  cs_kpi    = ls_kpi ).
    ENDLOOP.

    " Sincronizacion completa (fuera de padron, EF caso 6/7): a los proveedores con domicilio en
    " Tucuman (region 14) que no estan en el archivo se les asigna el tipo No Inscriptos (TN).
    " Solo con Acreditan: Coeficientes procesa unicamente los CUIT del archivo (en Modo C "Solo Padron"
    " queda grisado en pantalla, asi que su valor no decide).
    IF is_ejec-modo_archivo <> 'C' AND is_ejec-actualizar_solo_padron = abap_false.
      " CUIT que vienen en el archivo (EF: "si el CUIT esta en el Archivo"): se excluyen del universo TN,
      " aunque la linea haya sido rechazada o el proveedor haya quedado fuera del filtro.
      DATA lt_cuit_padron TYPE zcl_arba_ret_proc_app=>ty_cuit_set.
      LOOP AT lt_rec INTO DATA(ls_pr).
        INSERT ls_pr-cuit INTO TABLE lt_cuit_padron.   " ignora duplicados
      ENDLOOP.
      procesar_fuera_padron( EXPORTING is_ejec        = is_ejec
                                       it_cuit_padron = lt_cuit_padron
                             CHANGING  ct_log         = lt_log
                                       cs_kpi         = ls_kpi ).
    ENDIF.

    " Baja del tipo de fuera de padron a los que vienen en el padron (nota #57). Solo Acreditan.
    IF is_ejec-modo_archivo <> 'C'.
      procesar_bajas( EXPORTING is_ejec = is_ejec
                      CHANGING  ct_log  = lt_log
                                cs_kpi  = ls_kpi ).
    ENDIF.

    persistir_log( iv_uuid = is_ejec-ejecucion_uuid it_log = lt_log ).

    DATA(lv_estado) = COND zcl_arba_ret_proc_app=>ty_estado_ejec(
      WHEN ls_kpi-error_tecnico > 0 THEN 'OK_CON_ERRORES' ELSE 'OK' ).
    finalizar( iv_uuid = is_ejec-ejecucion_uuid iv_estado = lv_estado is_kpi = ls_kpi
               iv_simular = iv_simular iv_archivo = is_ejec-archivo ).
  ENDMETHOD.


  METHOD procesar_registro.
    DATA(ls_row) = base_log_row( is_record ).
    " Todas las filas del archivo apuntan al tipo de padron (24). El fuera de padron emite filas TN.
    ls_row-tipo_ret = is_ejec-tipo_retencion.

    " 1) Validacion
    IF is_val-es_valido = abap_false.
      ls_row-estado  = is_val-estado.
      ls_row-mensaje = is_val-mensaje.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-rechazados.
      RETURN.
    ENDIF.

    " 2) Matching de proveedor por CUIT
    DATA lt_sup TYPE zcl_arba_ret_bp_updater=>ty_supplier_tt.
    mo_bp->buscar_proveedor( EXPORTING iv_cuit = is_record-cuit IMPORTING et_suppliers = lt_sup ).
    IF lines( lt_sup ) = 0.
      ls_row-estado  = 'NOE'.
      ls_row-mensaje = 'CUIT sin proveedor en SAP'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-no_encontrados.
      RETURN.
    ELSEIF lines( lt_sup ) > 1.
      ls_row-estado  = 'DUP'.
      ls_row-mensaje = 'Rechazado: CUIT presente en mas de un proveedor en SAP'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-rechazados.
      RETURN.
    ENDIF.
    DATA(lv_sup) = lt_sup[ 1 ].
    ls_row-proveedor = lv_sup.

    " 3) Filtro opcional por rango de proveedor
    IF ( is_ejec-prov_desde IS NOT INITIAL AND lv_sup < is_ejec-prov_desde )
    OR ( is_ejec-prov_hasta IS NOT INITIAL AND lv_sup > is_ejec-prov_hasta ).
      ls_row-estado  = 'OMI'.
      ls_row-mensaje = 'Omitido: proveedor fuera del filtro'.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
      RETURN.
    ENDIF.

    " 4) Retencion actual del tipo de padron (24)
    DATA(ls_act) = mo_bp->leer_retencion_actual(
      iv_supplier = lv_sup iv_sociedad = is_ejec-sociedad iv_tipo_ret = is_ejec-tipo_retencion ).
    ls_row-indicador_anterior  = ls_act-indicador.
    ls_row-sujeto_ret_anterior = COND #( WHEN ls_act-es_sujeto = abap_true THEN 'X' ELSE '' ).
    ls_row-alicuota_nueva      = is_val-alicuota.   " informativo (porcentaje del archivo)

    " 5) Determinacion del indicador nuevo segun modo/caso
    DATA lv_ind          TYPE zcl_arba_ret_tuc_determinador=>ty_wht_code.
    DATA lv_sujeto_nuevo TYPE c LENGTH 1 VALUE 'X'.
    DATA lv_desc         TYPE string.
    DATA lv_est          TYPE c LENGTH 3.
    DATA lv_msg          TYPE string.

    IF is_record-modo = zcl_arba_ret_tuc_parser=>c_modo-coeficientes.
      " ---- Coeficientes (siempre rama CM) ----
      IF is_record-excluido = abap_true.
        " Excluido: destildar sujeto (no cambia el codigo). Aplicacion PENDIENTE (API).
        ls_row-caso             = 'X'.
        ls_row-indicador_nuevo  = ls_act-indicador.
        ls_row-sujeto_ret_nuevo = ''.
        ls_row-estado           = 'ACT'.
        ls_row-mensaje          = 'Excluido: destildar "sujeto a retencion" (aplicacion pendiente por API; la app estandar no lo hace)'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-actualizados.
        RETURN.
      ENDIF.

      IF is_val-coeficiente = 0.
        " Coeficiente 0 -> Indicador CM Coef. 0 (parametro de pantalla)
        lv_ind = is_ejec-indicador_cm_coef0.
        IF lv_ind IS INITIAL.
          ls_row-estado  = 'PCF'.
          ls_row-mensaje = 'Coeficiente 0 pero falta el parametro "Indicador CM Coef. 0"'.
          APPEND ls_row TO ct_log.
          ADD 1 TO cs_kpi-pendiente_config.
          RETURN.
        ENDIF.
        lv_desc = 'Coeficiente 0 -> Indicador CM Coef. 0 (parametro)'.
      ELSE.
        " Coeficiente <> 0 -> codigo CM por alicuota
        mo_determinador->determinar_indicador(
          EXPORTING iv_tipo_ret = is_ejec-tipo_retencion iv_conv_mult = abap_true iv_alicuota = is_val-alicuota
          IMPORTING ev_indicador = lv_ind ev_estado = lv_est ev_mensaje = lv_msg ).
        IF lv_est = 'PCF'.
          ls_row-estado  = 'PCF'.
          ls_row-mensaje = lv_msg.
          APPEND ls_row TO ct_log.
          ADD 1 TO cs_kpi-pendiente_config.
          RETURN.
        ENDIF.
        IF is_val-coeficiente < 1.
          " Tipo explicito con 2 decimales (Redmine 33748 nota #63): con DATA(...) inline el resultado
          " de la expresion quedaba sin decimales y 98,05 se grababa como 98,00.
          DATA lv_exencion TYPE p LENGTH 5 DECIMALS 2.
          lv_exencion = ( 1 - is_val-coeficiente ) * 100.
          " Exencion a aplicar por API (la app estandar solo pone el codigo). Se guarda en el log:
          " porcentaje = (1 - coef) * 100 y las fechas del periodo del padron, tomadas de la VIGENCIA
          " del archivo (AAAAMM): 1o al ultimo dia de ese mes.
          ls_row-exencion_pct = lv_exencion.
          IF is_record-vigencia CO '0123456789' AND strlen( is_record-vigencia ) = 6.
            DATA(lv_anio) = CONV i( is_record-vigencia(4) ).
            DATA(lv_mes)  = CONV i( is_record-vigencia+4(2) ).
            IF lv_mes BETWEEN 1 AND 12.
              ls_row-exencion_desde = CONV d( |{ is_record-vigencia }01| ).
              DATA(lv_mes_sig)  = lv_mes + 1.
              DATA(lv_anio_sig) = lv_anio.
              IF lv_mes_sig > 12.
                lv_mes_sig  = 1.
                lv_anio_sig = lv_anio + 1.
              ENDIF.
              ls_row-exencion_hasta = CONV d( |{ lv_anio_sig }{ lv_mes_sig WIDTH = 2 PAD = '0' ALIGN = RIGHT }01| ) - 1.
            ENDIF.
          ENDIF.
          lv_desc = |Coeficiente < 1 -> codigo CM por alicuota (via estandar) + EXENCION { lv_exencion }% del { ls_row-exencion_desde } al { ls_row-exencion_hasta } (se aplica con la accion Aplicar Exenciones)|.
        ELSE.
          lv_desc = 'Coeficiente 1 -> codigo CM por alicuota + ajuste de base imponible de partidas (pendiente por API)'.
        ENDIF.
      ENDIF.

    ELSE.
      " ---- Acreditan ----
      IF is_record-excluido = abap_true.
        " Excluido 'E' -> Indicador Exento CM (parametro de pantalla)
        lv_ind = is_ejec-indicador_exento_cm.
        IF lv_ind IS INITIAL.
          ls_row-estado  = 'PCF'.
          ls_row-mensaje = 'Excluido (E) pero falta el parametro "Ind. Ret. Exento CM"'.
          APPEND ls_row TO ct_log.
          ADD 1 TO cs_kpi-pendiente_config.
          RETURN.
        ENDIF.
        lv_desc = 'Excluido (E) -> Indicador Exento CM (parametro)'.
      ELSE.
        DATA(lv_cm) = xsdbool( is_record-tipo_contrib = 'CM' ).
        mo_determinador->determinar_indicador(
          EXPORTING iv_tipo_ret = is_ejec-tipo_retencion iv_conv_mult = lv_cm iv_alicuota = is_val-alicuota
          IMPORTING ev_indicador = lv_ind ev_estado = lv_est ev_mensaje = lv_msg ).
        IF lv_est = 'PCF'.
          ls_row-estado  = 'PCF'.
          ls_row-mensaje = lv_msg.
          APPEND ls_row TO ct_log.
          ADD 1 TO cs_kpi-pendiente_config.
          RETURN.
        ENDIF.
        lv_desc = |Determinado { is_record-tipo_contrib } por alicuota|.
      ENDIF.
    ENDIF.

    ls_row-indicador_nuevo  = lv_ind.
    ls_row-sujeto_ret_nuevo = lv_sujeto_nuevo.

    " 6) Clasificacion de caso y estado
    IF ls_act-existe = abap_false.
      ls_row-caso = '1'.   " alta
    ELSE.
      ls_row-caso = '2'.   " cambio
      IF ls_act-indicador = lv_ind AND ls_act-es_sujeto = abap_true.
        ls_row-estado  = 'SCB'.
        " Coeficientes coef < 1: el codigo no cambia pero la exencion se aplica igual (Aplicar Exenciones).
        ls_row-mensaje = COND #( WHEN ls_row-exencion_pct > 0
                                 THEN |Mantiene el código. Exención del { ls_row-exencion_pct NUMBER = USER } % a aplicar con el botón Aplicar Exenciones.|
                                 ELSE `Sin cambios: el indicador ya coincide` ).
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        RETURN.
      ENDIF.
    ENDIF.

    ls_row-estado  = 'ACT'.
    ls_row-mensaje = lv_desc.
    APPEND ls_row TO ct_log.
    ADD 1 TO cs_kpi-actualizados.
  ENDMETHOD.


  METHOD procesar_fuera_padron.
    " Codigo (indicador) del tipo No Inscriptos (TN). Se informa por pantalla (Indicador Fuera de
    " Padron) junto con el Tipo Ret. Fuera de Padron (TN). Sin ellos no se puede determinar -> nota.
    DATA(lv_ind_tn) = is_ejec-indicador_fuera_padron.
    IF is_ejec-tipo_ret_fuera IS INITIAL OR lv_ind_tn IS INITIAL.
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = 'Fuera de padron NO ejecutado: faltan "Tipo Ret. Fuera de Padron" y/o "Indicador Fuera de Padron".' )
             TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
      RETURN.
    ENDIF.

    " Alicuota del TN para el .txt del export (la app estandar lee la alicuota por columna; la BAdI
    " aplica el codigo del log). En Tucuman, TN codigo 01 = 7 %.
    DATA lv_alic_tn TYPE p LENGTH 5 DECIMALS 2.
    lv_alic_tn = mo_determinador->obtener_alicuota_indicador(
                   iv_tipo_ret = is_ejec-tipo_ret_fuera iv_indicador = lv_ind_tn ).

    " Universo TN = titulares TN actuales (keepers / Caso 7) + proveedores por region 14 (EF Caso 6),
    " menos los que estan en el padron. Indexado por proveedor.
    TYPES: BEGIN OF ty_cand,
             supplier TYPE zcl_arba_ret_bp_updater=>ty_supplier,
             cuit     TYPE c LENGTH 11,
             cur_ind  TYPE zcl_arba_ret_tuc_determinador=>ty_wht_code,
             es_tn    TYPE abap_boolean,
           END OF ty_cand.
    DATA lt_cand TYPE HASHED TABLE OF ty_cand WITH UNIQUE KEY supplier.

    " Keepers: titulares TN actuales (lectura confiable de I_SupplierWithholdingTax). Los conserva en
    " el snapshot (evita que la app estandar los borre por ausencia) y resuelve la baja (Caso 7).
    LOOP AT mo_bp->leer_titulares_tipo( iv_sociedad = is_ejec-sociedad iv_tipo = is_ejec-tipo_ret_fuera ) INTO DATA(ls_tn).
      INSERT VALUE #( supplier = ls_tn-supplier cuit = ls_tn-cuit cur_ind = ls_tn-indicador es_tn = abap_true ) INTO TABLE lt_cand.
    ENDLOOP.

    " Altas por region (EF Caso 6). BLINDAJE: si la region no es legible/autorizada, no se agregan
    " altas (solo quedan los keepers) y se loguea; nunca un snapshot vacio.
    DATA lt_region TYPE zcl_arba_ret_bp_updater=>ty_sup_ret_tt.
    DATA lv_reg_err TYPE abap_boolean.
    DATA lv_reg_msg TYPE string.
    mo_bp->get_proveedores_por_region( EXPORTING iv_region  = c_region_tuc
                                       IMPORTING et_sup     = lt_region
                                                 ev_error   = lv_reg_err
                                                 ev_mensaje = lv_reg_msg ).
    IF lv_reg_err = abap_true.
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = |Fuera de padron por region NO ejecutado (region { c_region_tuc } no autorizada/no disponible): { lv_reg_msg }. Se conservan los titulares TN actuales.| )
             TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
    ELSEIF lt_region IS INITIAL.
      APPEND VALUE #( caso    = '3'
                      estado  = 'OMI'
                      mensaje = |Region { c_region_tuc } sin proveedores (o sin autorizacion de lectura de direccion): no se agregaron altas por region. Se conservan los titulares TN actuales.| )
             TO ct_log.
      ADD 1 TO cs_kpi-omitidos.
    ELSE.
      LOOP AT lt_region INTO DATA(ls_reg).
        " EF seccion 8: solo proveedores creados para la sociedad de la ejecucion (cargados por preparar).
        IF mo_bp->esta_ampliado( ls_reg-supplier ) = abap_false.
          CONTINUE.
        ENDIF.
        IF NOT line_exists( lt_cand[ supplier = ls_reg-supplier ] ).
          INSERT VALUE #( supplier = ls_reg-supplier cuit = ls_reg-cuit cur_ind = '' es_tn = abap_false ) INTO TABLE lt_cand.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Emision de filas TN por cada candidato cuyo CUIT NO esta en el padron. Los que SI estan en el
    " padron se excluyen: van como tipo 24 y, al faltar en el snapshot TN, la app estandar les da de baja
    " el TN (Caso 7).
    LOOP AT lt_cand INTO DATA(ls_c).
      DATA ls_row TYPE zcl_arba_ret_proc_app=>ty_log_row.
      CLEAR ls_row.
      ls_row-cuit               = ls_c-cuit.
      ls_row-proveedor          = ls_c-supplier.
      ls_row-caso               = '3'.
      ls_row-tipo_ret           = is_ejec-tipo_ret_fuera.
      ls_row-indicador_anterior = ls_c-cur_ind.
      ls_row-indicador_nuevo    = lv_ind_tn.
      ls_row-alicuota_nueva     = lv_alic_tn.
      ls_row-sujeto_ret_nuevo   = 'X'.

      " Filtro de proveedor: fuera del rango no se toca nada. A un titular TN se lo conserva SIN CAMBIO en
      " el snapshot (con su codigo actual); si no, la app estandar le quitaria el TN por ausencia.
      IF ( is_ejec-prov_desde IS NOT INITIAL AND ls_c-supplier < is_ejec-prov_desde )
      OR ( is_ejec-prov_hasta IS NOT INITIAL AND ls_c-supplier > is_ejec-prov_hasta ).
        IF ls_c-es_tn = abap_false.
          CONTINUE.
        ENDIF.
        ls_row-indicador_nuevo     = ls_c-cur_ind.
        ls_row-alicuota_nueva      = mo_determinador->obtener_alicuota_indicador(
                                       iv_tipo_ret = is_ejec-tipo_ret_fuera iv_indicador = ls_c-cur_ind ).
        ls_row-sujeto_ret_anterior = 'X'.
        ls_row-estado              = 'SCB'.
        ls_row-mensaje             = 'Fuera del filtro de proveedor: se conserva el tipo No Inscriptos sin cambio'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      IF line_exists( it_cuit_padron[ table_line = ls_c-cuit ] ).
        CONTINUE.
      ENDIF.

      IF ls_c-es_tn = abap_true AND ls_c-cur_ind = lv_ind_tn.
        ls_row-sujeto_ret_anterior = 'X'.
        ls_row-estado  = 'SCB'.
        ls_row-mensaje = 'Fuera de padron: ya tiene el tipo No Inscriptos con ese codigo (se conserva)'.
        APPEND ls_row TO ct_log.
        ADD 1 TO cs_kpi-sin_cambios.
        CONTINUE.
      ENDIF.

      ls_row-estado = 'ACT'.
      IF ls_c-es_tn = abap_false.
        " Alta del TN: la app estandar no crea tipos. Sale como Caso 1 para que la cree Ejecutar por API
        " (ZCL_ARBA_RET_ALTA toma las filas caso 1 con el tipo de la fila).
        ls_row-caso    = '1'.
        ls_row-mensaje = |Fuera de padron (region { c_region_tuc }): alta del tipo No Inscriptos (la crea Ejecutar por API)|.
      ELSE.
        ls_row-mensaje = |Fuera de padron (region { c_region_tuc }): cambio de codigo No Inscriptos (aplica la app estandar del tipo TN)|.
      ENDIF.
      APPEND ls_row TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
    ENDLOOP.
  ENDMETHOD.


  METHOD procesar_bajas.
    " Sin tipo de fuera de padron (con "Solo Padron" no es obligatorio) no hay nada que dar de baja. Con el
    " mismo tipo que el de padron (la pantalla no lo permite) se borraria el tipo de padron a todo el archivo.
    IF is_ejec-tipo_ret_fuera IS INITIAL.
      " Informativo (no cuenta en los totales ni va a la solapa Errores).
      APPEND VALUE #( caso    = 'B'
                      estado  = 'OMI'
                      mensaje = 'Bajas del tipo de fuera de padron no revisadas: falta "Tipo Ret. Fuera de Padron".' )
             TO ct_log.
      RETURN.
    ENDIF.
    IF is_ejec-tipo_ret_fuera = is_ejec-tipo_retencion.
      RETURN.
    ENDIF.

    " Proveedores del archivo que quedan con el tipo de padron. El filtro Desde/Hasta ya esta aplicado: fuera
    " del rango la fila es OMI.
    DATA lt_con_padron TYPE HASHED TABLE OF zcl_arba_ret_bp_updater=>ty_supplier WITH UNIQUE KEY table_line.
    LOOP AT ct_log INTO DATA(ls_l) WHERE tipo_ret = is_ejec-tipo_retencion AND proveedor IS NOT INITIAL.
      IF ls_l-estado = 'SCB' OR ls_l-estado = 'ACT'
      OR ( ls_l-estado = 'PCF' AND ls_l-indicador_anterior IS NOT INITIAL ).
        INSERT ls_l-proveedor INTO TABLE lt_con_padron.
      ENDIF.
    ENDLOOP.
    IF lt_con_padron IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT mo_bp->leer_titulares_tipo( iv_sociedad = is_ejec-sociedad iv_tipo = is_ejec-tipo_ret_fuera ) INTO DATA(ls_h).
      IF NOT line_exists( lt_con_padron[ table_line = ls_h-supplier ] ).
        CONTINUE.
      ENDIF.
      " Si el tipo de padron se le da de alta en esta corrida, la baja depende de que el alta salga bien.
      DATA(lv_con_alta) = xsdbool( line_exists( ct_log[ proveedor = ls_h-supplier
                                                         tipo_ret  = is_ejec-tipo_retencion
                                                         estado    = 'ACT'
                                                         caso      = '1' ] ) ).
      APPEND VALUE #( cuit                = ls_h-cuit
                      proveedor           = ls_h-supplier
                      caso                = 'B'
                      tipo_ret            = is_ejec-tipo_ret_fuera
                      indicador_anterior  = ls_h-indicador
                      sujeto_ret_anterior = COND #( WHEN ls_h-es_sujeto = abap_true THEN 'X' ELSE '' )
                      estado              = 'BAJ'
                      mensaje             = |Baja del tipo { is_ejec-tipo_ret_fuera }: viene en el padron con el tipo { is_ejec-tipo_retencion }| &&
                                            COND string( WHEN lv_con_alta = abap_true
                                                         THEN | (sujeta al alta del { is_ejec-tipo_retencion })| ) && `.` )
             TO ct_log.
      ADD 1 TO cs_kpi-actualizados.
    ENDLOOP.
  ENDMETHOD.


  METHOD base_log_row.
    rs_row-nro_linea = is_record-nro_linea.
    rs_row-cuit      = is_record-cuit.
  ENDMETHOD.


  METHOD persistir_log.
    IF it_log IS INITIAL.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD DATA(lv_now).
    DATA lt_db TYPE STANDARD TABLE OF zarba_ret_log.
    TRY.
        " Redmine 33756 (13/10): las filas NOE (CUIT del archivo sin proveedor en SAP) no se graban:
        " no le sirven al usuario y llenaban el Log de Auditoria. Quedan contadas en Total No Encontrados.
        LOOP AT it_log INTO DATA(ls_log) WHERE estado <> 'NOE'.
          APPEND VALUE #(
            ejecucion_uuid      = iv_uuid
            log_uuid            = cl_system_uuid=>create_uuid_x16_static( )
            nro_linea           = ls_log-nro_linea
            cuit                = ls_log-cuit
            proveedor           = ls_log-proveedor
            caso                = ls_log-caso
            tipo_ret            = ls_log-tipo_ret
            indicador_anterior  = ls_log-indicador_anterior
            indicador_nuevo     = ls_log-indicador_nuevo
            alicuota_anterior   = ls_log-alicuota_anterior
            alicuota_nueva      = ls_log-alicuota_nueva
            sujeto_ret_anterior = ls_log-sujeto_ret_anterior
            sujeto_ret_nuevo    = ls_log-sujeto_ret_nuevo
            estado              = ls_log-estado
            mensaje             = ls_log-mensaje
            estado_tecnico      = ls_log-estado_tecnico
            exencion_pct        = ls_log-exencion_pct
            exencion_desde      = ls_log-exencion_desde
            exencion_hasta      = ls_log-exencion_hasta
            last_changed_at     = lv_now ) TO lt_db.
        ENDLOOP.
      CATCH cx_uuid_error.
        RETURN.
    ENDTRY.

    INSERT zarba_ret_log FROM TABLE @lt_db.
    COMMIT WORK.
  ENDMETHOD.


  METHOD finalizar.
    GET TIME STAMP FIELD DATA(lv_now).
    " En ejecucion real no se conserva el archivo.
    DATA(lv_archivo) = COND xstring( WHEN iv_simular = abap_true THEN iv_archivo ELSE VALUE #( ) ).
    DATA(lv_size)    = xstrlen( iv_archivo ).

    UPDATE zarba_ret_ejec
      SET estado_ejecucion       = @iv_estado,
          modo_simulacion        = @iv_simular,
          archivo                = @lv_archivo,
          tamanio_archivo        = @lv_size,
          total_leidos           = @is_kpi-leidos,
          total_actualizados     = @is_kpi-actualizados,
          total_sin_cambios      = @is_kpi-sin_cambios,
          total_no_encontrados   = @is_kpi-no_encontrados,
          total_rechazados       = @is_kpi-rechazados,
          total_error_tecnico    = @is_kpi-error_tecnico,
          total_pendiente_config = @is_kpi-pendiente_config,
          total_omitidos         = @is_kpi-omitidos,
          last_changed_at        = @lv_now
      WHERE ejecucion_uuid = @iv_uuid.
    COMMIT WORK.
  ENDMETHOD.
ENDCLASS.
