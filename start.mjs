#!/usr/bin/env node
// Restarts the stopped environment.

import { runCli } from './app/cli.mjs';

await runCli('start', import.meta.url);
