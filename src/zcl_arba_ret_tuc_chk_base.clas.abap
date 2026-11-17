CLASS zcl_arba_ret_tuc_chk_base DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    " --- Ajustar antes de correr ---
    CONSTANTS c_sociedad  TYPE c LENGTH 4 VALUE '3110'.
    CONSTANTS c_tipo      TYPE c LENGTH 2 VALUE '24'.
    " Opcional: acotar a un proveedor de prueba (vacio = todos los del filtro).
    CONSTANTS c_proveedor TYPE c LENGTH 10 VALUE ''.
ENDCLASS.



CLASS ZCL_ARBA_RET_TUC_CHK_BASE IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    TYPES: BEGIN OF ty_out,
             supplier          TYPE c LENGTH 10,
             documento         TYPE c LENGTH 10,
             ejercicio         TYPE c LENGTH 4,
             tipo              TYPE c LENGTH 2,
             codigo            TYPE c LENGTH 2,
             base_retencion    TYPE p LENGTH 15 DECIMALS 2,
             importe_documento TYPE p LENGTH 15 DECIMALS 2,
             difiere           TYPE c LENGTH 2,
           END OF ty_out.
    DATA lt_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    " --- Diagnostico: entender por que puede no haber filas ---
    " 1) Partidas abiertas de proveedor (sin filtrar retencion).
    SELECT COUNT(*) FROM I_OperationalAcctgDocItem
      WHERE CompanyCode = @c_sociedad
        AND FinancialAccountType = 'K'
        AND ClearingJournalEntry = ''
      INTO @DATA(lv_open_k).
    out->write( |Partidas abiertas de proveedor (K, sin compensar) en la sociedad: { lv_open_k }| ).

    " 2) Items de retencion por tipo (cualquier estado): muestra que tipos tienen documentos posteados.
    SELECT w~WithholdingTaxType AS tipo, COUNT(*) AS cnt
      FROM I_WithholdingTaxItem AS w
      WHERE w~CompanyCode = @c_sociedad
      GROUP BY w~WithholdingTaxType
      INTO TABLE @DATA(lt_by_type).
    out->write( |Items de retencion por tipo en la sociedad:| ).
    out->write( lt_by_type ).

    " Partidas ABIERTAS de proveedor (FinancialAccountType = K, sin compensar) con item de retencion,
    " para la sociedad y el tipo indicados. Se lee la base de retencion y el importe del documento.
    SELECT o~Supplier                     AS supplier,
           w~AccountingDocument           AS documento,
           w~FiscalYear                   AS ejercicio,
           w~WithholdingTaxType           AS tipo,
           w~WithholdingTaxCode           AS codigo,
           w~WhldgTaxBaseAmtInTransacCrcy AS base_retencion,
           o~AmountInTransactionCurrency  AS importe_documento
      FROM I_WithholdingTaxItem AS w
      INNER JOIN I_OperationalAcctgDocItem AS o
        ON  o~CompanyCode        = w~CompanyCode
        AND o~AccountingDocument = w~AccountingDocument
        AND o~FiscalYear         = w~FiscalYear
      WHERE o~FinancialAccountType = 'K'
        AND o~ClearingJournalEntry = ''
        AND w~CompanyCode          = @c_sociedad
        AND w~WithholdingTaxType   = @c_tipo
      INTO TABLE @DATA(lt_raw)
      UP TO 500 ROWS.

    LOOP AT lt_raw INTO DATA(ls).
      IF c_proveedor IS NOT INITIAL AND ls-supplier <> c_proveedor.
        CONTINUE.
      ENDIF.
      APPEND VALUE #(
        supplier          = ls-supplier
        documento         = ls-documento
        ejercicio         = ls-ejercicio
        tipo              = ls-tipo
        codigo            = ls-codigo
        base_retencion    = ls-base_retencion
        importe_documento = ls-importe_documento
        " Condicion de la EF: base <> 0 y base <> importe (comparo en valor absoluto por el signo).
        difiere           = COND #( WHEN ls-base_retencion <> 0
                                     AND abs( ls-base_retencion ) <> abs( ls-importe_documento )
                                    THEN 'SI' ELSE 'NO' ) ) TO lt_out.
    ENDLOOP.

    out->write( |Sociedad { c_sociedad } - Tipo { c_tipo } - Proveedor { COND #( WHEN c_proveedor IS INITIAL THEN '(todos)' ELSE c_proveedor ) }| ).
    out->write( |Partidas abiertas con retencion: { lines( lt_out ) }| ).
    out->write( lt_out ).
  ENDMETHOD.
ENDCLASS.
