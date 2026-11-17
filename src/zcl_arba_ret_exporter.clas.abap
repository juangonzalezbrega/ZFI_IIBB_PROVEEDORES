"! Exportador del padron de CAMBIOS (EF: alimentar a la app estandar
"! "Update Withholding Tax Codes and Open Items" para el ajuste de partidas §6.5).
"!
"! Reconstruye, por cada registro que recibio cambios (log con estado 'ACT'), la MISMA
"! linea del padron ARBA (regimen "R") que ingiere la app estandar, y la comprime en un .zip.
"!
"! Formato de linea (10 campos funcionales + ";" final), p.ej.:
"!   R;25022026;01032026;31032026;20383564361;C;S;N;3,00;01;
"!   1  2        3        4        5           6 7 8 9    10
"!   1=regimen(R) 2=fecha publicacion 3=vig.desde 4=vig.hasta 5=CUIT 6=tipo contrib.
"!   7=marca alta/baja 8=marca cambio alic. 9=alicuota 10=nro grupo
"!
"! Los registros "fuera de padron" (caso 3) no vienen de un archivo: van con CUIT + alicuota
"! (maxima) y los campos de fecha/marca/grupo VACIOS. La app estandar solo lee CUIT (col 5) y
"! alicuota (col 9), asi que las columnas vacias no molestan.
CLASS zcl_arba_ret_exporter DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_alicuota TYPE p LENGTH 5 DECIMALS 2.

    "! Un registro a exportar (subconjunto del log de auditoria con estado 'ACT').
    TYPES: BEGIN OF ty_row,
             cuit               TYPE c LENGTH 11,
             alicuota           TYPE ty_alicuota,
             tipo_contribuyente TYPE c LENGTH 1,
             marca_alta_baja    TYPE c LENGTH 1,
             marca_cambio_alic  TYPE c LENGTH 1,
             nro_grupo          TYPE c LENGTH 2,
             fecha_publicacion  TYPE d,
             vigencia_desde     TYPE d,
             vigencia_hasta     TYPE d,
           END OF ty_row.
    TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    "! Arma el .txt (una linea por registro, formato ARBA regimen R), cada linea con CRLF.
    METHODS build_txt
      IMPORTING it_rows       TYPE ty_rows
                iv_provincia  TYPE c
      RETURNING VALUE(rv_txt) TYPE string.

    "! Comprime el texto en un .zip con una unica entrada iv_entryname y devuelve los bytes.
    METHODS build_zip
      IMPORTING iv_txt        TYPE string
                iv_entryname  TYPE string
      RETURNING VALUE(rv_zip) TYPE xstring.

    "! Una entrada .txt del .zip (nombre + contenido). Para Tucuman se exporta una entrada por tipo
    "! de retencion (24 padron / TN No Inscriptos), porque la app estandar se corre una vez por tipo.
    TYPES: BEGIN OF ty_zip_entry,
             name TYPE string,
             txt  TYPE string,
           END OF ty_zip_entry.
    TYPES ty_zip_entries TYPE STANDARD TABLE OF ty_zip_entry WITH EMPTY KEY.

    "! Comprime varias entradas .txt en un unico .zip (una por tipo de retencion en Tucuman).
    METHODS build_zip_multi
      IMPORTING it_entries    TYPE ty_zip_entries
      RETURNING VALUE(rv_zip) TYPE xstring.

  PRIVATE SECTION.
    CONSTANTS c_regimen TYPE c LENGTH 1 VALUE 'R'.

    METHODS line_from_row
      IMPORTING is_row         TYPE ty_row
                iv_provincia   TYPE c
      RETURNING VALUE(rv_line) TYPE string.

    "! dats (AAAAMMDD) -> "DDMMAAAA"; vacio si la fecha es inicial (p.ej. caso 3 fuera de padron).
    METHODS fmt_fecha
      IMPORTING iv_fecha      TYPE d
      RETURNING VALUE(rv_txt) TYPE string.

    "! alicuota packed(,2) -> "9,99" (coma decimal, 2 decimales fijos, sin depender del locale).
    METHODS fmt_alicuota
      IMPORTING iv_alic       TYPE ty_alicuota
      RETURNING VALUE(rv_txt) TYPE string.
ENDCLASS.



