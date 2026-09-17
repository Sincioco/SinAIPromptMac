// Platform differences stay at the native boundary; the editor remains shared.
export const macNative=!!window.webkit?.messageHandlers?.sinNative;
export const isMac=macNative||/Mac|iPhone|iPad/.test(navigator.platform);
export const documentRoot=macNative?'sin-asset://document/':'https://sin-document.local/';
export function isDocumentUrl(url){return url.hostname==='sin-document.local'||url.protocol==='sin-asset:'&&url.hostname==='document';}
export function uuid(){
  if(crypto.randomUUID)return crypto.randomUUID();
  // Custom WebKit schemes are not always secure contexts, but getRandomValues
  // remains available. Keep the same RFC 4122 IDs in saved annotations/templates.
  const bytes=crypto.getRandomValues(new Uint8Array(16));bytes[6]=bytes[6]&15|64;bytes[8]=bytes[8]&63|128;
  const hex=[...bytes].map(value=>value.toString(16).padStart(2,'0')).join('');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
export function platformShortcuts(root){
  if(!isMac)return;
  for(const attribute of ['title','aria-label'])for(const element of root.querySelectorAll('['+attribute+']'))element.setAttribute(attribute,element.getAttribute(attribute).replaceAll('Ctrl+Alt+','⌘⌥').replaceAll('Ctrl+Y','⇧⌘Z').replaceAll('Ctrl+','⌘'));
  for(const hint of root.querySelectorAll('.hint'))hint.innerHTML=hint.innerHTML.replaceAll('Ctrl+','⌘');
}
