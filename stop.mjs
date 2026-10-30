#!/usr/bin/env node
// Stops the environment without removing containers or data.

import { runCli } from './app/cli.mjs';

await runCli('stop', import.meta.url);
