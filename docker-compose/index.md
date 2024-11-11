# Docker Compose Applications

## Introduction

This set of Docker Compose files defines a variety of applications that can be easily deployed and managed using Docker. These applications cover a wide range of functionalities, from media management and monitoring to productivity tools and personal finance management.

## List of Applications

| Application | Description |
| --- | --- |
| Actual | A self-hosted personal finance management application. |
| Audiobookshelf | A self-hosted audiobook and podcast server. |
| Gotify | A self-hosted push notification server. |
| Diun | A Docker image update notifier. |
| Dozzle | A web-based Docker container log viewer. |
| DuckDNS | A dynamic DNS service. |
| Filebrowser | A web-based file manager. |
| Firefly III | A self-hosted personal finance management application. |
| FreshRSS | A self-hosted RSS feed reader. |
| Ghostfolio | A self-hosted personal finance tracking and portfolio management application. |
| Homepage | A customizable homepage for your web browser. |
| iCloudPD | A tool for downloading photos from iCloud. |
| Kuma | A self-hosted uptime monitoring tool. |
| Nextcloud | A self-hosted cloud storage and collaboration platform. |
| Nginx Proxy Manager | A web-based reverse proxy for managing your web applications. |
| Ollama | A self-hosted web-based task and project management tool. |
| PhotoPrism | A self-hosted photo management application. |
| Pi-hole + Unbound | A self-hosted DNS server with ad-blocking capabilities. |
| Portainer | A web-based Docker management tool. |
| PrivateBin | A self-hosted encrypted pastebin. |
| Signal-CLI | A self-hosted Signal messaging client. |
| Vaultwarden | A self-hosted password manager. |
| Visual Studio Code | A self-hosted web-based code editor. |
| YouTube-DL | A self-hosted tool for downloading videos from YouTube and other platforms. |

## Application Descriptions

1. **Actual**: A self-hosted personal finance management application that allows you to track your income, expenses, and budgets.

2. **Audiobookshelf**: A self-hosted audiobook and podcast server that provides a web-based interface for managing and listening to your audio content.

3. **Gotify**: A self-hosted push notification server that can be used to receive notifications from various sources, such as Docker containers.

4. **Diun**: A Docker image update notifier that monitors your Docker containers and notifies you when new versions of the images are available.

5. **Dozzle**: A web-based Docker container log viewer that makes it easy to view and search through your container logs.

6. **DuckDNS**: A dynamic DNS service that allows you to access your self-hosted applications using a custom domain name.

7. **Filebrowser**: A web-based file manager that provides a user-friendly interface for managing your files and folders.

8. **Firefly III**: A self-hosted personal finance management application that helps you track your income, expenses, and budgets.

9. **FreshRSS**: A self-hosted RSS feed reader that allows you to subscribe to and read your favorite blogs and news sources.

10. **Ghostfolio**: A self-hosted personal finance tracking and portfolio management application that helps you monitor your investments and net worth.

11. **Homepage**: A customizable homepage for your web browser that can display various widgets and information.

12. **iCloudPD**: A tool for downloading photos from your iCloud account and storing them on your local server.

13. **Kuma**: A self-hosted uptime monitoring tool that allows you to track the availability of your web applications and services.

14. **Nextcloud**: A self-hosted cloud storage and collaboration platform that provides features such as file sharing, calendars, and contacts.

15. **Nginx Proxy Manager**: A web-based reverse proxy for managing your web applications, including SSL/TLS configuration and domain name management.

16. **Ollama**: A self-hosted web-based task and project management tool.

17. **PhotoPrism**: A self-hosted photo management application that helps you organize, edit, and share your photos.

18. **Pi-hole + Unbound**: A self-hosted DNS server with ad-blocking capabilities, providing a more private and secure internet experience.

19. **Portainer**: A web-based Docker management tool that makes it easy to manage your Docker containers and images.

20. **PrivateBin**: A self-hosted encrypted pastebin that allows you to securely share text and code snippets.

21. **Signal-CLI**: A self-hosted Signal messaging client that allows you to send and receive encrypted messages.

22. **Vaultwarden**: A self-hosted password manager that provides a secure way to store and manage your passwords.

23. **Visual Studio Code**: A self-hosted web-based code editor that provides a full-featured development environment.

24. **YouTube-DL**: A self-hosted tool for downloading videos from YouTube and other platforms, allowing you to create your own video library.

## How to Run the Applications

To run these applications, you'll need to have Docker and Docker Compose installed on your system. Once you have these tools set up, you can follow these steps:

1. Clone the repository containing the Docker Compose files.
2. Navigate to the directory containing the Docker Compose files.
3. Run the following command to start the applications:

```
docker-compose up -d
```

This will start all the applications defined in the Docker Compose files in the background. You can then access the applications by navigating to their respective URLs in your web browser.

To stop the applications, you can run the following command:

```
docker-compose down
```

This will stop and remove the containers for all the applications.