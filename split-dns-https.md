# Traefik with Pihole & Cloudflare Tunnel - HTTPS Setup Guide

## Architecture Overview

This guide explains how to set up Traefik as a reverse proxy with:
- **Pi-hole** for local DNS resolution (split-DNS)
- **Cloudflare Tunnel** for secure public access
- **Let's Encrypt** with DNS-01 for valid HTTPS certificates on both public and local-only subdomains

### Key Concept

Let's Encrypt validates domain ownership via DNS records, not by checking if services are publicly accessible. This means you can obtain valid certificates for local-only services using the DNS-01 challenge.

---

## Scenario 1: Public + Local Subdomain (homeassistant.example.com)

### Use Case
Service accessible both:
- **Locally**: Direct connection via Pi-hole DNS
- **Publicly**: Via Cloudflare Tunnel with HTTPS

### Setup

#### Pi-hole Configuration
Add A record:
```
homeassistant.example.com → 192.168.1.X (Traefik server IP)
```

#### Cloudflare Configuration
- DNS A record: `homeassistant.example.com → any public IP` (or localhost)
- Create Cloudflare Tunnel routing:
  ```yaml
  homeassistant.example.com → http://localhost:8080 (Traefik's tunnel entry point)
  ```

#### Traefik Docker Compose Setup

**traefik service:**
```yaml
traefik:
  image: traefik:latest
  container_name: traefik
  restart: unless-stopped
  ports:
    - "80:80"      # Local HTTP (redirects to HTTPS)
    - "443:443"    # Local HTTPS
    - "8080:8080"  # Cloudflared tunnel entry point
  environment:
    - CF_DNS_API_TOKEN=your_cloudflare_api_token
    - CF_ZONE_API_TOKEN=your_cloudflare_zone_token
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./traefik.yml:/traefik.yml:ro
    - ./acme.json:/acme.json
  networks:
    - traefik
```

**traefik.yml configuration:**
```yaml
api:
  dashboard: true
  debug: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          scheme: https
          port: 443
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: acme.json
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - 1.1.1.1:53
          - 8.8.8.8:53

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik
  file:
    filename: traefik.yml
    watch: true
```

**Service labels (docker-compose.yml):**
```yaml
homeassistant:
  image: ghcr.io/home-assistant/home-assistant:latest
  container_name: homeassistant
  restart: unless-stopped
  ports:
    - "8123:8123"  # Internal port
  volumes:
    - ./config:/config
  networks:
    - traefik
  labels:
    - traefik.enable=true
    - traefik.http.routers.homeassistant.rule=Host(`homeassistant.example.com`)
    - traefik.http.routers.homeassistant.entrypoints=websecure
    - traefik.http.routers.homeassistant.tls=true
    - traefik.http.routers.homeassistant.tls.certresolver=letsencrypt
    - traefik.http.services.homeassistant.loadbalancer.server.port=8123

networks:
  traefik:
    driver: bridge
```

#### Cloudflared Tunnel Config (config.yml)
```yaml
tunnel: your-tunnel-uuid
credentials-file: /path/to/credentials.json

ingress:
  - hostname: homeassistant.example.com
    service: http://localhost:8080
  - service: http_status:404
```

---

## Scenario 2: Local-Only Subdomain (admin.local.example.com)

### Use Case
Service accessible **only locally** with valid HTTPS:
- NOT exposed via Cloudflare Tunnel
- Accessible only within local network
- Uses valid Let's Encrypt certificate

### Setup

#### Pi-hole Configuration
Add A record:
```
admin.local.example.com → 192.168.1.X (Traefik server IP)
```

#### Cloudflare Configuration (Optional)
- DNS A record: `admin.local.example.com → any value` (e.g., localhost or your home IP)
- **NO Cloudflare Tunnel** - service stays private

**Why add to Cloudflare DNS?** Let's Encrypt uses DNS-01 challenge which queries Cloudflare's DNS records. The service doesn't need to be publicly accessible, only the DNS record must exist.

#### Traefik Configuration
Use same Traefik setup as Scenario 1.

**Service labels (docker-compose.yml):**
```yaml
admin_dashboard:
  image: some-admin-service:latest
  container_name: admin_dashboard
  restart: unless-stopped
  ports:
    - "3000:3000"  # Internal port
  volumes:
    - ./admin-config:/config
  networks:
    - traefik
  labels:
    - traefik.enable=true
    - traefik.http.routers.admin.rule=Host(`admin.local.example.com`)
    - traefik.http.routers.admin.entrypoints=websecure
    - traefik.http.routers.admin.tls=true
    - traefik.http.routers.admin.tls.certresolver=letsencrypt
    - traefik.http.services.admin.loadbalancer.server.port=3000
```

