# Competition Environment Setup

## Description
This project provides a simple, reliable, and efficient environment for web development competitions. Using Docker along with Gitea, Traefik, and MySQL, it allows organizers to set up a consistent competition environment with minimal effort. Competitors can focus on their work without worrying about complex configurations.

The environment includes:
1. **Docker**: Ensures consistent setups across systems.  
2. **Traefik**: Routes requests to the right services.  
3. **Gitea**: A Git server for version control.  
4. **MySQL**: Manages competition data.  

## Setting up the Environment

### Quick start
On a fresh Debian or Ubuntu server you only need git:

```bash
git clone <this repository> infra && cd infra
sudo sh install.sh
```

`install.sh` does the following:
1. Installs Docker if it is missing.
2. Asks for the competition domain and the root password, and writes `config/main-config.json`.
3. Starts the base layer: Traefik and the admin UI.
4. Prints the admin address.

Create a wildcard DNS record (`*.<domain>` pointing to the server) beforehand. Everything else is done in the browser:

- **Admin UI:** `https://admin.<domain>`. Log in with the root user.
- **Fallback when Traefik is down:** `ssh -L 8090:127.0.0.1:8090 <server>`, then open `http://localhost:8090`.

In the UI you add the modules and competitors, then run **Inicializálás** (init). You can follow every operation's log live; logs are also kept in `data-admin/jobs/`.

Re-running `install.sh` keeps the existing configuration and only restarts the base layer. Traefik and the admin UI are not touched by stop and clean.

### TLS certificates
With `letsencrypt: true` in the config, Traefik requests a separate Let's Encrypt certificate for each host the first time it is accessed. This covers `git.`, `admin.`, `pma.` and every competitor site. Turn it on or off in `install.sh` or with the Let's Encrypt switch in the UI. A change in the UI takes effect at the next Inicializálás.

Requirements:
- Public DNS for every host. A wildcard record `*.<domain>` covers all of them except two:
  - `repo.repman.<domain>` needs its own record;
  - the bare `<domain>`, where the Traefik dashboard is served.
- Port 80 reachable from the internet (HTTP-01 challenge).
- Let's Encrypt limits: 50 new certificates per registered domain per week, and 5 for the same host. The certificates live in the `infra-traefik_letsencrypt` volume, which Tisztítás does not remove, so re-initializing does not request new ones. Removing that volume does.
- To try it out without using up the limits, set `ACME_CA_SERVER=https://acme-staging-v02.api.letsencrypt.org/directory` in `.admin.env`, then re-run `install.sh`. Staging certificates are not trusted by browsers. Before switching back, remove the volume, because Traefik keeps the staging certificates until they expire:

  ```bash
  docker compose -p infra-traefik -f traefik.yaml down
  docker volume rm infra-traefik_letsencrypt
  ```

Hosts without a certificate yet, and every host when Let's Encrypt is off, get the built-in certificate from `config/traefik/certs`, which browsers warn about. Use this for local or test environments whose domain isn't publicly resolvable.

The admin UI writes its own route whenever the configuration is saved, so a new domain or Let's Encrypt setting applies to `admin.<domain>` right away. The other services follow at the next Inicializálás.

