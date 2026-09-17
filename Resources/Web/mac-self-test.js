// Run in the actual WKWebView after window.editor.ready(), not Node or a mock DOM.
// Returns a list of passing checks and throws at the first regression.
import {native,request,macNative} from './bridge.js';
import {documentRoot,uuid} from './platform.js';
import {parseHtml,serialize,pasteSafeHtml,portableHtml,renameImageFolder} from './document.js';
import {renameImageFile} from './asset-references.js';
import {markdownToHtml,htmlToMarkdown} from './markdown.js';
import {renderPng,outputBounds} from './annotation-model.js';
import {captureTemplate,parseTemplate,templateJson} from './templates.js';
import {runCodeBlockTests} from './code-block-self-test.js';
import {runDocumentToolsTests} from './document-tools-self-test.js';
import {runInteractionTests} from './mac-interaction-tests.js';

export async function run(){
  const results=[],check=(ok,name)=>{if(!ok){const error=Error(name);error.stack=name+'\n'+error.stack;throw error;}results.push(name);};
  window.sinTestResults=results;
  await window.editor.ready();
  const saved=window.editor.html(),frame=document.querySelector('#document');
  try{
    check(native&&macNative,'WKWebView native bridge is active');
    check(typeof await request('editor-fonts')==='string','Native request/reply correlates a font response');
    check(documentRoot==='sin-asset://document/','Assets resolve through the macOS document scheme');
    const ids=Array.from({length:200},uuid);
    check(new Set(ids).size===200&&ids.every(value=>/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/.test(value)),'Annotation IDs are unique RFC 4122 UUIDs');
    window.__sinDocumentScriptRan=false;
    await window.editor.load('<p>Safe document</p><script>parent.__sinDocumentScriptRan=true<\/script>');
    await new Promise(resolve=>setTimeout(resolve,30));
    check(!window.__sinDocumentScriptRan&&frame.contentDocument.head.firstElementChild?.httpEquiv==='Content-Security-Policy'&&frame.contentDocument.head.firstElementChild.content.includes("script-src 'none'")&&frame.sandbox.contains('allow-same-origin'),'Opened HTML cannot execute scripts; editor retains DOM access');
    check(frame.contentDocument.body.isContentEditable,'Sandboxed document supports native WebKit editing');
    window.__sinScriptEvents=[];
    const nested='<script>parent.parent.__sinScriptEvents.push("nested frame")<\/script>';
    await window.editor.load(`<html><head><meta http-equiv="Content-Security-Policy" content="script-src 'unsafe-inline' data: sin-asset:"><meta http-equiv="refresh" content="0;url=data:text/html,escaped"><script>parent.__sinScriptEvents.push('inline')<\/script><script src="sin-asset://app/security-probe.js"><\/script><script src="data:text/javascript,parent.__sinScriptEvents.push('data script')"><\/script></head><body onload="parent.__sinScriptEvents.push('body handler')"><p>Isolation probe</p><button onclick="parent.__sinScriptEvents.push('event handler')">Probe</button><a href="javascript:parent.__sinScriptEvents.push('javascript URL')">Probe link</a><iframe srcdoc="${nested.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;')}"></iframe><object data="data:text/html,${encodeURIComponent(nested)}"></object></body></html>`);
    const protectedDoc=frame.contentDocument;let trustedClicks=0;
    protectedDoc.addEventListener('click',()=>trustedClicks++);
    protectedDoc.querySelector('button').click();protectedDoc.querySelector('a').click();
    await new Promise(resolve=>setTimeout(resolve,60));
    check(window.__sinScriptEvents.length===0,'CSP rejects inline, external, data, event-handler, javascript-URL, and nested-frame scripts');
    check(trustedClicks===2,'Trusted parent handlers still receive document click events in WebKit');
    check(frame.contentDocument===protectedDoc&&!protectedDoc.querySelector('meta[http-equiv="refresh" i]'),'Document meta refresh cannot navigate away from isolation');
    check(protectedDoc.head.firstElementChild.content.includes("script-src 'none'")&&protectedDoc.querySelectorAll('meta[http-equiv="Content-Security-Policy" i]').length===2,'A later document CSP cannot loosen the first application policy');
    check(window.editor.html().includes('http-equiv="refresh"')&&!window.editor.html().includes('data-sin-refresh-equiv'),'Source metadata survives save while runtime refresh remains disabled');
    await window.editor.load('<p>Safe document</p>');
    await window.editor.restoreView({selectionStart:5,selectionLength:8,scroll:0});
    const view=window.editor.captureView();
    check(view.selectionStart===5&&view.selectionLength===8&&frame.contentDocument.getSelection().toString()==='document','Visual view state restores text selection offsets');
    await window.editor.load(window.editor.html());await window.editor.restoreView(view);
    check(frame.contentDocument.getSelection().toString()==='document','Visual selection survives serialization and reopening');
    const sanitized=pasteSafeHtml('<p onclick="alert(1)">Hello<script>alert(1)<\/script><img src="photo.png" onerror="alert(1)"></p><iframe src="about:blank"></iframe>');
    check(!/script|onclick|onerror|iframe/.test(sanitized)&&sanitized.includes('photo.png'),'HTML paste removes executable elements and handlers');
    const clean=window.editor.html();
    check(!clean.includes('contenteditable')&&!clean.includes('data-sin-runtime')&&!clean.includes('sin-asset:'),'Saved HTML excludes runtime editing attributes and internal base');
    const renamed=parseHtml(renameImageFolder('<img src="Old%20folder/photo.png?size=1#preview"><img src="https://example.invalid/Old%20folder/photo.png">','Old folder','New # folder'));
    check(renamed.images[0].getAttribute('src')==='New%20%23%20folder/photo.png?size=1#preview'&&renamed.images[1].getAttribute('src').startsWith('https://example.invalid/'),'Image folder rename preserves query strings and external URLs');
    const fileRename=parseHtml(renameImageFile('<img src="sin-asset://document/picture.png"><img src="other.png">','file:///tmp/Sin%20Prompt/test.html','file:///tmp/Sin%20Prompt/picture.png','file:///tmp/Sin%20Prompt/new%20picture.png'));
    check(fileRename.images[0].getAttribute('src')==='sin-asset://document/new%20picture.png'&&fileRename.images[1].getAttribute('src')==='other.png','Image rename resolves native document URLs against the actual HTML folder');
    const caseHTML='<img src="A.png"><img src="a.png">',caseDocument='file:///tmp/case-check.html',caseOld='file:///tmp/A.png',caseNew='file:///tmp/renamed.png';
    const sensitive=parseHtml(renameImageFile(caseHTML,caseDocument,caseOld,caseNew,true));
    check(sensitive.images[0].getAttribute('src')==='renamed.png'&&sensitive.images[1].getAttribute('src')==='a.png','Image rename distinguishes separate letter-case filenames on case-sensitive volumes');
    const insensitive=parseHtml(renameImageFile(caseHTML,caseDocument,caseOld,caseNew,false));
    check([...insensitive.images].every(image=>image.getAttribute('src')==='renamed.png'),'Image rename updates case-variant references on case-insensitive volumes');
    await runDocumentToolsTests(check);
    await runCodeBlockTests(check);
    const markdown='# Heading\n\n**Strong** [link](https://example.invalid)\n\n```objectivec\nNSLog(@"Hello");\n```';
    const mdDoc=parseHtml(markdownToHtml(markdown));
    const exported=await htmlToMarkdown(mdDoc,()=>{throw Error('Unexpected image');});
    check(exported.includes('# Heading')&&exported.includes('NSLog(@"Hello");'),'Markdown and source code round-trip');
    const object={id:uuid(),type:'rectangle',name:'Rectangle',x:10,y:20,width:120,height:70,fill:'#ff0000',stroke:'none',strokeWidth:0,visible:true};
    const scene={version:1,width:800,height:500,blankCanvas:true,background:'none',objects:[object]};
    const png=await renderPng(scene),bounds=outputBounds(scene);
    check(png.data.startsWith('data:image/png;base64,')&&png.width===120&&png.height===70&&bounds.x===10,'Annotation SVG renders to cropped PNG using WebKit canvas');
    const template=await parseTemplate(templateJson(captureTemplate(scene.objects,'Test object')));
    check(template.objects.length===1&&template.name==='Test object','Reusable annotation templates retain editable object geometry');
    await runInteractionTests(check,scene,png);
    await window.editor.load(`<p>Image</p><img src="${png.data}" data-sin-storage="inline">`);
    const standalone=parseHtml(await portableHtml(window.editor.html(),documentRoot));
    check(standalone.images.length===1&&standalone.images[0].src.startsWith('data:image/png;base64,')&&!standalone.querySelector('base'),'Standalone HTML embeds its image without private URLs');
    check(!serialize(standalone).includes('data-sin-runtime'),'Standalone export excludes transient state');
    return results;
  }catch(error){error.stack=error.message+'\n'+error.stack;throw error;}
  finally{delete window.__sinDocumentScriptRan;delete window.__sinScriptEvents;await window.editor.load(saved);}
}
