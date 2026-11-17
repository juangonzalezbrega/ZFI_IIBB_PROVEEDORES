// Ayuda de valores (dropdown) para el campo Provincia del padron: ARBA / CABA / SF / TUC / SAL.
// Se arma con 1 fila literal por provincia usando I_Country filtrado a 'AR' (1 fila por rama).
// Padrones habilitados por cliente (17/10): cada rama se cruza con la tabla de customizing ZARBA_RET_PROV
// (app "Custom Business Configurations", objeto ZARBA_RET_PROV). La provincia se muestra si NO esta en la
// tabla o si esta con Activa = 'X'. Tabla vacia = todas visibles (comportamiento anterior).
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Provincia padron - ayuda de valores'
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZI_ARBA_PROVINCIA_VH
  as select from I_Country as c
    left outer join zarba_ret_prov as h1 on h1.provincia = 'ARBA'
{
      @EndUserText.label: 'Provincia'
  key cast( 'ARBA' as abap.char( 4 ) )                             as Provincia,
      @EndUserText.label: 'Descripcion'
      cast( 'ARBA - Prov. de Buenos Aires' as abap.char( 40 ) )    as Descripcion
}
where c.Country = 'AR'
  and ( h1.provincia is null or h1.activa = 'X' )

union all

select from I_Country as c2
    left outer join zarba_ret_prov as h2 on h2.provincia = 'CABA'
{
  key cast( 'CABA' as abap.char( 4 ) )                             as Provincia,
      cast( 'CABA - Ciudad Aut. de Buenos Aires' as abap.char( 40 ) ) as Descripcion
}
where c2.Country = 'AR'
  and ( h2.provincia is null or h2.activa = 'X' )

union all

select from I_Country as c3
    left outer join zarba_ret_prov as h3 on h3.provincia = 'SF'
{
  key cast( 'SF' as abap.char( 4 ) )                              as Provincia,
      cast( 'Santa Fe (CM / Local)' as abap.char( 40 ) )          as Descripcion
}
where c3.Country = 'AR'
  and ( h3.provincia is null or h3.activa = 'X' )

union all

select from I_Country as c4
    left outer join zarba_ret_prov as h4 on h4.provincia = 'TUC'
{
  key cast( 'TUC' as abap.char( 4 ) )                             as Provincia,
      cast( 'Tucuman (Acreditan / Coeficientes)' as abap.char( 40 ) ) as Descripcion
}
where c4.Country = 'AR'
  and ( h4.provincia is null or h4.activa = 'X' )

union all

select from I_Country as c5
    left outer join zarba_ret_prov as h5 on h5.provincia = 'SAL'
{
  key cast( 'SAL' as abap.char( 4 ) )                             as Provincia,
      cast( 'Salta (DGR)' as abap.char( 40 ) )                    as Descripcion
}
where c5.Country = 'AR'
  and ( h5.provincia is null or h5.activa = 'X' )
  
// #33749 - Entre Rios (ATER)
// Se incorpora ER al selector de provincias.
// La provincia solo debe estar disponible cuando esta habilitada.

union all

select from I_Country as c6
    left outer join zarba_ret_prov as h6
      on h6.provincia = 'ER'
{
  key cast( 'ER' as abap.char( 4 ) )                 as Provincia,
      cast( 'Entre Rios (ATER)' as abap.char( 40 ) ) as Descripcion
}
where c6.Country = 'AR'
  and ( h6.provincia is null or h6.activa = 'X' )
    
