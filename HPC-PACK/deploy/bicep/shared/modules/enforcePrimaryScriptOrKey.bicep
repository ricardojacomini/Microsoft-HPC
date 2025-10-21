// This module intentionally declares a non-existent provider resource
// so that deployments fail when this module is invoked. It's used as
// a template-only enforcement mechanism when required parameters are
// not provided by the caller (per the user's request for option C).

resource forceFail 'Microsoft.NonExistentProvider/forceFail@2020-01-01' = {
  name: 'forceFailure'
  properties: {}
}
