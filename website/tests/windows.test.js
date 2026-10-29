import test from 'node:test';
import assert from 'node:assert/strict';
import { clampFrame, isDemoShortcut, nextDemoSlot, canDrift } from '../windows-geometry.js';
test('frames fit narrow viewports and retain document position', () => {
  assert.deepEqual(clampFrame({x:900,y:1200,width:420,height:300},{width:320,height:2000}),{x:8,y:1200,width:304,height:300});
  assert.deepEqual(clampFrame({x:-20,y:-40,width:200,height:150},{width:1000,height:800}),{x:8,y:8,width:200,height:150});
});
test('viewport collision includes scroll offset during dragging', () => {
  assert.equal(clampFrame({x:0,y:1600,width:200,height:150},{width:1000,height:800,top:500}).y,1142);
});
test('shortcut ignores repeats, composition and editable fields', () => {
  const event={metaKey:true,shiftKey:true,key:'V',target:{closest:()=>null}};
  assert.equal(isDemoShortcut(event),true);
  for(const props of [{repeat:true},{isComposing:true},{altKey:true},{ctrlKey:true},{target:{closest:()=>({})}}]) assert.equal(isDemoShortcut({...event,...props}),false);
});
test('demo windows reuse bounded slots and drift respects lifecycle', () => {
  assert.deepEqual(Array.from({length:8},(_,i)=>nextDemoSlot(i,3)),[0,1,2,0,1,2,0,1]);
  assert.equal(canDrift({interacted:false,reduced:false,hidden:false,suspended:false}),true);
  for(const flag of ['interacted','reduced','hidden','suspended']) assert.equal(canDrift({[flag]:true}),false);
});
