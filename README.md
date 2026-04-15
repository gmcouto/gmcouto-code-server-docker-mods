# code-server-ai-tools

A [Docker Mod](https://github.com/linuxserver/docker-mods) for the
[linuxserver/code-server](https://hub.docker.com/r/linuxserver/code-server) container that
installs the following tools on every container start:

### Terminal utilities

| Tool | Package | Description |
|---|---|---|
| [tmux](https://github.com/tmux/tmux) | `apt` | Terminal multiplexer for persistent terminal sessions |

### AI CLI tools

| Tool | Package | Description |
|---|---|---|
| [gemini-cli](https://github.com/google-gemini/gemini-cli) | `@google/gemini-cli` | Google Gemini in your terminal |
| [claude-code](https://github.com/anthropics/claude-code) | `@anthropic-ai/claude-code` | Anthropic Claude agentic coding CLI |
| [openclaude](https://github.com/Gitlawb/openclaude) | `@gitlawb/openclaude` | Open-source Claude-compatible coding agent CLI |
| [Cursor Agent CLI](https://cursor.com/docs/cli/installation) | official installer | Cursor editor CLI (`cursor-agent` command) |
| [GitHub Copilot CLI](https://github.com/github/copilot-cli) | `@github/copilot` | GitHub Copilot in your terminal (`copilot` command) |
| [OpenAI Codex CLI](https://github.com/openai/codex) | `@openai/codex` | OpenAI Codex local coding agent (`codex` command) |

> **Prerequisites** – this mod relies on Node.js/npm being available at container startup.
> Use it alongside the **`linuxserver/mods:code-server-nodejs`** or **`linuxserver/mods:code-server-nvm`** mod.

---

## Usage

Just add this repo's image, `ghcr.io/gmcouto/code-server-ai-tools:latest`, to your container's `DOCKER_MODS` environment variable. You can do this either in your `docker run` command or in `docker-compose.yml`:

### docker run

```bash
docker run -d \
  --name=code-server \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Etc/UTC \
  -e DOCKER_MODS=linuxserver/mods:code-server-nodejs|ghcr.io/gmcouto/code-server-ai-tools:latest \
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
      - DOCKER_MODS=linuxserver/mods:code-server-nodejs|linuxserver/mods:code-server-nvm|linuxserver/mods:universal-docker|linuxserver/mods:code-server-python3|ghcr.io/gmcouto/code-server-ai-tools:latest
    volumes:
      - /path/to/config:/config
    ports:
      - 8443:8443
    restart: unless-stopped
```


## My personal DOCKER_MODS value:
```
DOCKER_MODS=linuxserver/mods:code-server-nodejs|linuxserver/mods:code-server-nvm|linuxserver/mods:universal-docker|linuxserver/mods:code-server-python3|ghcr.io/gmcouto/code-server-ai-tools:latest
```
