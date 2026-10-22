// Run inside the real WKWebView. Canvas pixels, native clipboard and DOM editing
// are real; synthetic pointer events exercise the installed annotation listeners.
import {request,report} from './bridge.js';
import {parseHtml,loadImage} from './document.js';
import {markdownDocument} from './markdown.js';
import {rewriteProjectReferences} from './project-references.js';
import {runProjectReferenceTests} from './project-references-self-test.js';
import {combineDocuments} from './document-combine.js';
import {cleanOriginalImages} from './original-images.js';
import {annotate} from './annotation-ui.js';
import {sliceBounds,sliceDividers,sliceCellCount,setSliceCount,moveSliceDivider,createSliceImages,copySlice,saveAllSlices} from './image-slicing.js';

const tick=()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
async function until(predicate,name){
  const deadline=performance.now()+5000;
  while(performance.now()<deadline){const result=await predicate();if(result)return result;await new Promise(resolve=>setTimeout(resolve,10));}
  throw Error('Timed out: '+name);
}
async function pixels(source){
  const image=await loadImage(source),canvas=document.createElement('canvas');canvas.width=image.naturalWidth;canvas.height=image.naturalHeight;
  const context=canvas.getContext('2d');context.drawImage(image,0,0);
  return {width:canvas.width,height:canvas.height,data:context.getImageData(0,0,canvas.width,canvas.height).data};
}
const exactColor=(image,color)=>image.data.every((value,index)=>value===color[index%4]);
async function withSliceBridge(handler,work){
  const bridge=window.webkit.messageHandlers.sinNative,original=bridge.postMessage;
  bridge.postMessage=function(message){
    if(!message.type.startsWith('slice-export-'))return original.call(this,message);
    Promise.resolve().then(()=>handler(message)).then(result=>window.sinNativeReply({id:message.id,result}),error=>window.sinNativeReply({id:message.id,error:error.message}));
  };
  try{return await work();}finally{bridge.postMessage=original;}
}

