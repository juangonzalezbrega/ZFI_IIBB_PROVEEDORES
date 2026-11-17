@EndUserText.label: 'Padron Salta - Condiciones'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Semantics.valueRange.maximum: '1'
@ObjectModel.semanticKey: [ 'SingletonID' ]
@UI: {
  headerInfo: {
    typeName: 'SaltaCondicionAll'
  }
}
define root view entity ZI_ARBARETSALC_S
  as select from I_Language
    left outer join ZARBA_RET_SALC on 0 = 0
  association [0..*] to I_ABAPTransportRequestText as _ABAPTransportRequestText on $projection.TransportRequestID = _ABAPTransportRequestText.TransportRequestID
  composition [0..*] of ZI_ArbaRetSalc as _SaltaCondicion
{
  @UI.facet: [ {
    id: 'SaltaCondicion', 
    purpose: #STANDARD, 
    type: #LINEITEM_REFERENCE, 
    label: 'Padrón Salta - Condición', 
    position: 1 , 
    targetElement: '_SaltaCondicion'
  } ]
  @UI.lineItem: [ {
    position: 1 
  } ]
  key 1 as SingletonID,
  _SaltaCondicion,
  @UI.hidden: true
  max( ZARBA_RET_SALC.LAST_CHANGED_AT ) as LastChangedAtMax,
  @ObjectModel.text.association: '_ABAPTransportRequestText'
  @UI.identification: [ {
    position: 1 , 
    type: #WITH_INTENT_BASED_NAVIGATION, 
    semanticObjectAction: 'manage'
  } ]
  @Consumption.semanticObject: 'CustomizingTransport'
  cast( '' as SXCO_TRANSPORT) as TransportRequestID,
  _ABAPTransportRequestText
}
where I_Language.Language = $session.system_language
