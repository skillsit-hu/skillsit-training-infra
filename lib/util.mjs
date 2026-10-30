import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const repoDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CONFIG_FILE = 'config/main-config.json';

export function die(message) {
  console.error(message);
  process.exit(1);
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function run(cmd, args, { env, cwd, input, quiet = false, capture = false, check = false } = {}) {
  const result = spawnSync(cmd, args, {
    cwd,
    env: { ...process.env, ...env },
    input,
    encoding: 'utf8',
    stdio: [input === undefined ? 'inherit' : 'pipe', capture || quiet ? 'pipe' : 'inherit', quiet ? 'pipe' : 'inherit'],
  });
  if (result.error) {
    if (check) die(`Failed to run ${cmd}: ${result.error.message}`);
    console.error(`Failed to run ${cmd}: ${result.error.message}`);
  } else if (check && result.status !== 0) {
    die(`Command failed (${result.status}): ${cmd} ${args.join(' ')}`);
  }
  return { ok: !result.error && result.status === 0, stdout: result.stdout ?? '' };
}

function shQuote(value) {
  return `'${String(value).replaceAll("'", `'\\''`)}'`;
}

export function giteaCli(args, opts) {
  const command = ['/app/gitea/gitea', ...args].map(shQuote).join(' ');
  return run('docker', ['exec', 'gitea', 'su', '-c', command, 'git'], opts);
}

export function readConfigFile() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  } catch (err) {
    die(`Could not read ${CONFIG_FILE}: ${err.message}`);
  }
}

export function loadConfig() {
  const config = readConfigFile();
  const https = config.enableHttps === true || config.enableHttps === 'true';
  return {
    domain: config.domain,
    enableHttps: String(https),
    username: config.username,
    password: config.password,
    modules: config.modules ?? [],
    competitors: config.competitors ?? [],
    entrypoint: https ? 'websecure' : 'web',
    protocol: https ? 'https' : 'http',
    registryPort: https ? '443' : '5000',
  };
}

// Pulldeck is served at clara.<domain> (see pulldeck.yaml) and checks AUTH_TOKEN from .env.clara
export function readPulldeckToken() {
  let contents = '';
  try {
    contents = fs.readFileSync('.env.clara', 'utf8');
  } catch {
    // handled below
  }
  const line = contents.split(/\r?\n/).find((l) => l.startsWith('AUTH_TOKEN='));
  const token = line?.slice('AUTH_TOKEN='.length).trim();
  if (!token) die('AUTH_TOKEN not found in .env.clara');
  return token;
}
