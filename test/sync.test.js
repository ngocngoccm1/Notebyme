import test from 'node:test';
import assert from 'node:assert/strict';
import { NotesStore } from '../assets/notes-store.js';
import { synchronize } from '../assets/sync.js';
const memory = () => { const rows = new Map(); return { getItem: k => rows.get(k), setItem: (k, v) => rows.set(k, v), removeItem: k => rows.delete(k) }; };
const deferred = () => { let resolve; const promise = new Promise(r => resolve = r); return { promise, resolve }; };

test('editing while an upload is in flight keeps the latest edit dirty', async () => {
  const store = new NotesStore('user-a', memory());
  const note = store.create(); store.update(note.id, { body: 'before' });
  const entered = deferred(), uploaded = deferred(); let remote;
  const sync = synchronize(store, async (path, options) => {
    if (options?.method === 'PUT') { remote = structuredClone(options.data.notes); entered.resolve(); await uploaded.promise; return { saved: [note.id] }; }
    return { notes: remote };
  }, () => true);
  await entered.promise; store.update(note.id, { body: 'edited while saving' }); uploaded.resolve(); await sync;
  assert.equal(store.notes[0].body, 'edited while saving'); assert.equal(store.notes[0].dirty, true);
});

test('switching account while downloading does not merge or persist the old response', async () => {
  const storage = memory(); const a = new NotesStore('a', storage), b = new NotesStore('b', storage);
  const entered = deferred(), downloaded = deferred(); let current = a; let saves = 0;
  const sync = synchronize(a, async () => { entered.resolve(); return await downloaded.promise; }, () => current === a, () => saves++);
  await entered.promise; current = b;
  downloaded.resolve({ notes: [{ id: 'private-a', title: '', body: 'secret', deleted: false, updated_at: new Date().toISOString() }] });
  assert.equal(await sync, false); assert.equal(saves, 0); assert.deepEqual(b.notes, []); assert.deepEqual(a.notes, []);
});

test('partial remote response does not remove locally cached clean notes', () => {
  const store = new NotesStore('a', memory()); const note = store.create();
  store.acknowledge(store.snapshot()); store.merge([]);
  assert.equal(store.notes[0].id, note.id);
});

test('quota failure is reported rather than treated as a successful local save', () => {
  const store = new NotesStore('a', { getItem: () => null, setItem() { throw new Error('quota'); } });
  store.create(); assert.equal(store.persist(), false); assert.equal(store.notes.length, 1);
});
