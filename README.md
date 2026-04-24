# iztro OpenAI MCP for Railway

Remote MCP server for Zi Wei Dou Shu / Tu Vi Dau So tools, prepared for Railway and OpenAI ChatGPT developer mode.

## What I found

- As of 2026-04-24, `@feida/iztro-mcp-server` is not returned by npm registry.
- The active public package is `@xzkcz/iztro-mcp-server@2.2.1`.
- npm publish timeline for `@xzkcz/iztro-mcp-server`:
  - `1.0.3` on 2025-07-26
  - `1.0.4` on 2025-10-03
  - `2.2.1` on 2025-12-03
- The package metadata still points to `https://github.com/xzkcz/iztro-mcp-server.git`, but that GitHub repository returned `404` during verification on 2026-04-24.
- The published package itself is small and lightweight, but its entrypoint starts with `transportType: "stdio"`, so it is not directly usable as a public remote MCP endpoint for OpenAI without a wrapper.

## Why this wrapper exists

- OpenAI remote MCP works over Streamable HTTP or HTTP/SSE.
- The upstream npm package is `stdio` only.
- This project recreates the useful read-only astrology tools and exposes them at:
  - `GET /`
  - `GET /health`
  - `POST /mcp` and related Streamable HTTP traffic
  - `GET /sse`

## Included tools

- `get_astrolabe`
- `get_horoscope_decades`
- `get_horoscope_ages`
- `get_horoscope_years`
- `get_horoscope_months`
- `get_mutaged_places`

`gen_astrolabe` was intentionally left out because it writes files to disk and is not useful for a public read-only MCP deployment.

## Surface Pro 4 fit check

- Resource-wise, this workload is light enough for a Surface Pro 4 with Core m3, 4 GB RAM, and 128 GB storage.
- Published package sizes checked from npm:
  - `@xzkcz/iztro-mcp-server`: 67,010 bytes unpacked
  - `iztro`: 2,138,358 bytes unpacked
  - `fastmcp`: 1,332,900 bytes unpacked
  - `lunar-typescript`: 1,360,545 bytes unpacked
- Practical issue: to let ChatGPT call it, you need a public HTTPS endpoint. Because this machine did not already have Node installed and local hosting would still need tunnel or public ingress, Railway is the cleaner deployment target.

## Deploy to Railway

1. Put this folder in a Git repository.
2. Push it to GitHub.
3. In Railway, create a new project from that repo.
4. Railway should auto-detect Node and run `npm start`.
5. After deploy, your MCP endpoint will be:

```text
https://YOUR-APP.up.railway.app/mcp
```

Health check:

```text
https://YOUR-APP.up.railway.app/health
```

Landing page:

```text
https://YOUR-APP.up.railway.app/
```

## Connect from ChatGPT

As verified from OpenAI docs on 2026-04-24:

- ChatGPT Developer mode supports remote MCP over `SSE` and `streaming HTTP`.
- Supported auth modes there are `OAuth`, `No Authentication`, and `Mixed Authentication`.

Recommended setup:

1. Open ChatGPT on web.
2. Go to `Settings -> Apps -> Advanced settings -> Developer mode`.
3. Turn Developer mode on.
4. Click `Create app`.
5. Use:
   - Server URL: `https://YOUR-APP.up.railway.app/mcp`
   - Authentication: `No Authentication`

## OpenAI Responses API example

```json
{
  "model": "gpt-5.4",
  "input": "Lap la so cho ngay 2000-08-16 luc 2 gio sang, nam, locale zh-CN",
  "tools": [
    {
      "type": "mcp",
      "server_label": "iztro",
      "server_url": "https://YOUR-APP.up.railway.app/mcp",
      "require_approval": "never"
    }
  ]
}
```

Because every exposed tool here is read-only, `require_approval: "never"` is a reasonable default.

## Run locally later if you want

```bash
npm install
npm start
```

Local endpoints:

- `http://localhost:3000/mcp`
- `http://localhost:3000/sse`
- `http://localhost:3000/health`

If you want ChatGPT on the public Internet to call a local machine, you still need a public HTTPS tunnel such as Cloudflare Tunnel or another ingress layer.
