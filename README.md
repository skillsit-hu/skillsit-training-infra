# Competition Environment Setup

## Description
This project provides a simple, reliable, and efficient environment for web development competitions. Using Docker along with Gitea, Traefik, Watchtower, and MySQL, it allows organizers to set up a consistent competition environment with minimal effort. Competitors can focus on their work without worrying about complex configurations.

The environment includes:
1. **Docker**: Ensures consistent setups across systems.  
2. **Traefik**: Routes requests to the right services.  
3. **Watchtower**: Updates Docker containers automatically.  
4. **Gitea**: A Git server for version control.  
5. **MySQL**: Manages competition data.  

## Setting up the Environment

### Prerequisites
Ensure [Node.js](https://nodejs.org/) 20 or newer is installed. On a fresh Debian host, `node setup.mjs` installs Docker (it has no dependencies).

The other scripts are thin wrappers around the shared code in `app/`, which has to be built once (and after every update):

```bash
cd app && npm ci && npm run build
```

### Admin UI
The same operations are available from a web UI (`app/`: Express API + React). Start it as a container next to the environment:

```bash
docker compose -f admin.yaml up -d --build
```

If the repository is not at `/home/azureuser/infra`, pass its absolute path: `INFRA_DIR=$PWD docker compose -f admin.yaml up -d --build`.

It listens on `http://<host>:8090` (set `ADMIN_PORT` to change it) and logs in with the root `username` / `password` from `config/main-config.json`. From the UI you can edit the configuration (domain, HTTPS, modules, competitors), run the operations below, and follow their logs live. Set `ADMIN_SESSION_SECRET` so logins survive container restarts. The admin container is not part of start/stop/clean, so it keeps running after `clean`. Job logs are kept in `data-admin/jobs/`.

The UI is served over plain HTTP; reach it through an SSH tunnel or a firewall-restricted port.

### Commands
- **Initialize the environment:**  
  `node init.mjs`
   
   **Note:** If you have previously run `node init.mjs`, make sure to clean the environment first by running `node clean.mjs` before initializing again. This ensures a fresh setup and avoids potential conflicts.

- **Add a competitor to a running environment:**  
  `node create_user.mjs <username> <password>`

- **Stop the environment:**  
  `node stop.mjs`

- **Restart the environment:**  
  `node start.mjs`

- **Clean the entire system:**  
  `node clean.mjs`

- **Disable all competitors' Gitea logins:**  
  `node disable_competitors_gitlogin.mjs`

### Configuration
The environment is configured in `config/main-config.json`:

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
   Before making changes to the environment repository, stop all Docker containers: `node stop.mjs`


## Competitor Workflow

### Creating a Repository

1. **Access Gitea:**  
   Open your Git server (e.g., `https://git.local.skill17.com`) and log in using your credentials.

2. **Choose a Framework Template:**  
   Go to `organization -> frameworks` to pick a framework or the vanilla base for your repository. The templates include the necessary Docker and Gitea files with GitHub Actions ready to use. Check the [Frameworks Documentation](./frameworks.md) for details.  
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
