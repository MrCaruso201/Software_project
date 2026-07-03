"""
Registrazione del servizio mDNS (Bonjour/Zeroconf).

Permette ai client iOS sulla stessa rete di scoprire il server
senza conoscerne l'IP in anticipo.
"""

import asyncio
import socket
from typing import Optional

from zeroconf import ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

from config import SERVICE_NAME, SERVICE_PORT, SERVICE_TYPE

zeroconf_instance: Optional[AsyncZeroconf] = None


def get_local_ip() -> str:
    """Restituisce l'IP locale della macchina."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    finally:
        s.close()


async def start_bonjour() -> None:
    """Registra il servizio mDNS sulla rete locale."""
    global zeroconf_instance
    local_ip = get_local_ip()
    print(f"📡 IP locale: {local_ip}")

    info = ServiceInfo(
        type_=SERVICE_TYPE,
        name=SERVICE_NAME,
        addresses=[socket.inet_aton(local_ip)],
        port=SERVICE_PORT,
        properties={"version": "1.0"},
        server=f"{socket.gethostname()}.local.",
    )

    zeroconf_instance = AsyncZeroconf()
    await zeroconf_instance.async_register_service(info)
    print(f"✅ Bonjour attivo: '{SERVICE_NAME}' su {local_ip}:{SERVICE_PORT}")


async def stop_bonjour() -> None:
    """Deregistra il servizio mDNS e chiude Zeroconf."""
    if zeroconf_instance:
        await zeroconf_instance.async_close()
        print("🔴 Bonjour fermato")
