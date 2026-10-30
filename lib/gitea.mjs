import fs from 'node:fs';
import path from 'node:path';
import { die, run, sleep } from './util.mjs';

// API calls stay on the local Gitea port. The public hostname goes through
// Traefik, which can hang once the runners start.
export const GITEA_API = 'http://127.0.0.1:3000';
export const FRAMEWORK_ORG = 'frameworks';
export const COMPETITOR_TEAM = 'competitors';

// [repo name, template source]; the repo name is also the local clone directory.
export const FRAMEWORKS = [
  ['laravel', 'https://github.com/sitc2026-templates/ws26-laravel.git'],
  ['vanilla', 'https://github.com/sitc2026-templates/ws26-vanilla.git'],
  ['nuxtjs', 'https://github.com/sitc2026-templates/ws26-nuxtjs.git'],
  ['nextjs', 'https://github.com/sitc2026-templates/ws26-nextjs.git'],
  ['nextjs-prisma', 'https://github.com/sitc2026-templates/ws26-nextjs-prisma.git'],
  ['expressjs', 'https://github.com/sitc2026-templates/ws26-expressjs.git'],
  ['prisma', 'https://github.com/sitc2026-templates/ws26-prisma.git'],
  ['zurb-foundation', 'https://github.com/sitc2026-templates/ws26-zurb-foundation.git'],
  ['vuejs', 'https://github.com/sitc2026-templates/ws26-vuejs.git'],
  ['reactjs', 'https://github.com/sitc2026-templates/ws26-reactjs.git'],
  ['bootstrap', 'https://github.com/sitc2026-templates/ws26-bootstrap.git'],
  ['angular', 'https://github.com/sitc2026-templates/ws26-angular.git'],
  ['tailwindcss', 'https://github.com/sitc2026-templates/ws26-tailwindcss.git'],
];

const TOKEN_NAME = 'CreateOrganizationScript';
const WEBHOOK_SECRET = 'GFW8Mq5ANOsK';
const WORKFLOW_FILE = '.gitea/workflows/docker-ci.yaml';
const TEMPLATE_REGISTRY_HOST = 'git.sitc.skillsit.eu';
const TEMPLATE_PULLDECK_URL = 'https://pulldeck.sitc.skillsit.eu';

