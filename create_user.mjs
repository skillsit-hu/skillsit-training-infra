#!/usr/bin/env node
// Adds a competitor to an already initialised environment. Usage: node create_user.mjs <USERNAME> <USER_PASSWORD>

import { runCli } from './app/cli.mjs';

await runCli('createUser', import.meta.url);
