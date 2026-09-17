import {uuid} from './platform.js';

// WebKit's rich-text insertion flattens details/figures, but table nodes retain
// native Undo identity. Editing-only presentation tables carry the exact DOM;
// serialization unwraps them back into ordinary portable HTML.
export function wrapAtom(element,kind){
  const existing=element.closest(`table[data-sin-${kind}-wrapper]`);if(existing)return existing;
  const table=element.ownerDocument.createElement('table');table.setAttribute(`data-sin-${kind}-wrapper`,uuid());
  table.setAttribute('role','presentation');table.style.cssText='width:100%;border:0;margin:0';
  const cell=table.insertRow().insertCell();cell.style.cssText='border:0;padding:0';
  element.before(table);cell.append(element);return table;
}
export function insertAtom(doc,markup,kind,insert=null){
  const marker=uuid();
  const carrier=`<table data-sin-${kind}-wrapper="${marker}" role="presentation" style="width:100%;border:0;margin:0"><tbody><tr><td style="border:0;padding:0">Placeholder</td></tr></tbody></table>`;
  if(insert)insert(carrier);else doc.execCommand('insertHTML',false,carrier);
  const shell=doc.querySelector(`[data-sin-${kind}-wrapper="${marker}"]`);
  if(!shell)throw Error('WebKit could not insert the '+kind+' object.');
  shell.querySelector('td').innerHTML=markup;
  // Finalize this replacement as its own native history item.
  doc.execCommand('undo');doc.execCommand('redo');
  return shell;
}
