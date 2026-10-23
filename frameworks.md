# Framework Templates

For your projects, you can use ready-made blank templates tailored to popular frameworks. It is recommended to maintain separate repositories for frontend and backend frameworks for better organization and scalability.

| Framework | Version in Repository | Repository URL                                                                      | Latest Stable Version | Release Date     | Manual Page                                            |
| --------- | --------------------- | ----------------------------------------------------------------------------------- | --------------------- | ---------------- | ------------------------------------------------------ |
| Laravel   | ^10.8                 | [skill-setup/laravel-base](https://github.com/skill-setup/laravel-base)             | 11.0.0                | December 5, 2024 | [Laravel Documentation](https://laravel.com/docs/11.x) |
| Next.js   | ^13.4.9               | [skill-setup/nextjs-base](https://github.com/skill-setup/nextjs-base)               | 15.0.0                | November 2024    | [Next.js Documentation](https://nextjs.org/docs)       |
| React     | ^18.3.1               | [skill-setup/react-vite-js-base](https://github.com/skill-setup/react-vite-js-base) | 19.0.0                | December 5, 2024 | [React Documentation](https://react.dev/versions)      |
| Vue.js    | ^3.2.47               | [skill-setup/vuejs](https://github.com/skill-setup/vuejs)                           | 3.3.4                 | August 2024      | [Vue.js Documentation](https://vuejs.org/guide/)       |

---

## Additional Resources
- [Vanilla Base](https://github.com/skill-setup/vanilla-base): A minimal template for vanilla JavaScript projects.

## Using the Packagist Mirror for Laravel Projects

For Laravel projects, you can configure Composer to use the local Repman instance as a Packagist mirror for faster package installation and caching. Add the following configuration to your `composer.json` file:

```json
{
  "repositories": [
    {
      "type": "composer",
      "url": "https://packagist.{DOMAIN}",
      "options": {
        "ssl": {
          "verify_peer": false
        }
      }
    },
    {
      "packagist.org": false
    }
  ]
}
```

Replace `{DOMAIN}` with your configured domain (e.g., `local.skill17.com`).

### Alternative: Using Repman as a fallback

If you want to use Repman as a fallback (tries local mirror first, then packagist.org):

```json
{
  "repositories": [
    {
      "type": "composer",
      "url": "https://packagist.{DOMAIN}",
      "options": {
        "ssl": {
          "verify_peer": false
        }
      }
    }
  ]
}
```

### Benefits of using Repman:

- **Faster package installation** - Dependencies are cached locally
- **Private package hosting** - Host your own private packages
- **Reduced external network dependency** - Packages served from local mirror
- **Advanced features** - Web interface, API access, security scanning
- **GitHub/GitLab integration** - Easy private package imports