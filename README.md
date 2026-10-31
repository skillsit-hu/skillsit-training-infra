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

The built-in TLS certificate in `config/traefik/certs` is used for every host, so browsers warn on other domains. Proper certificates are a to-do.

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

### Configuration
The environment is configured in `config/main-config.json`. `install.sh` creates it, the admin UI edits it, and it is not committed (see `config/main-config.example.json`):

```json
{
  "domain": "local.skill17.com",
  "enableHttps": true,
  "username": "root",
  "password": "change-me",
  "modules": ["module_a", "module_b"],
  "competitors": [
    { "username": "comp01", "password": "test123", "subdomain": "qwer" }
  ]
}
```

1. **domain:** The main domain for the competition.
2. **enableHttps:** Enable (`true`) or disable (`false`) HTTPS for Traefik.
3. **username / password:** Root credentials for Gitea and MySQL.
4. **modules:** Competition task names. A competitor site is published at `<subdomain>-<module>.<domain>`.
5. **competitors:** Each entry is a username, password, and subdomain.

## Using the Environment

- **Git Server (Gitea):**  
  Access through the `git` subdomain of your configured domain.  
  **Example:** `https://git.local.skill17.com`

- **Competitors' Work:**  
  Competitors' projects can be accessed using their subdomain and the module name.  
  Format: `https://<subdomain>-<module_name>.<domain>`  
  **Example:** `https://qwer-module_a.local.skill17.com`

- **PHPMyAdmin (Database Management):**  
  Manage databases through the `pma` subdomain of your configured domain.  
  **Example:** `https://pma.local.skill17.com`

- **Packagist Mirror (Package Caching):**  
  A local Repman instance serving as a Packagist mirror for caching Laravel vendor packages, improving dependency installation speed.  
  Access through the `packagist` subdomain of your configured domain.  
  **Example:** `https://packagist.local.skill17.com`

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

3. Every push automatically deploys to the competition URL (e.g., `https://<subdomain>-<module_name>.local.skill17.com`).  
   Be mindful of the number of pushes to avoid unnecessary deployments. Check your changes at the competition URL after each push.
