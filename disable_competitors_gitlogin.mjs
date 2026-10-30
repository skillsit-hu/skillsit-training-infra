#!/usr/bin/env node
// Disables the Gitea accounts of all competitors in config/main-config.json (e.g. at the end of a competition).

import { runCli } from './app/cli.mjs';

await runCli('disableCompetitorLogins', import.meta.url);
