// shared/serviceRegistry.js
const fs = require('fs-extra');
const path = require('path');
const axios = require('axios');

const REGISTRY_PATH = path.join(__dirname, '_registry.json');

const CHECK_INTERVAL_MS = 30_000; // 30s entre health checks
const FAIL_OPEN_AFTER = 3;        // 3 falhas seguidas marca como unhealthy
const INSTANCE_TTL_MS = 5 * 60_000; // 5 min sem heartbeat => remover

// Estado em memória (cada processo mantém o seu, mas persistimos em arquivo p/ compartilhamento)
let memory = {
  services: {
    // name: [{ url, healthy, fails, lastSeen, lastOk, meta }]
  },
  updatedAt: new Date().toISOString()
};

// Util: carrega o JSON do disco (se existir)
async function load() {
  try {
    if (await fs.pathExists(REGISTRY_PATH)) {
      const data = await fs.readJson(REGISTRY_PATH);
      if (data && data.services) memory = data;
    } else {
      await persist();
    }
  } catch (e) {
    console.warn('[registry] falha ao carregar arquivo:', e.message);
  }
}

// Util: salva o JSON no disco (atomicamente)
async function persist() {
  memory.updatedAt = new Date().toISOString();
  await fs.outputJson(REGISTRY_PATH, memory, { spaces: 2 });
}

// Normaliza chave do serviço
const key = (name) => String(name || '').trim().toLowerCase();

// Busca lista de instâncias de um serviço
function getList(name) {
  const k = key(name);
  memory.services[k] ||= [];
  return memory.services[k];
}

// Adiciona ou atualiza instância
async function register(name, url, meta = {}) {
  await load();
  const list = getList(name);
  const now = Date.now();

  const idx = list.findIndex(i => i.url === url);
  if (idx >= 0) {
    // heartbeat/update
    list[idx] = {
      ...list[idx],
      healthy: true,
      fails: 0,
      lastSeen: now,
      lastOk: now,
      meta: { ...list[idx].meta, ...meta }
    };
  } else {
    list.push({
      url,
      healthy: true,
      fails: 0,
      lastSeen: now,
      lastOk: now,
      meta
    });
  }
  await persist();
  return true;
}

async function deregister(name, url) {
  await load();
  const list = getList(name);
  const next = list.filter(i => i.url !== url);
  memory.services[key(name)] = next;
  await persist();
  return true;
}

// Escolhe uma instância saudável (round-robin simples baseado em lastOk)
async function lookup(name) {
  await load();
  const list = getList(name).filter(i => i.healthy);
  if (list.length === 0) return null;
  // escolhe a mais “antiga” em lastOk para balancear
  list.sort((a, b) => (a.lastOk || 0) - (b.lastOk || 0));
  return list[0].url;
}

// Retorna o conteúdo do registry (para /registry do gateway)
async function dump() {
  await load();
  return memory;
}

// Health check de uma instância
async function checkInstance(svcName, inst) {
  try {
    const { data } = await axios.get(`${inst.url}/health`, { timeout: 3000 });
    // consideramos ok se respondeu um JSON com {status:'ok'}
    const ok = data && (data.status === 'ok' || data.service);
    if (ok) {
      inst.healthy = true;
      inst.fails = 0;
      inst.lastSeen = Date.now();
      inst.lastOk = Date.now();
      return;
    }
    throw new Error('resposta inválida');
  } catch {
    inst.fails = (inst.fails || 0) + 1;
    if (inst.fails >= FAIL_OPEN_AFTER) inst.healthy = false;
  }
}

// Remove instâncias “podres” (TTL estourado)
function cleanupAged(svcName, list) {
  const now = Date.now();
  return list.filter(inst => {
    const age = now - (inst.lastSeen || 0);
    return age <= INSTANCE_TTL_MS; // mantém só quem foi visto nos últimos X min
  });
}

// Loop de health checks (rodará em cada processo que importar este módulo)
let timerStarted = false;
async function startBackgroundChecks() {
  if (timerStarted) return;
  timerStarted = true;

  await load();

  setInterval(async () => {
    try {
      await load(); // traz o estado mais novo
      const names = Object.keys(memory.services || {});
      for (const n of names) {
        const list = getList(n);
        for (const inst of list) {
          await checkInstance(n, inst);
        }
        memory.services[key(n)] = cleanupAged(n, list);
      }
      await persist();
    } catch (e) {
      console.warn('[registry] health loop error:', e.message);
    }
  }, CHECK_INTERVAL_MS);
}

// Inicia os checks ao importar o módulo
startBackgroundChecks();

// Exports
module.exports = {
  register,
  deregister,
  lookup,
  dump
};
