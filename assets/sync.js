import { batches } from './notes-store.js';

export async function synchronize(local, api, isCurrent, saved = () => {}) {
  for (const batch of batches(local.snapshot())) {
    await api('/notes', { method: 'PUT', data: { notes: batch.map(item => item.note) } });
    if (!isCurrent()) return false;
    local.acknowledge(batch); saved();
  }
  const remote = await api('/notes');
  if (!isCurrent()) return false;
  local.merge(remote.notes); saved();
  return true;
}
