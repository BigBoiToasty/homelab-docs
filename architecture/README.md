# Architecture

How the homelab is built: the hardware and VM underneath, and how traffic gets in and out.

| Page | Read it for |
|---|---|
| [host-and-vm.md](host-and-vm.md) | Proxmox host and ZFS pools, VM 100 specs, guest agent, the two virtual disks and what's stored where, services running directly on the VM |
| [networking-and-security.md](networking-and-security.md) | Who can reach what (internet vs tailnet vs LAN), the nginx reverse-proxy flow, Cloudflare Tunnel, Tailscale, Playit, the VPN kill switch, every open port, security findings |

**The short version:**

- One Proxmox server, one Debian VM, 40 Docker containers.
- The **internet** can reach only the portfolio site (Cloudflare Tunnel) and the Minecraft/Terraria servers (Playit).
- Everything else is reached through **Tailscale**: the `*.example.com` names point at the server's Tailscale IP. It can also be reached from the home **LAN** by IP and port.