export async function runParityTests(check){
  const frame=document.querySelector('#document'),doc=()=>frame.contentDocument;
  const select=(element,start=null,end=null)=>{
    const range=doc().createRange();range.selectNodeContents(element);
    if(start!=null){range.setStart(element.firstChild,start);range.setEnd(element.firstChild,end??start);}
    doc().body.focus();doc().getSelection().removeAllRanges();doc().getSelection().addRange(range);doc().dispatchEvent(new Event('selectionchange'));
  };
  runProjectReferenceTests(check);
  const old='file:///tmp/Projects/Old/Prompt.html',next='file:///tmp/Projects/New/Prompt.html';
  const moves=[{oldUrl:'file:///tmp/Projects/Old/Art/',newUrl:'file:///tmp/Projects/New/Art/',directory:true}];
  const moved=parseHtml(rewriteProjectReferences('<img src="sin-asset://document/Art/a.png?x=1#part"><img src="art/a.png">',old,next,moves,true));
  check(moved.images[0].getAttribute('src')==='Art/a.png?x=1#part'&&moved.images[1].getAttribute('src')==='file:///tmp/Projects/Old/art/a.png','Mac project moves resolve the custom scheme and distinguish differently cased asset folders');
  const insensitive=parseHtml(rewriteProjectReferences('<img src="art/a.png">',old,next,moves,false));
  check(insensitive.images[0].getAttribute('src')==='art/a.png','Project moves honor native case-insensitive volume comparison');
  const exactAssets=[
    {oldUrl:'file:///tmp/Projects/Old/Prompt/',newUrl:'file:///tmp/Projects/New/Prompt/',directory:true,caseSensitive:false},
    {oldUrl:'file:///tmp/Projects/Old/Prompt/picture.png',newUrl:'file:///tmp/Projects/New/Prompt/picture.png',caseSensitive:false},
    {oldUrl:'file:///tmp/Projects/Old/Prompt/Subfolder/',newUrl:'file:///tmp/Projects/New/Prompt/Subfolder/',directory:true,caseSensitive:false},
    {oldUrl:'file:///tmp/Projects/Old/Prompt/Subfolder/Another%20%23.png',newUrl:'file:///tmp/Projects/New/Prompt/Subfolder/Another%20%23.png',caseSensitive:false}
  ];
  const sensitiveDestination=parseHtml(window.editor.rewriteProjectReferences('<img src="prompt/PICTURE.PNG?size=2#part" data-sin-original-source="sin-asset://document/PROMPT/picture.PNG"><img srcset="prompt/subfolder/ANOTHER%20%23.PNG 2x"><div style="background:url(prompt/PICTURE.PNG)"></div>',old,next,exactAssets,false,true));
  check(sensitiveDestination.images[0].getAttribute('src')==='Prompt/picture.png?size=2#part'&&sensitiveDestination.images[0].getAttribute('data-sin-original-source')==='Prompt/picture.png'&&sensitiveDestination.images[1].getAttribute('srcset')==='Prompt/Subfolder/Another%20%23.png 2x'&&sensitiveDestination.querySelector('div').style.backgroundImage==='url("Prompt/picture.png")','Moving from an insensitive to a sensitive volume restores actual asset filename case in image, original, responsive and CSS references');
  const caseWithBase=parseHtml(rewriteProjectReferences('<base href="./"><img src="prompt/PICTURE.PNG"><img src="unmoved.png">',old,next,exactAssets,false,true));
  check(caseWithBase.querySelector('base').getAttribute('href')==='file:///tmp/Projects/Old/'&&caseWithBase.images[0].getAttribute('src')==='file:///tmp/Projects/New/Prompt/picture.png'&&caseWithBase.images[1].getAttribute('src')==='unmoved.png','Cross-volume asset case correction respects an explicit base whose folder stays in the old project');
  const mixedMappings=[
    {oldUrl:'file:///Volumes/Sensitive/a.html',newUrl:'file:///tmp/Projects/New/a.html',caseSensitive:true},
    {oldUrl:'file:///Volumes/Insensitive/Other.html',newUrl:'file:///tmp/Projects/New/Other.html',caseSensitive:false}
  ];
  const mixedVolumes=parseHtml(rewriteProjectReferences('<a href="file:///Volumes/Sensitive/A.html">Distinct</a><a href="file:///Volumes/Sensitive/a.html">Moved</a><a href="file:///Volumes/Insensitive/OTHER.html">Moved</a>',old,next,mixedMappings,false,true));
  check([...mixedVolumes.querySelectorAll('a')].map(link=>link.getAttribute('href')).join('|')==='file:///Volumes/Sensitive/A.html|a.html|Other.html','Mixed-volume project moves compare each source mapping with its own filesystem sensitivity');
  const distinctDestination=parseHtml(rewriteProjectReferences('<img src="outside.png">',old,next,[{oldUrl:'file:///tmp/Projects/Old/outside.png',newUrl:'file:///tmp/Projects/new/outside.png'}],false,true));
  check(distinctDestination.images[0].getAttribute('src')==='file:///tmp/Projects/new/outside.png','Relative project references distinguish differently cased destination folders on a sensitive volume');
  const unicode=parseHtml(rewriteProjectReferences('<img src="Cafe%CC%81/a.png">',old,next,[{oldUrl:'file:///tmp/Projects/Old/Caf%C3%A9/',newUrl:'file:///tmp/Projects/New/Caf%C3%A9/',directory:true}],true));
  check(unicode.images[0].getAttribute('src')==='Cafe%CC%81/a.png','Project moves recognize canonically equivalent Unicode filenames');
  const markdown=parseHtml(markdownDocument('# Imported\n\n![Local](pictures/a.png) [Sibling](other.md) [Anchor](#part)','file:///tmp/Source/readme.md'));
  check(markdown.images[0].getAttribute('src')==='file:///tmp/Source/pictures/a.png'&&markdown.querySelector('a').getAttribute('href')==='file:///tmp/Source/other.md'&&markdown.querySelectorAll('a')[1].getAttribute('href')==='#part','Editable Markdown import preserves source-folder images, sibling links and local anchors');
  check(window.editor.documentTitle('<p data-sin-style="title"> </p><figure><p data-sin-style="title">Skip</p></figure><p data-sin-style="title"> My\n  Prompt </p>')==='My Prompt','First-save title extraction ignores empty and embedded titles and normalizes whitespace');
  const combined=parseHtml(await combineDocuments([
    {html:'<style>.first{color:red}</style><h1 id="part">First</h1><ol start="5"><li>A</li><li>B</li></ol><a href="#part">Anchor</a><a href="other.html">Sibling</a><script>parent.__combineExecuted=true<\/script><p onclick="alert(1)">Safe</p>',base:'file:///tmp/One/a.html'},
    {html:'<h1 id="part">Second</h1><ol start="8"><li value="40">C</li></ol><a href="#part">Anchor</a><iframe srcdoc="bad"></iframe>',base:'file:///tmp/Two/b.html'}
  ]));
  check([...combined.querySelectorAll('section[data-sin-combined] h1')].map(node=>node.textContent).join(',')==='First,Second'&&combined.querySelectorAll('ol')[1].start===3&&!combined.querySelector('li[value]'),'Combine preserves page order and continues top-level numbering');
  check(combined.querySelectorAll('h1')[1].id==='sin-combined-2-part'&&combined.querySelector('a').getAttribute('href')==='#sin-combined-1-part'&&combined.querySelectorAll('a')[1].href==='file:///tmp/One/other.html','Combine isolates duplicate IDs and preserves each source document link base');
  check(!combined.querySelector('script,iframe,[onclick]')&&!window.__combineExecuted,'Combining parses detached documents and removes executable content');
  const originalImages=parseHtml('<img src="file:///tmp/a.png" srcset="sin-asset://original/runtime" data-sin-original-srcset="&quot;authored.png 2x&quot;"><img src="file:///tmp/b.png" srcset="runtime" data-sin-original-srcset="null"><img src="file:///tmp/c.png" srcset="runtime" data-sin-original-srcset="&quot;&quot;">');
  cleanOriginalImages(originalImages);
  check(originalImages.images[0].getAttribute('srcset')==='authored.png 2x'&&!originalImages.images[1].hasAttribute('srcset')&&originalImages.images[2].getAttribute('srcset')===''&&!originalImages.querySelector('[data-sin-original-srcset]'),'Original-image cleanup restores authored, absent and empty srcset values exactly');

  await window.editor.load('<p>Spellcheck sample</p>');window.editor.setSpellcheck(false);
  check(doc().body.spellcheck===false,'Spell Check toggles the live WebKit editable document');
  await window.editor.load('<p>Another sample</p>');
  check(doc().body.spellcheck===false&&!window.editor.html().includes('spellcheck='),'Spell Check survives document loading without changing saved HTML');window.editor.setSpellcheck(true);
  await window.editor.load('<p><br></p>');select(doc().querySelector('p'));
  window.editor.command('insertDateHeading','Wednesday, October 21, 2026');
  const date=doc().body.firstElementChild,following=doc().body.lastElementChild;
  check(date.dataset.sinStyle==='heading2'&&date.textContent==='Wednesday, October 21, 2026'&&following!==date&&following.dataset.sinStyle==='normal'&&following.contains(doc().getSelection().anchorNode),'Long Date inserts Heading 2 and leaves a Normal paragraph ready for typing');
  const plain='# Literal heading\r\nhttps://youtu.be/abcdefghijk\r\n**No bold**';
  await request('editor-copy',{html:'<h1>Rich clipboard</h1>',text:plain});
  await window.editor.load('');select(doc().body);
  await window.editor.command('pasteText');
  check([...doc().body.children].map(node=>node.textContent).join('\n')===plain.replace(/\r\n/g,'\n')&&!doc().querySelector('h1,strong,figure'),'Paste as Text inserts literal Markdown and video URLs as plain paragraphs');
  const pasteMenu=document.querySelector('#pasteOptionsMenu');document.querySelector('#pasteOptions').click();await tick();
  check(pasteMenu.matches(':popover-open')&&pasteMenu.querySelector('[data-cmd=pasteText]'),'Ribbon Paste arrow opens the two-command Paste Options menu');
  pasteMenu.dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true,cancelable:true}));
  check(document.activeElement===pasteMenu.querySelector('[data-cmd=pasteText]'),'Paste menu supports keyboard navigation');
  pasteMenu.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
  check(!pasteMenu.matches(':popover-open'),'Escape dismisses Paste Options');
  await window.editor.load('<h1>Heading</h1><p>Paragraph</p><ol><li>First</li><li>Second</li></ol>');window.editor.command('selectAll');
  await window.editor.command('copy');const copied=await request('editor-paste',{textOnly:true});
  check(/Heading\s*\n\s*Paragraph/.test(copied.text)&&/First[^\n]*\n[^\n]*Second/.test(copied.text),'Native text clipboard preserves rendered breaks between headings, paragraphs and list items');
  await window.editor.load('<ol start="8"><li>Earlier</li></ol><p>Gap</p><p id="new-list">Later</p>');select(doc().querySelector('#new-list'),0);window.editor.command('insertOrderedList');
  check([...doc().querySelectorAll('li')].find(node=>node.textContent==='Later')?.value===9,'A newly created numbered list continues the preceding list by default');
  for(const style of ['title','heading','heading2']){
    await window.editor.load('<p id="split">Firstxy</p>');select(doc().querySelector('p'));document.querySelector(`[data-style=${style}]`).click();select(doc().querySelector('p'),5);
    // Native execCommand performs the real split. Supply the same beforeinput
    // event a key press emits so its post-input formatting listener is exercised.
    doc().dispatchEvent(new InputEvent('beforeinput',{inputType:'insertParagraph',bubbles:true,cancelable:true}));
    doc().execCommand('insertParagraph');
    const split=doc().body.lastElementChild;
    check(split.textContent==='xy'&&split.dataset.sinStyle==='normal'&&doc().body.firstElementChild.dataset.sinStyle===style,style+' split resets an existing second paragraph to Normal');
    doc().execCommand('insertText',false,'Z');check(split.textContent==='Zxy',style+' split places typing before the following text');
  }
  await window.editor.load('<p data-sin-style="title" style="font-size:34pt;color:red">Visible</p><div hidden>Hidden sentinel</div><script>parent.__clearExecuted=true<\/script><input type="hidden" value="secret"><p>Last</p>');
  const beforeClear=window.editor.html();window.editor.command('selectAll');window.editor.command('delete');
  check(doc().body.children.length===1&&doc().body.firstElementChild.dataset.sinStyle==='normal'&&!doc().body.textContent.trim()&&!doc().body.querySelector('script,[hidden],input'),'Select All and Delete clear hidden content and restore one empty Normal paragraph');
  window.editor.command('undo');
  check(doc().body.textContent.includes('Hidden sentinel')&&doc().body.querySelector('input[type=hidden]')&&!window.__clearExecuted,'Full clear supports native Undo without executing restored document scripts');
  window.editor.command('redo');check(!doc().body.textContent.trim()&&!doc().body.querySelector('[hidden]'),'Full clear supports native Redo');
  await window.editor.load(beforeClear);window.editor.command('selectAll');await window.editor.command('cut');
  check(!doc().body.textContent.trim()&&(await request('editor-paste',{textOnly:true})).text.includes('Visible'),'Cut copies the rendered selection before completely clearing the document');
  const notice=document.querySelector('#notice'),message=notice.querySelector('.notice-message'),error='Unavailable image: '+('Long name '.repeat(30))+'\n'+'x'.repeat(300);
  report(Error(error));await tick();
  check(message.textContent===error&&Math.abs(notice.getBoundingClientRect().left-frame.getBoundingClientRect().left)<1&&message.scrollWidth<=message.clientWidth+1,'Long error notices align with the editor and wrap without losing text');
  message.click();check(!notice.hidden,'Clicking error text leaves it available for selection and copying');document.querySelector('#dismissNotice').click();check(notice.hidden,'The accessible dismiss button closes the notice');

  const canvas=document.createElement('canvas');canvas.width=40;canvas.height=20;const context=canvas.getContext('2d');
  const palette=[[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,255,0,255]];
  palette.forEach((color,index)=>{context.fillStyle=`rgb(${color.slice(0,3)})`;context.fillRect(index%2*20,Math.floor(index/2)*10,20,10);});
  const png=canvas.toDataURL('image/png');
  await window.editor.load(`<p>Image</p><img src="${png}">`);await doc().images[0].decode();doc().images[0].click();
  check(document.querySelector('[data-image-action=select]')&&document.querySelector('[data-image-action=copy]'),'Image menu includes Select Image and Copy Image');
  document.querySelector('[data-image-action=select]').click();check(doc().images[0].hasAttribute('data-sin-selected'),'Select Image restores image selection and resize controls');
  await request('editor-copy',{html:'<p>Reset</p>',text:'Reset'});doc().images[0].click();document.querySelector('[data-image-action=copy]').click();
  const imagePaste=await until(async()=>{const data=await request('editor-paste');return data?.image?data:null;},'Copy Image native PNG');
  check((await pixels(imagePaste.image)).width===40,'Copy Image writes an actual PNG to the native pasteboard');
  const otherCanvas=document.createElement('canvas');otherCanvas.width=13;otherCanvas.height=7;
  const otherContext=otherCanvas.getContext('2d');otherContext.fillStyle='#00ffff';otherContext.fillRect(0,0,13,7);
  await window.editor.load(`<p>Text context menu</p><img src="${png}"><img src="${otherCanvas.toDataURL('image/png')}" style="width:6px">`);
  await Promise.all([...doc().images].map(image=>image.decode()));
  const beforeImageCopy=window.editor.html(),imageMenu=document.querySelector('.image-actions');
  for(const [name,options,readOnly] of [
    ['Right-click',{button:2},false],['Control-click',{button:0,ctrlKey:true},false],['Read-only right-click',{button:2},true]
  ]){
    window.editor.setReadOnly(readOnly);doc().images[0].click();
    const target=doc().images[1],bounds=target.getBoundingClientRect();
    const event=new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:bounds.left+2,clientY:bounds.top+2,...options});
    target.dispatchEvent(event);
    check(event.defaultPrevented&&imageMenu.matches(':popover-open')&&!imageMenu.querySelector('[data-image-action=copy]').disabled&&target.hasAttribute('data-sin-selected')&&!doc().images[0].hasAttribute('data-sin-selected'),name+' opens Copy Image for the clicked image instead of the previous selection');
    if(readOnly)check(['edit','resize','rename','delete'].every(action=>imageMenu.querySelector(`[data-image-action=${action}]`).disabled),'Read-only image menus allow copying while disabling edits');
    await request('editor-copy',{html:'<p>Reset</p>',text:'Reset'});imageMenu.querySelector('[data-image-action=copy]').click();
    const copiedImage=await until(async()=>{const data=await request('editor-paste');return data?.image?data.image:null;},name+' image copy');
    const copiedPixels=await pixels(copiedImage);
    check(copiedPixels.width===13&&copiedPixels.height===7&&exactColor(copiedPixels,[0,255,255,255]),name+' copies the clicked image at its original size and exact colors');
  }
  window.editor.setReadOnly(false);doc().images[0].click();
  const textContext=new MouseEvent('contextmenu',{bubbles:true,cancelable:true,button:2});doc().querySelector('p').dispatchEvent(textContext);
  check(!textContext.defaultPrevented&&!imageMenu.matches(':popover-open'),'Text right-click retains its standard menu and dismisses stale image actions');
  check(window.editor.html()===beforeImageCopy,'Image context menus and clipboard copying leave document contents unchanged');
  await runCellTests(check,png,palette);
  await runAnnotationTests(check,png);
  delete window.__combineExecuted;delete window.__clearExecuted;
}

