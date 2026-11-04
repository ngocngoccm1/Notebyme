const fields = note => ({ id: note.id, title: note.title, body: note.body, updated_at: note.updated_at, deleted: note.deleted });
const valid = note => note && typeof note.id === 'string' && typeof note.title === 'string' && typeof note.body === 'string' && typeof note.updated_at === 'string' && Number.isFinite(Date.parse(note.updated_at)) && typeof note.deleted === 'boolean';

export class NotesStore {
  constructor(userId, storage = globalThis.localStorage) {
    this.userId = userId;
    this.storage = storage;
    this.key = `tiny-notes-v2-${userId}`;
    this.notes = [];
    try {
      const raw = storage.getItem(this.key) || storage.getItem(`tiny-notes-v1-${userId}`) || '[]';
      const rows = JSON.parse(raw);
      if (Array.isArray(rows)) this.notes = rows.filter(valid).map(n => ({ ...fields(n), dirty: n.dirty === true, revision: Number(n.revision) || 0 }));
    } catch { /* A malformed cache never breaks login. */ }
  }
  persist() {
    try { this.storage.setItem(this.key, JSON.stringify(this.notes)); return true; } catch { return false; }
  }
  create() {
    const note = { id: crypto.randomUUID(), title: '', body: '', updated_at: new Date().toISOString(), deleted: false, dirty: true, revision: 1 };
    this.notes.unshift(note);
    return note;
  }
  update(id, changes) {
    const note = this.notes.find(n => n.id === id);
    if (!note) return;
    Object.assign(note, changes, { updated_at: new Date().toISOString(), dirty: true, revision: note.revision + 1 });
  }
  snapshot() { return this.notes.filter(n => n.dirty).map(n => ({ note: fields(n), revision: n.revision })); }
  acknowledge(snapshot) {
    for (const sent of snapshot) {
      const current = this.notes.find(n => n.id === sent.note.id);
      if (current?.revision === sent.revision) current.dirty = false;
    }
  }
  merge(rows) {
    const remote = new Map(rows.filter(valid).map(n => [n.id, { ...fields(n), dirty: false, revision: 0 }]));
    // Absence from a response is never interpreted as deletion. Deleted rows
    // travel as explicit tombstones, including during paginated downloads.
    for (const local of this.notes) if (local.dirty || !remote.has(local.id)) remote.set(local.id, local);
    this.notes = [...remote.values()];
  }
  clear() {
    this.storage.removeItem(this.key);
    this.storage.removeItem(`tiny-notes-v1-${this.userId}`);
  }
}

export function batches(snapshot) {
  const result = [];
  let batch = [], bytes = 32;
  for (const item of snapshot) {
    const size = new TextEncoder().encode(JSON.stringify(item.note)).length + 1;
    if (batch.length && (batch.length >= 20 || bytes + size > 900000)) { result.push(batch); batch = []; bytes = 32; }
    batch.push(item); bytes += size;
  }
  if (batch.length) result.push(batch);
  return result;
}
