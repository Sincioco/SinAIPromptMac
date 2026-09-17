// WebKit requires allow-scripts for trusted parent-owned DOM listeners to fire.
// This first CSP blocks document-authored script and child browsing contexts.
export function isolateDocument(doc){
  for(const meta of doc.querySelectorAll('meta[http-equiv]'))if(meta.httpEquiv.toLowerCase().trim()==='refresh'){
    meta.dataset.sinRefreshEquiv=meta.getAttribute('http-equiv');meta.removeAttribute('http-equiv');
  }
  const policy=doc.createElement('meta');policy.httpEquiv='Content-Security-Policy';
  policy.content="script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'";
  policy.dataset.sinRuntime='1';doc.head.prepend(policy);
}
export function restoreDocumentMetadata(root){
  for(const meta of root.querySelectorAll('meta[data-sin-refresh-equiv]')){
    meta.setAttribute('http-equiv',meta.dataset.sinRefreshEquiv);meta.removeAttribute('data-sin-refresh-equiv');
  }
}