async function runCellTests(check,png,palette){
  const image={id:'cells',type:'embedded-image',name:'Four cells',source:png,x:0,y:0,width:40,height:20,visible:true,sliceDividers:[.5],sliceRowDividers:[.5]};
  check(sliceCellCount(image)===4&&sliceBounds(image,3).x===20&&sliceBounds(image,3).y===10,'Image cell grid uses row-major ordering and both divider axes');
  for(const axis of ['x','y'])for(const size of [1,2,7]){
    const object={...image,width:axis==='x'?size:40,height:axis==='y'?size:20,sliceDividers:axis==='x'?[.1,.1025,.75]:[],sliceRowDividers:axis==='y'?[.1,.1025,.75]:[]};
    const valid=()=>{const cells=Array.from({length:sliceCellCount(object)},(_,i)=>sliceBounds(object,i)),dimension=axis==='x'?'width':'height';return cells.every((cell,i)=>cell[dimension]>0&&(!i||cell[axis]===cells[i-1][axis]+cells[i-1][dimension]))&&cells.reduce((total,cell)=>total+cell[dimension],0)===size;};
    moveSliceDivider(object,0,-1000,axis);const left=valid();moveSliceDivider(object,0,1000,axis);
    check(left&&valid(),`${axis} dividers stay contiguous and nonempty after resizing to ${size} pixels`);
  }
  const untouched=JSON.stringify(image);let progress=0;
  const cells=await createSliceImages(image,(done,total)=>{progress=done/total;},new AbortController().signal);
  const rendered=await Promise.all(cells.map(cell=>pixels(cell.source)));
  check(rendered.every((cell,index)=>cell.width===20&&cell.height===10&&exactColor(cell,palette[index]))&&progress===1&&JSON.stringify(image)===untouched,'Separate cells retain exact source pixels, row order and dimensions without guide graphics or source mutation');
  const aborted=new AbortController();aborted.abort();check(await createSliceImages(image,()=>{},aborted.signal)===null,'Canceled cell creation returns no partial replacement');
  const locked={...image,locked:true};setSliceCount(locked,3);moveSliceDivider(locked,0,4);check(locked.sliceDividers[0]===.5,'Locked images protect divider metadata');
  await copySlice(image,2);const copied=await request('editor-paste');check(exactColor(await pixels(copied.image),palette[2]),'Copy selected cell produces the exact row and column PNG on NSPasteboard');
  let writes=[],ends=0;
  const responder=message=>{
    if(message.type==='slice-export-begin')return 'isolated-cell-test';
    if(message.type==='slice-export-write'){writes.push(message);return null;}
    ends++;return {saved:writes.length,total:4,folder:'/isolated/cell-test'};
  };
  await withSliceBridge(responder,async()=>{
    const result=await saveAllSlices(image,()=>{},new AbortController().signal),outputs=await Promise.all(writes.map(write=>pixels(write.data)));
    check(result.saved===4&&ends===1&&writes.every((write,index)=>write.index===index&&write.token==='isolated-cell-test')&&outputs.every((output,index)=>exactColor(output,palette[index])),'Save All sends exact row-major PNGs through one native export session and closes it');
  });
  writes=[];ends=0;const stop=new AbortController();
  await withSliceBridge(responder,async()=>{
    const result=await saveAllSlices(image,done=>{if(done===1)stop.abort();},stop.signal);
    check(result.saved===1&&writes.length===1&&ends===1,'Stopping Save All finalizes the native session and reports the completed cell count');
  });
  writes=[];ends=0;
  await withSliceBridge(message=>{if(message.type==='slice-export-write'&&message.index===1)throw Error('Write fixture failed');return responder(message);},async()=>{
    let error='';try{await saveAllSlices(image,()=>{},new AbortController().signal);}catch(failure){error=failure.message;}
    check(ends===1&&error.includes('Write fixture failed')&&error.includes('1 of 4 cells saved'),'A slice write failure closes the session and reports successful partial output');
  });
  await withSliceBridge(message=>{if(message.type==='slice-export-begin')return null;throw Error('Canceled chooser must not write');},async()=>{
    check(await saveAllSlices(image,()=>{},new AbortController().signal)===null,'Canceling the slice destination creates no output session');
  });
  const session=annotate({version:1,width:40,height:20,background:'none',objects:[image]});let dialog;
  try{
    dialog=await until(()=>document.querySelector('dialog.annotation'),'cell dialog');dialog.querySelector('[data-action=slice]').click();
    check(dialog.querySelectorAll('[data-slice-cell]').length===4&&dialog.querySelector('#sliceCell').options[3].textContent.includes('Row 2, Col 2'),'Image Cells exposes selectable row and column labels');
    dialog.querySelector('#sliceCell').value='3';dialog.querySelector('#sliceCell').dispatchEvent(new Event('change',{bubbles:true}));
    await request('editor-copy',{html:'<p>Reset</p>',text:'Reset'});window.editor.command('copy');
    const cellCopy=await until(async()=>{const data=await request('editor-paste');return data?.image?data:null;},'AppKit selected cell Copy');
    check(exactColor(await pixels(cellCopy.image),palette[3])&&!document.querySelector('dialog.form-dialog'),'AppKit Copy targets the selected image cell without opening an object-format dialog');
    await until(()=>dialog.querySelector('#sliceProgress').hidden,'cell clipboard operation');
    writes=[];ends=0;
    await withSliceBridge(responder,async()=>{
      dialog.querySelector('[data-action=saveAllSlices]').click();
      check(!dialog.querySelector('#sliceProgress').hidden&&dialog.querySelector('[data-action=saveAllSlices]').disabled,'Save All UI reports progress and blocks a second concurrent export');
      await until(()=>dialog.querySelector('#sliceStatus').textContent.startsWith('Saved 4 of 4'),'slice UI completion');
      check(ends===1&&dialog.querySelector('#sliceProgress').hidden,'Save All UI restores controls after completing the native export session');
    });
    dialog.querySelector('[data-action=createSliceImages]').click();
    check(!dialog.querySelector('#sliceProgress').hidden&&dialog.querySelector('[data-action=apply]').disabled,'Cell creation reports progress and prevents overlapping Apply');
    await until(()=>dialog.querySelectorAll('[data-layer]').length===5,'separate image layers');
    check(dialog.querySelector('#canvas image').getAttribute('href')===png&&!dialog.querySelector('[data-slice-overlay]'),'Create Separate Images retains the original and selects editable copies');
    dialog.querySelector('[data-action=undo]').click();check(dialog.querySelectorAll('[data-layer]').length===1,'Creating all separate cells is one Undo step');
    dialog.querySelector('[data-action=redo]').click();dialog.querySelector('[data-action=apply]').click();const result=await session;
    check(result.state.objects.length===5&&result.state.objects.slice(1).every((object,index)=>object.name.includes(`Row ${Math.floor(index/2)+1}, Column ${index%2+1}`)&&!object.locked),'Separate image layers survive Apply with editable geometry and row/column names');
  }finally{if(dialog?.open)dialog.close('cancel');await session;}
}

