// Ayuda de valores (dropdown) para el Modo de archivo Tucuman: A = Acreditan, C = Coeficientes.
// Se arma con 2 filas literales usando I_Country filtrado a 'AR' (1 fila por rama), igual que la
// ayuda de Provincia.
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Modo Tucuman (Acreditan/Coeficientes) - ayuda de valores'
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZI_ARBA_RET_MODO_VH
  as select from I_Country as c
{
      @EndUserText.label: 'Modo'
  key cast( 'A' as abap.char( 1 ) )                              as Modo,
      @EndUserText.label: 'Descripcion'
      cast( 'A - Acreditan (alicuotas)' as abap.char( 40 ) )     as Descripcion
}
where c.Country = 'AR'

union all

select from I_Country as c2
{
  key cast( 'C' as abap.char( 1 ) )                              as Modo,
      cast( 'C - Coeficientes' as abap.char( 40 ) )              as Descripcion
}
where c2.Country = 'AR'
