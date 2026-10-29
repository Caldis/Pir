import { t } from './i18n.js';
import { clampFrame, isDemoShortcut, nextDemoSlot, canDrift } from './windows-geometry.js';
const art = [new URL('./assets/editorial/observatory.jpg', import.meta.url).href, new URL('./assets/editorial/sea.jpg', import.meta.url).href];
const paths = {close:'M5 5l10 10M15 5 5 15',reset:'M5 8a6 6 0 1 1-1 5M5 3v5h5',fit:'M3 7V3h4m6 0h4v4m0 6v4h-4m-6 0H3v-4',copy:'M7 7h10v10H7zM3 12V3h9',resize:'m8 17 9-9m-4 9 4-4',check:'m4 10 4 4 8-9'};
const icon = name => `<svg viewBox="0 0 20 20" aria-hidden="true"><path d="${paths[name]}"/></svg>`;
export function createWindowDemo() {
  const scene = document.querySelector('#window-scene');
  const host = document.querySelector('#demo-windows');
  document.body.append(host);
  const trigger = document.querySelector('#shortcut-demo');
  const status = document.querySelector('#demo-status');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const events = new AbortController();
  const windows = [];
  let interacted=false, suspended=false, disposed=false, count=0, z=5, gesture, drift, lastHeight=innerHeight;
  const bounds = viewport => ({width:document.documentElement.clientWidth,height:viewport ? innerHeight : document.documentElement.scrollHeight,top:viewport ? scrollY : 0});
  function paint(item, frame=item.frame) {
    item.frame=frame;
    Object.assign(item.element.style,{left:`${frame.x}px`,top:`${frame.y}px`,width:`${frame.width}px`,height:`${frame.height}px`});
  }
  function stopDrift() {interacted=true;updateDrift();}
  function updateDrift() {
    cancelAnimationFrame(drift);
    if(!canDrift({interacted,reduced:motion.matches,hidden:document.hidden,suspended}) || disposed) {
      for(const item of windows) item.element.style.transform='';
      return;
    }
    function tick(time) {
      for(const [i,item] of windows.entries()) item.element.style.transform=`translate(${Math.sin(time/3700+i*2)*3}px,${Math.cos(time/4600+i*2)*4}px)`;
      drift=requestAnimationFrame(tick);
    }
    drift=requestAnimationFrame(tick);
  }
  function focus(item) {item.element.style.zIndex=++z;}
  function reset(item) {stopDrift();paint(item,clampFrame(item.initial,bounds(false)));focus(item);}
  function announce(key) {status.textContent=t(key);}
  function control(item,name) {
    const button=document.createElement('button');button.type='button';button.dataset.action=name;button.innerHTML=icon(name);button.title=t(`demo.${name}`);button.setAttribute('aria-label',t(`demo.${name}`));
    button.addEventListener('click',async()=>{
      stopDrift();focus(item);
      if(name==='close') {item.element.hidden=true;trigger.focus();announce('demo.closed');}
      if(name==='reset') reset(item);
      if(name==='fit') {item.element.classList.toggle('image-fit');button.setAttribute('aria-pressed',String(item.element.classList.contains('image-fit')));}
      if(name==='copy') {
        try {
          if(item.type==='text') await navigator.clipboard.writeText(item.content.innerText);
          else {const response=await fetch(item.content.src);const blob=await response.blob();const bitmap=await createImageBitmap(blob);const canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;canvas.getContext('2d').drawImage(bitmap,0,0);bitmap.close();const png=await new Promise(resolve=>canvas.toBlob(resolve));await navigator.clipboard.write([new ClipboardItem({'image/png':png})]);}
          button.innerHTML=icon('check');clearTimeout(item.timer);item.timer=setTimeout(()=>button.innerHTML=icon('copy'),1200);announce('demo.copied');
        } catch {announce('demo.copyfailed');}
      }
    },{signal:events.signal});return button;
  }
  function add(type,slot=0) {
    const element=document.createElement('article');element.className=`floating-window window-${type}`;element.tabIndex=0;element.dataset.type=type;element.setAttribute('aria-label',t(`demo.${type}`));element.setAttribute('aria-describedby','window-help');
    const item={element,type};
    const toolbar=document.createElement('div');toolbar.className='window-controls';for(const name of type==='image'?['close','reset','fit','copy']:type==='text'?['close','reset','copy']:['close','reset'])toolbar.append(control(item,name));element.append(toolbar);
    const handle=document.createElement('div');handle.className='window-drag';handle.title=t('demo.move');handle.setAttribute('aria-hidden','true');element.append(handle);
    if(type==='image') {const image=document.createElement('img');image.src=art[slot%art.length];image.alt=t(slot%art.length?'demo.sea':'demo.observatory');image.draggable=false;element.append(image);item.content=image;}
    if(type==='text') {const text=document.createElement('div');text.className='note-content';text.contentEditable='true';text.setAttribute('role','textbox');text.setAttribute('aria-multiline','true');text.setAttribute('aria-label',t('demo.text'));text.innerText=t('demo.note');element.append(text);item.content=text;text.addEventListener('input',()=>item.edited=true,{signal:events.signal});}
    if(type==='files') {const files=document.createElement('div');files.className='demo-files';files.innerHTML=`<div><svg class="file-folder" viewBox="0 0 64 56" aria-hidden="true"><path d="M4 12a4 4 0 0 1 4-4h18l6 7h24a4 4 0 0 1 4 4v29H4Z"/><path d="M4 19h56"/></svg><span>Field notes</span></div><div><svg class="file-page" viewBox="0 0 48 56" aria-hidden="true"><path d="M7 3h23l11 11v39H7Z"/><path d="M30 3v12h11M14 27h20M14 33h20M14 39h13"/></svg><span>Read me.txt</span></div><div><img src="${art[1]}" alt=""><span>Blue hour.jpg</span></div>`;element.append(files);}
    const resize=document.createElement('button');resize.className='window-resize';resize.type='button';resize.innerHTML=icon('resize');resize.title=t('demo.resize');resize.setAttribute('aria-label',t('demo.resize'));element.append(resize);
    element.addEventListener('pointerdown',event=>{
      stopDrift();focus(item);
      const resizing=event.target.closest('.window-resize');
      if(!resizing && event.target.closest('button,[contenteditable]'))return;
      if(event.button!==0)return;
      event.preventDefault();element.focus({preventScroll:true});element.setPointerCapture(event.pointerId);
      item.touched=true;gesture={item,id:event.pointerId,x:event.clientX,y:event.clientY,start:{...item.frame},scroll:scrollY,resizing};element.classList.add('is-manipulating');
    },{signal:events.signal});
    element.addEventListener('pointermove',event=>{
      if(!gesture||gesture.item!==item)return;
      const dx=event.clientX-gesture.x,dy=event.clientY-gesture.y+scrollY-gesture.scroll;
      if(!gesture.resizing && (event.clientY>innerHeight-32||event.clientY<32))window.scrollBy(0,event.clientY<32?-12:12);
      const frame=gesture.resizing?{...gesture.start,width:gesture.start.width+dx,height:gesture.start.height+dy}:{...gesture.start,x:gesture.start.x+dx,y:gesture.start.y+dy};
      paint(item,clampFrame(frame,bounds(true)));
    },{signal:events.signal});
    const end=()=>{element.classList.remove('is-manipulating');gesture=undefined;};
    for(const name of ['pointerup','pointercancel','lostpointercapture'])element.addEventListener(name,end,{signal:events.signal});
    element.addEventListener('keydown',event=>{
      if(event.target.closest('[contenteditable]')||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;
      event.preventDefault();stopDrift();focus(item);item.touched=true;const delta=event.altKey?1:10;const dx=event.key==='ArrowLeft'?-delta:event.key==='ArrowRight'?delta:0;const dy=event.key==='ArrowUp'?-delta:event.key==='ArrowDown'?delta:0;
      paint(item,clampFrame(event.shiftKey||event.target===resize?{...item.frame,width:item.frame.width+dx,height:item.frame.height+dy}:{...item.frame,x:item.frame.x+dx,y:item.frame.y+dy},bounds(false)));
    },{signal:events.signal});
    host.append(element);windows.push(item);return item;
  }
  function arrange() {
    const rect=scene.getBoundingClientRect(),left=rect.left,top=rect.top+scrollY,narrow=innerWidth<760;
    const frames=narrow?[{x:left+6,y:top+8,width:Math.min(310,rect.width-12),height:222},{x:left+rect.width-230,y:top+205,width:230,height:192},{x:left+8,y:top+360,width:285,height:166}]:[{x:left+36,y:top+12,width:360,height:270},{x:left+rect.width-300,y:top+205,width:300,height:228},{x:left+5,y:top+350,width:320,height:166}];
    windows.slice(0,3).forEach((item,i)=>{item.initial=clampFrame(frames[i],bounds(false));if(!item.touched)paint(item,item.initial);});
  }
  add('image');add('text');add('files');arrange();
  function insert() {
    stopDrift();const slot=nextDemoSlot(count,3);let item=windows[slot+3];if(!item)item=add('image',count+1);item.content.src=art[(count+1)%art.length];item.content.alt=t((count+1)%art.length?'demo.sea':'demo.observatory');item.element.hidden=false;item.touched=true;item.initial=clampFrame({x:innerWidth*.38+slot*30,y:scrollY+innerHeight*.24+slot*24,width:330,height:248},bounds(true));paint(item,item.initial);focus(item);item.element.focus({preventScroll:true});count++;announce('demo.added');
  }
  trigger.addEventListener('click',insert,{signal:events.signal});
  document.addEventListener('keydown',event=>{if(isDemoShortcut(event)){event.preventDefault();insert();}},{signal:events.signal});
  document.addEventListener('pointerdown',stopDrift,{once:true,signal:events.signal});
  document.addEventListener('keydown',stopDrift,{once:true,signal:events.signal});
  window.addEventListener('scroll',stopDrift,{once:true,passive:true,signal:events.signal});
  document.addEventListener('visibilitychange',updateDrift,{signal:events.signal});
  motion.addEventListener('change',updateDrift,{signal:events.signal});
  window.addEventListener('resize',()=>{gesture=undefined;const visible=new Set(windows.filter(item=>item.touched && item.frame.y+item.frame.height>scrollY && item.frame.y<scrollY+lastHeight));arrange();for(const item of windows)paint(item,clampFrame(item.frame,bounds(visible.has(item))));lastHeight=innerHeight;},{signal:events.signal});
  document.addEventListener('pir-languagechange',()=>{for(const item of windows){if(item.type==='text'){item.content.setAttribute('aria-label',t('demo.text'));if(!item.edited)item.content.innerText=t('demo.note');}if(item.type==='image')item.content.alt=t(item.content.src===art[0]?'demo.observatory':'demo.sea');item.element.querySelector('.window-drag').title=t('demo.move');item.element.querySelector('.window-resize').title=t('demo.resize');item.element.setAttribute('aria-label',t(`demo.${item.type}`));for(const button of item.element.querySelectorAll('[data-action]')){button.title=t(`demo.${button.dataset.action}`);button.setAttribute('aria-label',button.title);}item.element.querySelector('.window-resize').setAttribute('aria-label',t('demo.resize'));}},{signal:events.signal});
  window.addEventListener('blur',()=>{gesture=undefined;for(const item of windows)item.element.classList.remove('is-manipulating');},{signal:events.signal});
  window.addEventListener('pagehide',event=>{suspended=true;updateDrift();if(!event.persisted){disposed=true;events.abort();for(const item of windows)clearTimeout(item.timer);}},{signal:events.signal});
  window.addEventListener('pageshow',()=>{suspended=false;updateDrift();},{signal:events.signal});
  updateDrift();
}
