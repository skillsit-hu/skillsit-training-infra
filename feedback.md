# Feedback and Questions

## Project Templates

### React

[Repo](https://github.com/skill-setup/react-vite-js-base)

## Pull Requests

### Configure Nginx for frontend routing, add missing dependencies, and fix Tailwind setup in Vite #1

- Added a custom nginx.conf file to configure Nginx for serving the frontend, including support for client-side routing with try_files.
- Updated the Dockerfile to copy the new nginx.conf into the Nginx container, ensuring the server uses the custom configuration.
- Added the missing dependencies to package.json, including @tailwindcss/vite, date-fns, and react-toast. These dependencies were in the IL, but were not installed in this repo yet.
- Fixed vite.config.js to include the @tailwindcss/vite plugin alongside React, enabling Tailwind CSS integration with Vite.

### Laravel

...

## Infra (Competition Scripts)

[Repo](https://github.com/skill-setup/competition-scripts)

## Pull Requests

### Automate user secrets setup and add .env file support with updated documentation #8

- The initialization script (init.sh) now automatically creates user-level secrets (USER and PASS) for each user using the Gitea API, removing the need for manual configuration.
- The script writes all relevant environment variables to a new .env file, making it easier to manage and reference configuration values. The script now strips carriage returns and newlines from values read from config/main to prevent formatting issues.
- The README has been updated to remove the step instructing users to manually set up action secrets, reflecting the new automated approach.

## Questions

### NPM cache

THe infra does not contain npm cache.
