# gmcouto-code-server-docker-mods

A [Docker Mod](https://github.com/linuxserver/docker-mods) for the
[linuxserver/code-server](https://hub.docker.com/r/linuxserver/code-server) container that
installs the following AI CLI tools on every container start:

| Tool | Package | Description |
|---|---|---|
| [gemini-cli](https://github.com/google-gemini/gemini-cli) | `@google/gemini-cli` | Google Gemini in your terminal |
| [claude-code](https://github.com/anthropics/claude-code) | `@anthropic-ai/claude-code` | Anthropic Claude agentic coding CLI |
| [openclaude](https://github.com/Gitlawb/openclaude) | `@gitlawb/openclaude` | Open-source Claude-compatible coding agent CLI |
| [cursor CLI](https://cursor.com/docs/cli/installation) | official installer | Cursor editor CLI (`cursor` command) |
| [GitHub Copilot CLI](https://github.com/github/copilot-cli) | `@github/copilot` | GitHub Copilot in your terminal (`copilot` command) |
| [OpenAI Codex CLI](https://github.com/openai/codex) | `@openai/codex` | OpenAI Codex local coding agent (`codex` command) |

> **Prerequisites** – this mod relies on Node.js/npm being available at container startup.
> Use it alongside the **`linuxserver/mods:code-server-nodejs`** or **`linuxserver/mods:code-server-nvm`** mod.

---

## Usage

Add the mod to your `docker run` or `docker-compose.yml`:

### docker run

```bash
docker run -d \
  --name=code-server \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Etc/UTC \
  -e DOCKER_MODS=linuxserver/mods:code-server-nodejs|ghcr.io/gmcouto/gmcouto-code-server-docker-mods:code-server-ai-tools \
  -p 8443:8443 \
  -v /path/to/config:/config \
  --restart unless-stopped \
  lscr.io/linuxserver/code-server:latest
```

### docker-compose.yml

```yaml
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - DOCKER_MODS=linuxserver/mods:code-server-nodejs|linuxserver/mods:code-server-nvm|linuxserver/mods:universal-docker|linuxserver/mods:code-server-python3|ghcr.io/gmcouto/gmcouto-code-server-docker-mods:code-server-ai-tools
    volumes:
      - /path/to/config:/config
    ports:
      - 8443:8443
    restart: unless-stopped
```

---

## Building & Publishing

The GitHub Actions workflow (`.github/workflows/BuildImage.yml`) builds and pushes the image
automatically on every push.

### Required repository secrets

| Secret | Description |
|---|---|
| `CR_USER` | Your GitHub username |
| `CR_PAT` | GitHub Personal Access Token with `read:packages` and `write:packages` scopes |
| `DOCKERUSER` | DockerHub username *(optional – only needed for DockerHub publishing)* |
| `DOCKERPASS` | DockerHub password/token *(optional)* |

The built image tag will be:

```
ghcr.io/gmcouto/gmcouto-code-server-docker-mods:code-server-ai-tools
```
