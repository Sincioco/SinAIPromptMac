import {parseHtml,serialize} from './document.js';
import {isDocumentUrl,isMac} from './platform.js';

// Resolve references against the parent HTML, not whichever document is displayed.
export function renameImageFile(html,documentUrl,oldUrl,newUrl,caseSensitive=isMac) {
  const doc=parseHtml(html),folder=new URL('.',documentUrl);
  const local=url=>isDocumentUrl(url)?new URL(url.pathname.slice(1)+url.search+url.hash,folder):url;
  let base=folder,changed=false;
  try{base=local(new URL(doc.querySelector('base[href]')?.getAttribute('href')||documentUrl,documentUrl));}catch{}
  const old=new URL(oldUrl),replacement=new URL(newUrl);
  for(const image of doc.querySelectorAll('img[src]')){
    const source=image.getAttribute('src');
    try{
      const resolved=local(new URL(source,base));
      const compare=path=>{const decoded=decodeURIComponent(path).normalize('NFC');return caseSensitive?decoded:decoded.toLowerCase();};
      if(resolved.protocol!=='file:'||resolved.hostname.toLowerCase()!==old.hostname.toLowerCase()||compare(resolved.pathname)!==compare(old.pathname))continue;
      // Rename only the final component, preserving relative/absolute form and suffixes.
      const suffix=source.search(/[?#]/),path=suffix<0?source:source.slice(0,suffix);
      image.setAttribute('src',path.slice(0,path.lastIndexOf('/')+1)+replacement.pathname.split('/').at(-1)+(suffix<0?'':source.slice(suffix)));
      changed=true;
    }catch{/* An unrelated malformed reference must not block a local rename. */}
  }
  return changed?serialize(doc):html;
}
