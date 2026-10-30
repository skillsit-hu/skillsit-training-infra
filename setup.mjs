#!/usr/bin/env node
// Installs Docker (and certbot) on a fresh Debian host from Docker's official apt repository.
// Self-contained on purpose: it runs before anything else is installed, so it can't use the app/ build.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';

function run(cmd, args, { input, quiet = false, capture = false, check = false } = {}) {
  const result = spawnSync(cmd, args, {
    input,
    encoding: 'utf8',
    stdio: [input === undefined ? 'inherit' : 'pipe', capture || quiet ? 'pipe' : 'inherit', quiet ? 'pipe' : 'inherit'],
  });
  if (check && (result.error || result.status !== 0)) {
    console.error(result.error ? `Failed to run ${cmd}: ${result.error.message}` : `Command failed (${result.status}): ${cmd} ${args.join(' ')}`);
    process.exit(1);
  }
  return { ok: !result.error && result.status === 0, stdout: result.stdout ?? '' };
}

const sudo = (...args) => run('sudo', args, { check: true });

sudo('apt-get', 'update');
sudo('apt-get', 'install', '-y', 'ca-certificates', 'curl', 'git', 'sudo');
sudo('install', '-m', '0755', '-d', '/etc/apt/keyrings');
sudo('curl', '-fsSL', 'https://download.docker.com/linux/debian/gpg', '-o', '/etc/apt/keyrings/docker.asc');
sudo('chmod', 'a+r', '/etc/apt/keyrings/docker.asc');

const arch = run('dpkg', ['--print-architecture'], { capture: true, check: true }).stdout.trim();
const codename = fs.readFileSync('/etc/os-release', 'utf8').match(/^VERSION_CODENAME=(.*)$/m)?.[1].replace(/"/g, '');
const source = `deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable\n`;
run('sudo', ['tee', '/etc/apt/sources.list.d/docker.list'], { input: source, quiet: true, check: true });
sudo('apt-get', 'update');

sudo('apt-get', 'install', 'docker-ce', 'docker-ce-cli', 'containerd.io', 'docker-buildx-plugin',
  'docker-compose-plugin', 'certbot');
