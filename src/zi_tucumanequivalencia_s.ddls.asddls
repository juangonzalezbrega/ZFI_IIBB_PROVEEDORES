@EndUserText.label: 'temp'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define view entity ZI_TucumanEquivalencia_S
  as select from I_Language
{
  key 1 as SingletonID
}
where I_Language.Language = $session.system_language