CLASS ZCL_ARBA_RET_EXPORTER IMPLEMENTATION.


  METHOD build_txt.
    LOOP AT it_rows INTO DATA(ls_row).
      rv_txt = rv_txt && line_from_row( is_row = ls_row iv_provincia = iv_provincia ) && cl_abap_char_utilities=>cr_lf.
    ENDLOOP.
  ENDMETHOD.


  METHOD line_from_row.
    " Los campos c() se concatenan sin blancos finales (la conversion a string los recorta),
    " asi los campos vacios del caso 3 quedan realmente vacios (;;).
    " IMPORTANTE: el .txt DEBE respetar el layout de la provincia -> la app estandar lee el CUIT y la
    " alicuota por POSICION de columna, y esa posicion difiere ARBA (CUIT col 5) vs CABA (CUIT col 4).
    IF iv_provincia = 'CABA'.
      " CABA: sin regimen. CUIT col 4; alicuota (retenciones) col 9 (col 8 percepciones = vacio).
      DATA lt_c TYPE STANDARD TABLE OF string WITH EMPTY KEY.
      lt_c = VALUE #( ( fmt_fecha( is_row-fecha_publicacion ) )     " 1
                      ( fmt_fecha( is_row-vigencia_desde ) )        " 2
                      ( fmt_fecha( is_row-vigencia_hasta ) )        " 3
                      ( |{ is_row-cuit }| )                         " 4  CUIT
                      ( |{ is_row-tipo_contribuyente }| )           " 5
                      ( |{ is_row-marca_alta_baja }| )              " 6
                      ( |{ is_row-marca_cambio_alic }| )            " 7
                      ( `` )                                        " 8  percepciones (no disponible)
                      ( fmt_alicuota( is_row-alicuota ) )           " 9  retenciones
                      ( `` )                                        " 10
                      ( `` ) ).                                     " 11
      rv_line = concat_lines_of( table = lt_c sep = `;` ) && `;`.
    ELSE.
      " ARBA (formato actual): regimen col 1, CUIT col 5, alicuota col 9, nro_grupo col 10.
      rv_line = c_regimen
        && ';' && fmt_fecha( is_row-fecha_publicacion )
        && ';' && fmt_fecha( is_row-vigencia_desde )
        && ';' && fmt_fecha( is_row-vigencia_hasta )
        && ';' && is_row-cuit
        && ';' && is_row-tipo_contribuyente
        && ';' && is_row-marca_alta_baja
        && ';' && is_row-marca_cambio_alic
        && ';' && fmt_alicuota( is_row-alicuota )
        && ';' && is_row-nro_grupo
        && ';'.
    ENDIF.
  ENDMETHOD.


  METHOD fmt_fecha.
    IF iv_fecha IS INITIAL.
      rv_txt = ``.
      RETURN.
    ENDIF.
    " iv_fecha = AAAAMMDD  ->  DDMMAAAA
    rv_txt = iv_fecha+6(2) && iv_fecha+4(2) && iv_fecha+0(4).
  ENDMETHOD.


  METHOD fmt_alicuota.
    " Escala a centesimos para separar parte entera y decimales sin depender del separador del locale.
    DATA lv_cent TYPE p LENGTH 8 DECIMALS 0.
    lv_cent = abs( iv_alic ) * 100.
    DATA(lv_ent) = lv_cent DIV 100.
    DATA(lv_dec) = lv_cent MOD 100.
    rv_txt = |{ lv_ent }| && ',' && |{ lv_dec WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.


  METHOD build_zip.
    " NOTA: cl_abap_zip es la API estandar de compresion; verificar que este liberada (C1) en el tenant.
    DATA(lo_zip)      = NEW cl_abap_zip( ).
    DATA(lv_xcontent) = cl_abap_conv_codepage=>create_out( )->convert( source = iv_txt ).
    lo_zip->add( name = iv_entryname content = lv_xcontent ).
    rv_zip = lo_zip->save( ).
  ENDMETHOD.


  METHOD build_zip_multi.
    DATA(lo_zip) = NEW cl_abap_zip( ).
    LOOP AT it_entries INTO DATA(ls_e).
      DATA(lv_x) = cl_abap_conv_codepage=>create_out( )->convert( source = ls_e-txt ).
      lo_zip->add( name = ls_e-name content = lv_x ).
    ENDLOOP.
    rv_zip = lo_zip->save( ).
  ENDMETHOD.
ENDCLASS.
