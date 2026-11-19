// The env of the VM of World (the class Beam of worker.js): the vars and
// the bindings of the Worker, and the ports of the VM. Each text of this
// env is in the environment of the VM (System.get_env/0), so the secrets
// of the Worker are not in it: only the Worker uses them (handler.js,
// shift.js; docs/factory.md, "The secrets").
export const SECRETS = ['WORLD_SHIFT_TOKEN', 'WORLD_TOKEN', 'WORLD_STORE_TOKEN'];

export function vmEnv(env, ports = {}) {
  const copy = { ...env, ...ports };
  for (const name of SECRETS) delete copy[name];
  return copy;
}