### Admin UI
The admin UI lives in its own repository, [skillsit-training-admin](https://github.com/skillsit-hu/skillsit-training-admin). GitHub Actions publishes it as the `ghcr.io/skillsit-hu/skillsit-training-admin` image, so nothing is built on the server. `install.sh` pulls the latest image.

To update the admin UI on a running server, re-run `sudo INFRA_KEEP_CONFIG=1 sh install.sh`. To use a fixed version, set `ADMIN_IMAGE=ghcr.io/skillsit-hu/skillsit-training-admin:<version>` in `.admin.env`.

The operations run from the UI:

| UI | Operation |
| --- | --- |
| Inicializálás | Provisions the environment. Run Tisztítás first if it was initialized before. |
| Indítás / Leállítás | Starts or stops the environment. Containers and data are kept. |
| Tisztítás | Removes containers, data volumes, competitor images and framework clones. Traefik and the admin UI keep running. |
| Versenyző létrehozása | Adds a competitor to a running environment. |
| Versenyzői loginok tiltása | Disables all competitors' Gitea logins. |
| Sablonok szinkronizálása | Imports the framework templates of the configuration that are missing from Gitea and deletes the ones no longer listed. |
| Versenyzői konténerek szinkronizálása | Regenerates the competitor containers and routes from the competitors' Gitea repositories. Runs automatically whenever a repository is created or deleted (Gitea webhook). |

### Configuration
The environment is configured in `config/main-config.json`. `install.sh` creates it, the admin UI edits it, and it is not committed (see `config/main-config.example.json`):

```json
{
  "domain": "local.skill17.com",
  "enableHttps": true,
  "letsencrypt": true,
  "acmeEmail": "ops@example.com",
  "username": "root",
  "password": "change-me",
  "modules": ["module_a", "module_b"],
  "competitors": [
    { "name": "Competitor One", "username": "comp01", "password": "test123" }
  ]
}
```

1. **domain:** The main domain for the competition.
2. **enableHttps:** Enable (`true`) or disable (`false`) HTTPS for Traefik.
   - **letsencrypt / acmeEmail:** Per-host Let's Encrypt certificates (see above), with an optional e-mail for expiry notices.
3. **username / password:** Root credentials for Gitea and MySQL.
4. **modules:** Competition task names. A competitor site is published at `<username>-<module>.<domain>`, lowercase, with `_` replaced by `-` (Let's Encrypt rejects `_` in hostnames).
5. **competitors:** Each entry is a username and a password, with an optional display name.
6. **frameworks:** The framework templates that init imports into the Gitea `frameworks` organization as template repositories, as `{ "name": "laravel", "url": "https://github.com/…/ws26-laravel.git" }` entries. Without the field the built-in list (the sitc2026-templates repositories) is used. Add or remove templates on the Konfiguráció page. Init imports the list; in a running environment, **Sablonok szinkronizálása** imports the new templates and deletes the removed ones. Repositories that competitors already created from a template are independent copies and are not affected. A template without `.gitea/workflows/docker-ci.yaml` is imported unchanged.

## Using the Environment

- **Git Server (Gitea):**  
  Access through the `git` subdomain of your configured domain.  
  **Example:** `https://git.local.skill17.com`

- **Competitors' Work:**  
  Competitors' projects can be accessed using their username and the module name.  
  Format: `https://<username>-<module_name>.<domain>` (lowercase, `_` becomes `-`)  
  **Example:** `https://comp01-module-a.local.skill17.com`

- **PHPMyAdmin (Database Management):**  
  Manage databases through the `pma` subdomain of your configured domain.  
  **Example:** `https://pma.local.skill17.com`

- **Packagist Mirror (Package Caching):**  
  A local Repman instance serving as a Packagist mirror for caching Laravel vendor packages, improving dependency installation speed.  
  Access through the `repman` subdomain of your configured domain.  
  **Example:** `https://repman.local.skill17.com`

## Updates (Environment Repository)
   Before making changes to the environment repository, stop the environment in the admin UI (Leállítás).


## Competitor Workflow

### Creating a Repository

1. **Access Gitea:**  
   Open your Git server (e.g., `https://git.local.skill17.com`) and log in using your credentials.

2. **Choose a Framework Template:**  
   Go to `organization -> frameworks` to pick a framework or the vanilla base for your repository. The templates include the necessary Docker and Gitea files with GitHub Actions ready to use.  
   **Tip:** Keep frontend and backend in separate repositories for better organization.

3. **Use the Template:**  
   Click **"Use this template"** to create your repository. Name the repository to match the module name defined in the configuration file.  
   **Example:** If your module is `module-a`, name the repository `module-a`.

4. **Set Up Action Secrets:**  
   Go to **Settings → Actions → Secrets** in your new repository and add:  
   - **`USER`**: Your username (e.g., `comp01`)  
   - **`PASS`**: Your password (e.g., `test123`)

5. **Test the Setup:**  
   Make a commit to verify that GitHub Actions are working correctly.

### Cloning and using the Repository

1. Use the repository URL to clone it:  
   ```bash
   git clone https://git.local.skill17.com/<username>/<module_name>.git
   ```  
   **Example:**  
   ```bash
   git clone https://git.local.skill17.com/comp01/module-a.git
   ```

2. Edit, commit, and develop your code. Frequent commits help keep your work organized, and using branches allows you to work on features or fixes without affecting the main deployment. If competition organizers allow it, you can use third-party packages to support frameworks and enhance your project. Always keep your project README up to date with essential information about the repository, such as setup instructions and dependencies.

3. Every push automatically deploys to the competition URL (e.g., `https://<username>-<module_name>.local.skill17.com`).  
   Be mindful of the number of pushes to avoid unnecessary deployments. Check your changes at the competition URL after each push.
