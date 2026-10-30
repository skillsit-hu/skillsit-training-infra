#!/usr/bin/env node
// Provisions the competition environment from config/main-config.json (app/packages/core/src/ops/init.ts).

import { runCli } from './app/cli.mjs';

await runCli('init', import.meta.url);
