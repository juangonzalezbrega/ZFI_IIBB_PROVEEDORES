@EndUserText.label: 'ARBA Ret. - Texto de codigo sin alicuota'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.resultSet.sizeCategory: #XS
// Texto de cada indicador de retencion sin la alicuota: corta desde el primer
// token "N%" / "N,NN%" (precedido por blanco y seguido de blanco o fin) hasta el final.
// Ej.: 'IIBB Santa Fe 0,10% Exento Act. Ind.' -> 'IIBB Santa Fe'.
// No toca porcentajes pegados o entre parentesis ('seg.comp.0%', '(21 o 27%)').
// Excepcion: si despues de la alicuota viene "No Insc...", solo se quita el porcentaje, para que
// el tipo de No Inscriptos no quede igual al del padron. Ej.: TN 'IIBB Tucuman 7% No Inscriptos'
// -> 'IIBB Tucuman No Inscriptos' (el 24 queda 'IIBB Tucuman').
define view entity ZI_ARBA_RET_TIPO_TXT_B
  as select from I_ExtendedWhldgTaxCodeText as txt
{
  key txt.CountryCode        as Country,
  key txt.WithholdingTaxType as WithholdingTaxType,
  key txt.WithholdingTaxCode as WithholdingTaxCode,
      cast( replace_regexpr( pcre  => '\\s+\\d[^\\s%]*%(\\s.*)?$',
                             value => replace_regexpr( pcre  => '\\s+\\d[^\\s%]*%\\s+(?=No\\s+Insc)',
                                                       value => txt.WhldgTaxCodeName,
                                                       with  => ' ',
                                                       result_length => 40 ),
                             with  => ' ',
                             result_length => 40 ) as abap.char(40) ) as TextoBase
}
where txt.Language = $session.system_language