**Note:** Service labels are identical to Scenario 1. The difference is:
- Cloudflare Tunnel doesn't route this subdomain
- Only Pi-hole DNS resolves it locally
- Certificate is still valid Let's Encrypt

---

## Complete Example: Multiple Services

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    environment:
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
      - CF_ZONE_API_TOKEN=${CF_ZONE_API_TOKEN}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./acme.json:/acme.json
    networks:
      - traefik

  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:latest
    container_name: homeassistant
    restart: unless-stopped
    volumes:
      - ./config:/config
    networks:
      - traefik
    labels:
      - traefik.enable=true
      - traefik.http.routers.homeassistant.rule=Host(`homeassistant.example.com`)
      - traefik.http.routers.homeassistant.entrypoints=websecure
      - traefik.http.routers.homeassistant.tls.certresolver=letsencrypt
      - traefik.http.services.homeassistant.loadbalancer.server.port=8123

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    volumes:
      - ./jellyfin/config:/config
      - ./jellyfin/cache:/cache
      - /media:/media:ro
    networks:
      - traefik
    labels:
      - traefik.enable=true
      - traefik.http.routers.jellyfin.rule=Host(`jellyfin.example.com`)
      - traefik.http.routers.jellyfin.entrypoints=websecure
      - traefik.http.routers.jellyfin.tls.certresolver=letsencrypt
      - traefik.http.services.jellyfin.loadbalancer.server.port=8096

  admin_panel:
    image: custom-admin:latest
    container_name: admin_panel
    restart: unless-stopped
    volumes:
      - ./admin-config:/config
    networks:
      - traefik
    labels:
      - traefik.enable=true
      - traefik.http.routers.admin.rule=Host(`admin.local.example.com`)
      - traefik.http.routers.admin.entrypoints=websecure
      - traefik.http.routers.admin.tls.certresolver=letsencrypt
      - traefik.http.services.admin.loadbalancer.server.port=3000

networks:
  traefik:
    driver: bridge
```

---

## Environment Setup

Create `.env` file:
```bash
CF_DNS_API_TOKEN=your_cloudflare_api_token
CF_ZONE_API_TOKEN=your_cloudflare_zone_api_token
```

Get Cloudflare tokens from: https://dash.cloudflare.com/profile/api-tokens

---

## Traffic Flow Diagram

### Scenario 1 (Public + Local)
```
User Local (on WiFi)
  ↓
Pi-hole DNS: homeassistant.example.com → 192.168.1.X
  ↓
Traefik (Local) → Service
  ↓
HTTPS (Let's Encrypt cert)

User Remote (Internet)
  ↓
Cloudflare Tunnel
  ↓
Traefik (same cert)
  ↓
Service
  ↓
HTTPS (Let's Encrypt cert)
```

### Scenario 2 (Local Only)
```
User Local
  ↓
Pi-hole DNS: admin.local.example.com → 192.168.1.X
  ↓
Traefik (Local) → Service
  ↓
HTTPS (Let's Encrypt cert)

User Remote
  ↗
  Not accessible (no tunnel route)
```

---

## Advantages

✅ **Valid HTTPS Everywhere** - Certificates look identical to public websites  
✅ **Local Bypass** - Local clients skip Cloudflare tunnel (faster, lower latency)  
✅ **Single Cert Management** - Traefik handles all renewals automatically  
✅ **True Privacy** - Local-only services never exposed to internet  
✅ **DNS-01 Magic** - Let's Encrypt validates via Cloudflare DNS, not HTTP accessibility  
✅ **Scalable** - Add more services by just adding labels to new containers  

---

## Troubleshooting

### Certificate not renewing
Check Traefik logs:
```bash
docker logs traefik
```

### DNS not resolving locally
Check Pi-hole admin interface, verify A records are set correctly.

### Cloudflare tunnel not working
Verify tunnel is running: `cloudflared tunnel list`

### Certificate validation fails
Ensure Cloudflare API tokens have correct permissions:
- Zone Settings (Read)
- Zone DNS (Edit)

---

## References

- [Traefik Documentation](https://doc.traefik.io/)
- [Let's Encrypt DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
