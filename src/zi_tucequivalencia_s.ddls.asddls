@EndUserText.label: 'Tucuman - Equivalencia alicuota / codigo'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Semantics.valueRange.maximum: '1'
@ObjectModel.semanticKey: [ 'SingletonID' ]
@UI: {
  headerInfo: {
    typeName: 'TucumanEquivalenAll'
  }
}
define root view entity ZI_TucEquivalencia_S
  as select from I_Language
    left outer join I_CstmBizConfignLastChgd on I_CstmBizConfignLastChgd.ViewEntityName = 'ZI_TUCEQUIVALENCIA'
  composition [0..*] of ZI_TucEquivalencia as _TucEquivalencia
{
  @UI.facet: [ {
    id: 'TucEquivalencia', 
    purpose: #STANDARD, 
    type: #LINEITEM_REFERENCE, 
    label: 'Tucuman - Equivalencia alicuota / codigo', 
    position: 1 , 
    targetElement: '_TucEquivalencia'
  } ]
  @UI.lineItem: [ {
    position: 1 
  } ]
  key 1 as SingletonID,
  _TucEquivalencia,
  @UI.hidden: true
  I_CstmBizConfignLastChgd.LastChangedDateTime as LastChangedAtMax
}
where I_Language.Language = $session.system_language
