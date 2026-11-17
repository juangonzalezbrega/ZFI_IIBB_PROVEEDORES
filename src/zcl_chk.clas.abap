CLASS zcl_chk DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
protected section.
private section.
ENDCLASS.



CLASS ZCL_CHK IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    SELECT FROM i_supplierwithholdingtax
      FIELDS supplier, companycode, withholdingtaxtype, withholdingtaxcode
      INTO TABLE @DATA(lt) UP TO 20 ROWS.
    out->write( |Filas: { lines( lt ) }| ).
    out->write( lt ).
  ENDMETHOD.
ENDCLASS.