export async function gitea(method, apiPath, { token, basic, body, timeout = 60_000 } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `token ${token}`;
  if (basic) headers.Authorization = `Basic ${Buffer.from(`${basic[0]}:${basic[1]}`).toString('base64')}`;
  try {
    const res = await fetch(`${GITEA_API}/api/v1${apiPath}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeout),
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      // non-JSON response
    }
    return { ok: res.ok, status: res.status, json, text };
  } catch (err) {
    return { ok: false, status: 0, json: null, text: err.message };
  }
}

function reportFailure(what, res) {
  console.error(`${what} failed (HTTP ${res.status}): ${res.text}`);
}

export async function waitForGitea() {
  const retries = 10;
  for (let count = 0; ; count++) {
    const res = await gitea('GET', '/version', { timeout: 5_000 });
    if (res.status !== 0) return;
    if (count >= retries) die('Gitea did not become ready in time.');
    console.log('Waiting for Gitea to be ready...');
    await sleep(5_000);
  }
}

export async function createPat(username, password) {
  console.log('Creating Gitea access token...');
  const basic = [username, password];
  await gitea('DELETE', `/users/${encodeURIComponent(username)}/tokens/${TOKEN_NAME}`, { basic, timeout: 30_000 });
  const res = await gitea('POST', `/users/${encodeURIComponent(username)}/tokens`, {
    basic,
    timeout: 30_000,
    body: {
      name: TOKEN_NAME,
      scopes: ['read:admin', 'write:organization', 'write:repository', 'write:user'],
    },
  });
  // Gitea 1.21 returns the secret in "sha1".
  const token = String(res.json?.sha1 ?? res.json?.token ?? '').trim();
  if (!token) die(`Failed to create Gitea access token. Response: ${res.text}`);
  return token;
}

export async function createOrg(token, name) {
  const res = await gitea('POST', '/orgs', { token, body: { username: name, full_name: name } });
  if (res.ok) console.log(`Organization '${name}' created.`);
  else reportFailure(`Creating organization '${name}'`, res);
}

export async function createTeam(token, org, name, canCreateOrgRepo) {
  const res = await gitea('POST', `/orgs/${org}/teams`, {
    token,
    body: {
      name,
      can_create_org_repo: canCreateOrgRepo,
      units_map: {
        'repo.actions': 'read',
        'repo.packages': 'none',
        'repo.code': 'write',
        'repo.issues': 'write',
        'repo.ext_issues': 'none',
        'repo.wiki': 'admin',
        'repo.pulls': 'owner',
        'repo.releases': 'none',
        'repo.projects': 'none',
        'repo.ext_wiki': 'none',
      },
    },
  });
  if (res.ok && res.json?.id) console.log(`Created team ID: ${res.json.id}`);
  else reportFailure(`Creating team '${name}'`, res);
}

export async function addUserToTeam(token, org, teamName, user) {
  const search = await gitea('GET', `/orgs/${org}/teams/search?q=${encodeURIComponent(teamName)}`, { token });
  const team = search.json?.data?.find((t) => t.name === teamName);
  if (!team) {
    reportFailure(`Looking up team '${teamName}' in '${org}'`, search);
    return;
  }
  const res = await gitea('PUT', `/teams/${team.id}/members/${encodeURIComponent(user)}`, { token });
  if (res.status === 204) console.log(`User '${user}' added to team '${teamName}' in organization '${org}'.`);
  else reportFailure(`Adding '${user}' to team '${teamName}'`, res);
}

async function setUserSecret(user, pass, name, value) {
  const res = await gitea('PUT', `/user/actions/secrets/${name}`, { basic: [user, pass], body: { data: value } });
  if (!res.ok) reportFailure(`Setting secret ${name} for ${user}`, res);
  return res.ok;
}

export async function setCompetitorSecrets(user, pass, pulldeckBaseUrl, pulldeckToken) {
  console.log(`Creating user-level secrets for ${user}...`);
  if ((await setUserSecret(user, pass, 'USER', user)) && (await setUserSecret(user, pass, 'PASS', pass))) {
    console.log(`✓ Created USER and PASS secrets for ${user}`);
  }
  if ((await setUserSecret(user, pass, 'PULLDECK_BASE_URL', pulldeckBaseUrl))
    && (await setUserSecret(user, pass, 'PULLDECK_TOKEN', pulldeckToken))) {
    console.log(`✓ Created Pulldeck secrets for ${user}`);
  }
}

export async function createWebhook(domain, username, password) {
  const res = await gitea('POST', '/admin/hooks', {
    basic: [username, password],
    body: {
      type: 'gitea',
      branch_filter: '*',
      config: {
        content_type: 'json',
        url: `https://infra-updater.${domain}/update`,
        secret: WEBHOOK_SECRET,
        is_system_webhook: 'true',
      },
      events: ['repository'],
      authorization_header: '',
      active: true,
    },
  });
  if (res.ok) console.log('Infra updater webhook created.');
  else reportFailure('Creating infra updater webhook', res);
}

export async function importFramework({ token, username, password, domain }, name, githubUrl) {
  const giteaHost = `git.${domain}`;
  // A previous failed import leaves this directory behind.
  fs.rmSync(name, { recursive: true, force: true });
  if (!run('git', ['clone', githubUrl, name]).ok) return console.error(`Failed to clone ${githubUrl}.`);

  const workflowPath = path.join(name, WORKFLOW_FILE);
  if (!fs.existsSync(workflowPath)) return console.error(`Workflow file ${WORKFLOW_FILE} not found in ${name}.`);
  // The pulldeck URL comes from each user's PULLDECK_BASE_URL secret.
  const workflow = fs
    .readFileSync(workflowPath, 'utf8')
    .replaceAll(TEMPLATE_REGISTRY_HOST, () => giteaHost)
    .replaceAll(TEMPLATE_PULLDECK_URL, () => '${{ secrets.PULLDECK_BASE_URL }}');
  fs.writeFileSync(workflowPath, workflow);

  const git = (...args) => run('git', args, { cwd: name });
  git('config', 'user.name', 'Digitalent');
  git('config', 'user.email', 'info@skillsit.hu');
  git('add', WORKFLOW_FILE);
  git('commit', '-m', 'Update Docker registry URL in Gitea Action');

  const res = await gitea('POST', `/orgs/${FRAMEWORK_ORG}/repos`, {
    token,
    body: { name, private: false, template: true },
  });
  if (!res.json?.id) return reportFailure(`Creating repository ${name} on Gitea`, res);
  console.log(`Repository ${name} created in the ${FRAMEWORK_ORG} organization on Gitea.`);

  const remote = `https://${encodeURIComponent(username)}:${encodeURIComponent(password)}@${giteaHost}/${FRAMEWORK_ORG}/${name}.git`;
  git('remote', 'add', 'gitea', remote);
  const pushed = run('git', ['push', 'gitea', 'main'], { cwd: name, env: { GIT_TERMINAL_PROMPT: '0' } }).ok;
  if (pushed) console.log(`Repository ${name} pushed to the ${FRAMEWORK_ORG} organization on Gitea with updated GitHub Action!`);
  else console.error(`Failed to push ${name} to Gitea.`);
}
