import {native,macNative,request,blobData,report} from './bridge.js';

// WKWebView does not expose File.path. Resolve the drag pasteboard natively first
// so opening a document preserves its folder and relative image references.
// Blob transfer also handles drags without filesystem URLs (for example Photos).
export function attachFileDrop(target){
  target.addEventListener('dragover',event=>{if(native&&event.dataTransfer.types.includes('Files'))event.preventDefault();},true);
  target.addEventListener('drop',event=>{
    if(!native)return;
    const files=[...event.dataTransfer.files].filter(file=>/\.(html?|md|markdown)$/i.test(file.name));
    const images=[...event.dataTransfer.files].filter(file=>/^image\//i.test(file.type)||/\.(png|jpe?g|gif|bmp|webp|svg)$/i.test(file.name));
    if(!files.length&&!images.length)return;
    event.preventDefault();event.stopImmediatePropagation();
    const selected=files.length?files:images;
    if(!macNative){window.chrome.webview.postMessageWithAdditionalObjects({type:files.length?'open-files':'insert-images'},selected);return;}
    (async()=>{
      const kind=files.length?'documents':'images';
      if(await request('drop-paths',{names:selected.map(file=>file.name),kind}).catch(()=>false))return;
      const data=await Promise.all(selected.map(async file=>({name:file.name,type:file.type,data:await blobData(file)})));
      await request('drop-files',{files:data,kind});
    })().catch(report);
  },true);
}
