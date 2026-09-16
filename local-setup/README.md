Scripts locaux (machine-specifiques)

setup pour macOS 12 Monterey Intel:
- scripts-local-setup.sh : binaire systeme (yt-dlp, ffmpeg, ffprobe) dans ~/bin
- install-node-deps.sh : npm install (Node 22, cache local) + correctif ORT + build
- smoke-test.sh : preflight + MCP tools/list + CLI

NOTE : les chemins sont en dur pour la machine d'origine (/Users/user/Documents/video-extract-mcp).
A adapter avant reuse ailleurs.
