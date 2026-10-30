#!/usr/bin/env node
// Tears the environment down completely: containers, data volumes, competitor images and framework clones.

import { runCli } from './app/cli.mjs';

await runCli('clean', import.meta.url);
