import {attachFileDrop} from './file-drop.js';
import {send,onNativeMessage,macNative} from './bridge.js';
import {isolateDocument} from './document-isolation.js';

// Only this local shell runs scripts. The document remains sandboxed and read-only.
const frame=document.querySelector('#preview');
if(macNative)frame.sandbox.add('allow-scripts');
attachFileDrop(document);
frame.addEventListener('load',()=>attachFileDrop(frame.contentDocument));
window.preview={load:html=>{const doc=new DOMParser().parseFromString(html,'text/html');if(macNative)isolateDocument(doc);frame.srcdoc='<!doctype html>'+doc.documentElement.outerHTML;}};
onNativeMessage(data=>{if(typeof data.html==='string')window.preview.load(data.html);});
send('preview-ready');