async function runAnnotationTests(check,png){
  const initial={version:1,width:260,height:180,background:'none',objects:[
    {id:'locked-image',type:'embedded-image',name:'Image',source:png,x:0,y:0,width:80,height:40,visible:true,imageClip:{x:5,y:5,width:60,height:30}},
    {id:'box',type:'rectangle',name:'Box',x:100,y:60,width:50,height:30,visible:true,fill:'#aabbcc',stroke:'none',strokeWidth:0}
  ]};
  const session=annotate(initial);let dialog;
  try{
    dialog=await until(()=>document.querySelector('dialog.annotation'),'annotation parity dialog');
    const $=selector=>dialog.querySelector(selector),click=selector=>$(selector).click();
    const select=(id,shift=false)=>$(`[data-layer="${id}"]`).dispatchEvent(new MouseEvent('click',{bubbles:true,shiftKey:shift}));
    const key=(key,metaKey=false)=>$('#canvas').dispatchEvent(new KeyboardEvent('keydown',{key,metaKey,bubbles:true,cancelable:true}));
    const change=(selector,value)=>{const input=$(selector);input.value=String(value);input.dispatchEvent(new Event('change',{bubbles:true}));};
    click('[data-action=applyCrop]');click('[data-action=lock]');await until(()=>!$('.annotation-error').textContent,'stale crop completion');
    check($('#canvas [data-object="locked-image"]').dataset.locked==='true'&&$('#canvas image').getAttribute('href')===png&&$('[data-action=applyCrop]').disabled,'Locking during asynchronous crop rejects the stale result');
    change('[data-geometry=x]',90);change('#opacity',20);key('ArrowRight');key('Delete');click('[data-action=resetAllCrops]');
    check($('#canvas image').getAttribute('x')==='0'&&$('#canvas [data-object="locked-image"]').getAttribute('opacity')==='1'&&$('[data-geometry=x]').disabled&&!$('#canvas [data-handle]'),'Locked annotations ignore geometry, appearance, keyboard and crop mutations');
    select('box',true);key('ArrowRight');change('#opacity',50);
    check($('#canvas [data-object="box"] rect').getAttribute('x')==='101'&&$('#canvas [data-object="box"]').getAttribute('opacity')==='0.5'&&$('#canvas image').getAttribute('x')==='0','Mixed-selection movement and styling modify only unlocked layers');
    const context=()=>{const node=$('[data-layer="locked-image"]'),bounds=node.getBoundingClientRect();node.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:bounds.left+5,clientY:bounds.top+5}));};
    context();check($('.annotation-menu').matches(':popover-open')&&dialog.querySelectorAll('.layer.selected').length===2,'Annotation context menu retains an existing multi-selection');
    for(const format of ['svg','png']){
      await request('editor-copy',{html:'<p>Reset</p>',text:'Reset'});
      if(!$('.annotation-menu').matches(':popover-open'))context();click(`[data-annotation-command=${format}]`);
      await until(async()=>{const value=await request('annotation-paste');return value?.objects&&JSON.parse(value.objects).objects.length===2;},'direct annotation '+format+' copy');
      check(!document.querySelector('dialog.form-dialog'),'Direct context '+format.toUpperCase()+' copy preserves editable objects without another format dialog');
    }
    context();$('.annotation-menu').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
    check(dialog.open&&!$('.annotation-menu').matches(':popover-open'),'Escape dismisses annotation context menu without closing the editor');
    key('Delete');check(dialog.querySelectorAll('[data-layer]').length===1,'Deleting a mixed selection keeps locked layers');click('[data-action=undo]');
    select('locked-image');click('[data-action=duplicate]');check(dialog.querySelectorAll('[data-layer]').length===3&&$('#canvas [data-object="'+$('.layer.selected').dataset.layer+'"]').dataset.locked==='false','Duplicating a locked annotation creates an unlocked copy');click('[data-action=undo]');
    select('locked-image');click('[data-action=unlock]');check(!$('#geometry input').disabled&&$('#canvas [data-handle]'),'Unlock restores annotation edit controls');click('[data-action=undo]');check($('#geometry input').disabled,'Annotation locking supports Undo');
    const viewport=$('.canvas-viewport');
    // Synthetic events have no OS pointer capture. Their geometry and all app
    // listeners still run in WebKit; scoped shims affect only this test dialog.
    viewport.setPointerCapture=()=>{};viewport.hasPointerCapture=()=>false;viewport.releasePointerCapture=()=>{};
    const draw=(x,y,toX,toY,shiftKey=false)=>{
      const point=(a,b)=>new DOMPoint(a,b).matrixTransform($('#canvas').getScreenCTM());
      for(const [type,p] of [['pointerdown',point(x,y)],['pointermove',point(toX,toY)],['pointerup',point(toX,toY)]])$('#canvas').dispatchEvent(new PointerEvent(type,{bubbles:true,cancelable:true,button:0,pointerId:1,clientX:p.x,clientY:p.y,shiftKey}));
    };
    for(const tool of ['arrow','line','rectangle','circle','text']){
      click(`[data-tool=${tool}]`);draw(10,90,50,120,true);draw(80,100,120,140);
      check($(`[data-tool=${tool}]`).classList.contains('active')&&dialog.querySelectorAll('[data-layer]').length===4&&!$('#canvas [data-handle]'),'Drawing '+tool+' twice preserves the active tool and hides edit handles');
      if(tool==='line'){const lines=[...dialog.querySelectorAll('#canvas [data-object] line')];check(lines.some(line=>line.getAttribute('y1')===line.getAttribute('y2')),'Shift-drawing a line constrains it to a horizontal or vertical axis');}
      click('[data-action=undo]');click('[data-action=undo]');
    }
    click('[data-action=apply]');const result=await session;
    check(result.state.objects.find(object=>object.id==='locked-image').locked===true,'Annotation Apply serializes persistent object locks');
  }finally{if(dialog?.open)dialog.close('cancel');await session;}
}
