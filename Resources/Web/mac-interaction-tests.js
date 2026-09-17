import {request} from './bridge.js';
import {annotate} from './annotation-ui.js';
import {setCropInsets,setCornerRadii,resetCrop,applyCrop} from './annotation-crop.js';
import {imageClip} from './annotation-model.js';
import {runContentTests} from './content-self-test.js';

const tick=()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
async function until(predicate,label){
  const deadline=performance.now()+5000;
  while(performance.now()<deadline){const value=await predicate();if(value)return value;await new Promise(resolve=>setTimeout(resolve,20));}
  throw Error('Timed out: '+label);
}

export async function runInteractionTests(check,scene,png){
  const doc=()=>document.querySelector('#document').contentDocument;
  const click=selector=>{const control=document.querySelector(selector);if(!control)throw Error('Missing control: '+selector);control.click();};
  const select=selector=>{
    const range=doc().createRange();range.selectNodeContents(doc().querySelector(selector));
    doc().body.focus();doc().getSelection().removeAllRanges();doc().getSelection().addRange(range);doc().dispatchEvent(new Event('selectionchange'));
  };
  await runContentTests(check);
  await window.editor.load('<p id="sample">Style reference sample</p><p id="after">Other paragraph</p>');
  check(document.querySelectorAll('.style-strip [data-style]').length===5,'Ribbon offers all five Modern paragraph styles');
  check(document.querySelector('[data-cmd=copy]').title.includes('⌘')&&document.querySelector('[data-cmd=redo]').title.includes('⇧⌘Z'),'Ribbon exposes Mac copy and redo shortcuts');
  for(const [style,points] of [['normal',12],['no-spacing',12],['heading',22],['heading2',18],['title',34]]){
    select('#sample');click(`.style-strip [data-style="${style}"]`);
    const block=doc().querySelector('#sample');
    check(block.dataset.sinStyle===style&&Math.abs(parseFloat(doc().defaultView.getComputedStyle(block).fontSize)-points*4/3)<.1&&doc().querySelector('#after').textContent==='Other paragraph',style+' preset applies correct points without changing the next paragraph');
  }
  select('#sample');click('#fontColorOptions');
  check(document.querySelectorAll('.color-palette > .palette-grid .swatch').length===70,'Office color palette has 70 theme and standard swatches');
  click('.color-palette [data-color="#e97132"]');
  check(doc().querySelector('#sample').innerHTML.includes('233, 113, 50')&&!document.querySelector('.color-palette'),'Palette applies color to saved text selection and closes');
  select('#after');click('#highlightOptions');click('.color-palette [data-color="#92d050"]');
  check(doc().querySelector('#after').innerHTML.includes('146, 208, 80')&&doc().getSelection().isCollapsed,'Highlight preserves text and collapses the caret');
  select('#sample');const size=document.querySelector('#fontSize');size.value='18';size.dispatchEvent(new Event('change'));await tick();click('#growFont');await tick();
  check(doc().querySelector('#sample').innerHTML.includes('20pt'),'Grow Font advances to the next point size');
  click('#shrinkFont');await tick();check(doc().querySelector('#sample').innerHTML.includes('18pt'),'Shrink Font returns to the previous point size');
  const toolbar=document.querySelector('#toolbar'),width=toolbar.style.width;
  try{
    toolbar.style.width='480px';window.editor.setToolbarWrap(false);await tick();
    check(!document.querySelector('#moreRibbon').hidden&&!!document.querySelector('.ribbon-overflow #link'),'Narrow ribbon moves tools into overflow');
    click('#moreRibbon');check(!!document.querySelector('.ribbon-overflow:popover-open'),'WebKit opens native popover ribbon overflow');
  }finally{window.editor.setToolbarWrap(true);toolbar.style.width=width;await tick();}

  const image={id:'crop-image',type:'embedded-image',source:png.data,x:0,y:0,width:120,height:70,visible:true};
  setCropInsets(image,{top:5,left:10,right:20,bottom:15});setCornerRadii(image,'topLeft',8,true);
  check(imageClip(image).width===90&&imageClip(image).height===50&&Object.values(image.cropCornerRadii).every(value=>value===8),'Reversible crop and synchronized corner radii retain source geometry');
  const baked=await applyCrop(image);
  check(baked.width===90&&baked.height===50&&!baked.imageClip&&!baked.cropCornerRadii&&baked.source!==png.data,'Permanent crop bakes pixels and clears reversible metadata');
  resetCrop(image);check(imageClip(image).width===120&&!image.cropCornerRadii,'Reset Crop restores complete source bounds');

  const originalTemplates=await request('templates-load');
  const underlying=window.editor.html();
  let annotation;
  try{
    annotation=annotate(scene);
    const dialog=await until(()=>document.querySelector('dialog.annotation'),'annotation dialog');
    const layers=()=>dialog.querySelectorAll('[data-layer]').length;
    check(dialog.open&&dialog.querySelectorAll('.color-picker').length===4&&dialog.querySelector('[data-action=undo]').title.includes('⌘'),'Annotation opens all four palettes with Mac shortcuts');
    click('dialog.annotation [data-layer]');
    const keyboard=(key,shiftKey=false)=>dialog.dispatchEvent(new KeyboardEvent('keydown',{key,metaKey:true,shiftKey,bubbles:true,cancelable:true}));
    keyboard('d');check(layers()===2,'Command-D duplicates a selected annotation object');
    keyboard('z');check(layers()===1,'Command-Z undoes annotation duplication');
    keyboard('z',true);check(layers()===2,'Shift-Command-Z redoes annotation duplication');
    window.editor.command('undo');check(layers()===1,'AppKit Undo command targets the annotation modal');
    window.editor.command('redo');check(layers()===2&&window.editor.html()===underlying,'AppKit Redo targets annotation without editing the underlying document');
    click('dialog.annotation [data-layer]');
    const x=dialog.querySelector('[data-geometry=x]');x.value='80';x.dispatchEvent(new Event('change',{bubbles:true}));
    check(dialog.querySelector('[data-geometry=x]').value==='80','Annotation inspector updates selected object geometry');
    keyboard('c');await until(()=>document.querySelector('dialog.form-dialog [value=svg]'),'annotation clipboard choice');
    click('dialog.form-dialog [value=svg]');
    const copied=await until(async()=>{const value=await request('annotation-paste');return value?.objects&&JSON.parse(value.objects).objects?.[0]?.x===0?value:null;},'editable clipboard objects');
    check(JSON.parse(copied.objects).objects[0].type==='rectangle','Native SVG clipboard also retains editable annotation JSON');
    keyboard('v');await until(()=>layers()===3,'paste annotation object');
    check(layers()===3,'Command-V pastes an editable object from NSPasteboard');
    click('dialog.annotation [data-action=saveTemplate]');await until(()=>document.querySelector('dialog.form-dialog [name=name]'),'template name dialog');
    document.querySelector('dialog.form-dialog [name=name]').value='Mac smoke-test object';click('dialog.form-dialog [value=ok]');
    const templateButton=await until(()=>[...dialog.querySelectorAll('[data-template]')].find(button=>button.textContent==='Mac smoke-test object'),'saved template');
    templateButton.click();check(layers()===4,'Saved object template inserts another editable object');
    click('dialog.annotation [data-action=apply]');
    const applied=await annotation;annotation=null;
    check(applied.state.objects.length===4&&applied.data.startsWith('data:image/png;base64,'),'Apply returns all editable layers and a lossless PNG');
  }finally{
    document.querySelector('dialog.form-dialog')?.close('cancel');
    document.querySelector('dialog.annotation')?.close('cancel');
    if(annotation)await annotation;
    await request('templates-save',{templates:originalTemplates||[]});
  }
}
