#!/usr/bin/env node
// Creates the base Gitea organisations using the root credentials from config/main-config.json.

import { runCli } from './app/cli.mjs';

await runCli('setupOrgs', import.meta.url);
