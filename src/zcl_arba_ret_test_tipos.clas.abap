"! Clase utilitaria TEMPORAL de DIAGNOSTICO. Vuelca, para Argentina, TODO el texto/descripcion que
"! exponen las vistas LIBERADAS relacionadas con el Tipo de Retencion, para decidir si hay alguna
"! fuente dinamica aprovechable (y descartar de una vez):
"!   (1) Tipos distintos = lo que hoy muestra el dropdown (ZI_ARBA_RET_TIPO_VH -> distinct WITHT).
"!   (2) I_ExtendedWhldgTaxCode: base liberada del origen del dropdown. Incluye WhldgTaxReferenceText
"!       (texto por codigo) y WithholdingTaxIncomeType (clasificador con texto propio, ver 4).
"!   (3) I_ExtendedWhldgTaxCodeText: descripcion por CODIGO (todos los idiomas).
"!   (4) I_WithholdingTaxIncomeTypeText: descripcion de Income Type (esta vista SI esta released);
"!       si cada WITHT usa un income type con texto util, podria servir de fuente dinamica.
"! Correr con F9 en ADT (Run As -> ABAP Application (Console)) y pegar TODA la salida. Borrar al terminar.
CLASS zcl_arba_ret_test_tipos DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.



CLASS ZCL_ARBA_RET_TEST_TIPOS IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.

    "==================================================================
    " (1) TIPOS distintos (lo que hoy ve el usuario en el matchcode).
    "==================================================================
    SELECT DISTINCT country, withholdingtaxtype
      FROM i_extendedwhldgtaxcode
      WHERE country = 'AR'
      ORDER BY country, withholdingtaxtype
      INTO TABLE @DATA(lt_tipos).

    out->write( `===== (1) TIPOS distintos (AR) = lo que muestra el dropdown =====` ).
    IF lt_tipos IS INITIAL.
      out->write( 'Sin datos para country = AR (revisar release / autorizacion).' ).
      RETURN.
    ENDIF.
    out->write( lt_tipos ).

    "==================================================================
    " (2) Volcado COMPLETO de la config de codigos (AR) con TODOS los campos
    "     descriptivos que expone la vista (incluye WhldgTaxReferenceText e IncomeType).
    "==================================================================
    SELECT country, withholdingtaxtype, withholdingtaxcode, officialwhldgtaxcode,
           withholdingtaxpercent, withholdingtaxincometype,
           region, provincialtaxcode, whldgtaxreferencetext
      FROM i_extendedwhldgtaxcode
      WHERE country = 'AR'
      ORDER BY withholdingtaxtype, withholdingtaxcode
      INTO TABLE @DATA(lt_cfg).

    out->write( `===== (2) I_ExtendedWhldgTaxCode (AR) - campos descriptivos por CODIGO =====` ).
    out->write( lt_cfg ).

    "==================================================================
    " (3) Texto por CODIGO (unica descripcion liberada segura). Todos los idiomas.
    "==================================================================
    SELECT countrycode, withholdingtaxtype, withholdingtaxcode, language, whldgtaxcodename
      FROM i_extendedwhldgtaxcodetext
      WHERE countrycode = 'AR'
      ORDER BY withholdingtaxtype, withholdingtaxcode, language
      INTO TABLE @DATA(lt_codetxt).

    out->write( `===== (3) I_ExtendedWhldgTaxCodeText (AR) - texto por CODIGO (todos los idiomas) =====` ).
    IF lt_codetxt IS INITIAL.
      out->write( 'Sin datos.' ).
    ELSE.
      out->write( lt_codetxt ).
    ENDIF.

    "==================================================================
    " (4) Texto de INCOME TYPE (vista LIBERADA). Cruzar con el income type de (2):
    "     si cada tipo de retencion mapea a un income type con descripcion util,
    "     esto seria una fuente DINAMICA valida.
    "==================================================================
    SELECT country, withholdingtaxincometype, language, withholdingtaxincometypename
      FROM i_withholdingtaxincometypetext
      WHERE country = 'AR'
      ORDER BY withholdingtaxincometype, language
      INTO TABLE @DATA(lt_inctxt).

    out->write( `===== (4) I_WithholdingTaxIncomeTypeText (AR) - texto de Income Type (released) =====` ).
    IF lt_inctxt IS INITIAL.
      out->write( 'Sin datos (ningun income type con texto para AR).' ).
    ELSE.
      out->write( lt_inctxt ).
    ENDIF.

  ENDMETHOD.
ENDCLASS.
