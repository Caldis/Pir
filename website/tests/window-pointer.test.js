import test from 'node:test';
import assert from 'node:assert/strict';
import { createPointerOwner } from '../window-pointer.js';
function fixture() {
  const captures = new Set();
  const releases = [];
  const item = {element:{setPointerCapture:id=>captures.add(id),hasPointerCapture:id=>captures.has(id),releasePointerCapture:id=>{releases.push(id);captures.delete(id);}}};
  let clears=0;
  const owner=createPointerOwner(()=>clears++);
  return {owner,item,captures,releases,get clears(){return clears;}};
}
test('a second touch cannot replace the captured pointer or move its window',()=>{
  const f=fixture(),other=fixture();
  const first={item:f.item,id:7,start:{x:20}};
  assert.equal(f.owner.begin(first),true);
  assert.equal(f.owner.begin({item:other.item,id:8}),false);
  assert.equal(f.owner.active,first);
  assert.equal(f.owner.matches(f.item,8),false);
  assert.equal(f.owner.matches(other.item,7),false);
  assert.equal(f.owner.matches(f.item,7),true);
});
test('foreign pointerup or cancel cannot end the owner gesture',()=>{
  const f=fixture(),other=fixture();f.owner.begin({item:f.item,id:7});
  assert.equal(f.owner.end(other.item,7),false);
  assert.equal(f.owner.end(f.item,8),false);
  assert.equal(f.owner.active.id,7);
  assert.equal(f.clears,0);
  assert.equal(f.owner.end(f.item,7),true);
  assert.equal(f.owner.active,undefined);
  assert.deepEqual(f.releases,[7]);
  assert.equal(f.clears,1);
});
test('blur or resize cancellation releases capture before accepting a new pointer',()=>{
  const f=fixture();f.owner.begin({item:f.item,id:7});
  f.item.element.releasePointerCapture=id=>{assert.equal(f.owner.active,undefined);f.releases.push(id);f.captures.delete(id);};
  f.owner.cancel();
  assert.deepEqual(f.releases,[7]);assert.equal(f.captures.size,0);assert.equal(f.clears,1);
  assert.equal(f.owner.begin({item:f.item,id:9}),true);
  f.captures.delete(9); // lostpointercapture already released the native capture.
  assert.equal(f.owner.end(f.item,9),true);
  assert.deepEqual(f.releases,[7]);assert.equal(f.clears,2);
});
