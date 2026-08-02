# Instructivo: KYZ ADM Script (VPS AutoScript)

Script desarrollado y mantenido por JotchuaDevz. Instala y configura un servidor multiprotocolo completo (SSH, Xray, Hysteria, ZiVPN, UDP Custom, SlowDNS, SlipStream) sobre un VPS limpio, con panel de administración por menú.

Repositorio: https://github.com/emanuel666/autoscript

---

## 1. Requisitos previos

### 1.1 Servidor

- VPS con acceso root
- Sistema operativo soportado:
  - Debian 12 (recomendado)
  - Debian 11 (soporte legado)
  - Ubuntu 24.04 (soportado)
  - Ubuntu 22.04 (recomendado)
  - Ubuntu 20.04 (soporte legado)

Cualquier otro sistema operativo o versión no es compatible y el instalador se detendrá al detectarlo.

### 1.2 Dominio para Xray (opcional pero recomendado)

Se necesita un registro DNS tipo A apuntando la IP de tu VPS. Ejemplo:

```
vpn.tudominio.com    A    123.45.67.89
```

Si no cuentas con un dominio, puedes dejar el campo vacío durante la instalación y el script usará la IP pública del servidor directamente. En ese caso se generará un certificado autofirmado en lugar de uno de Let's Encrypt, y los clientes deberán activar la opción "allowInsecure" en la configuración TLS.

### 1.3 Subdominio NS para SlowDNS (obligatorio si se desea usar SlowDNS)

SlowDNS no funciona con un registro A normal. Requiere que un subdominio esté delegado como nameserver hacia tu servidor. Esto se configura con dos registros DNS:

```
ns.tudominio.com          NS    ns-server.tudominio.com
ns-server.tudominio.com   A     123.45.67.89
```

El valor que se ingresa en el script cuando pregunta "Ingresa el Nameserver de SlowDNS" es el registro delegado, en este ejemplo `ns.tudominio.com`.

Si no se configura este registro correctamente, SlowDNS no recibirá tráfico aunque el servicio esté instalado y corriendo.

### 1.4 Subdominio NS para SlipStream (opcional)

SlipStream es un túnel DNS adicional. Si se activa durante la instalación, requiere su propio subdominio con delegación NS, siguiendo el mismo esquema del punto 1.3, pero con un nombre distinto al usado para SlowDNS. Ejemplo:

```
ss.tudominio.com          NS    ss-server.tudominio.com
ss-server.tudominio.com   A     123.45.67.89
```

El script no permite usar el mismo dominio para SlowDNS y SlipStream, ya que el enrutador interno (dnsdist) distribuye el tráfico según el dominio de destino. Si ambos coinciden, uno de los dos túneles se queda sin tráfico.

---

## 2. Instalación

Existen cuatro métodos equivalentes para ejecutar el instalador. Se recomienda el método 4 porque conserva el archivo en el servidor, lo cual facilita reinstalaciones o revisión de errores.

### Opcion 1

```
wget -qO- https://raw.githubusercontent.com/emanuel666/autoscript/refs/heads/main/install.sh | bash
```

### Opcion 2

```
wget -qO xfc.sh https://raw.githubusercontent.com/emanuel666/autoscript/refs/heads/main/install.sh && bash install.sh
```

### Opcion 3

```
bash <(curl -sL https://raw.githubusercontent.com/emanuel666/autoscript/refs/heads/main/install.sh)
```

### Opcion 4 (recomendada)

```
wget -qO install.sh https://raw.githubusercontent.com/emanuel666/autoscript/refs/heads/main/install.sh
chmod +x install.sh
./install.sh
```

---

## 3. Flujo de instalación (qué preguntas hace el script)

1. Detecta el sistema operativo y valida que sea compatible.
2. Solicita el dominio o subdominio para Xray. Se puede dejar en blanco para usar la IP del servidor.
3. Si se ingresó un dominio, verifica que resuelva correctamente a la IP del servidor antes de continuar. Si no coincide, la instalación se detiene con un mensaje de error indicando que se debe corregir el registro A.
4. Solicita el certificado: automático vía Let's Encrypt si hay dominio válido, o autofirmado si se usa IP.
5. Solicita el nameserver para SlowDNS (ver sección 1.3). Trae un valor por defecto de ejemplo que debe reemplazarse por uno propio.
6. Pregunta si se desea instalar SlipStream. Si se acepta, solicita su propio subdominio NS (ver sección 1.4).
7. Solicita el valor de ofuscación (obfs) para Hysteria y ZiVPN, con un valor por defecto sugerido.
8. Instala y configura automáticamente:
   - SSH con Dropbear, Stunnel y SSLH
   - Xray-core con los inbounds de VLESS, VMess y Trojan
   - HAProxy para enrutamiento TLS y HTTP/2
   - Hysteria v1 y v2
   - ZiVPN
   - UDP Custom
   - SlowDNS y, si se activó, SlipStream
   - Cronjobs de expiración de cuentas para cada protocolo
   - Verificador de servicios y limitador de sesiones SSH
9. Al finalizar, reinicia el servidor automáticamente para aplicar todos los cambios.

---

## 4. Protocolos y puertos instalados

| Servicio | Puerto(s) |
|---|---|
| SSH (directo) | 22 |
| SSH (segundo puerto interno) | 299 |
| Stunnel (SSL sobre SSH) | 4443 |
| SSLH (multiplexor) | 666 (interno) |
| WebSocket Proxy | 10080, 25, 2082, 2086 |
| Xray (VLESS/VMess/Trojan TLS) | 443 |
| Xray (variantes sin TLS) | 80, 8080, 8880 |
| Hysteria (v1) | 36712/udp |
| Hysteria 2 | 36713/udp |
| UDP Custom | 36717/udp |
| ZiVPN | 5667 |
| Panel web interno (Nginx) | 85 |

Xray incluye variantes de VLESS, VMess y Trojan sobre TCP, WebSocket, gRPC, XHTTP y HTTPUpgrade, con y sin TLS, enrutadas mediante HAProxy según el path o el ALPN de la conexión.

---

## 5. Uso posterior a la instalación

Una vez reiniciado el servidor, se administra todo desde un panel de menú accesible con el comando:

```
menu
```

Desde ahí se pueden realizar, entre otras, las siguientes acciones:

- Crear, editar y eliminar usuarios de cada protocolo
- Obtener los enlaces de conexión (vmess://, vless://, trojan://, etc.) listos para importar en el cliente
- Cambiar el dominio o IP del servidor
- Cambiar el nameserver de SlowDNS
- Instalar o cambiar el dominio de SlipStream
- Iniciar, detener o reiniciar servicios individuales
- Acceder a herramientas de configuración avanzada

---

## 6. Notas y advertencias

- El script incluye un aviso de derechos reservados de Hex Applications que prohíbe la copia, modificación o redistribución sin autorización previa. Tomar esto en cuenta antes de redistribuir el código o el enlace de instalación fuera de los canales autorizados.
- Si se cambia el dominio o el nameserver después de haber compartido enlaces de conexión con usuarios, esos enlaces dejan de funcionar porque quedan atados al dominio y certificado usados en el momento de su creación.
- Es indispensable verificar que los registros DNS (A y NS según corresponda) estén correctamente propagados antes de ejecutar el instalador o antes de solicitar el certificado Let's Encrypt, de lo contrario la instalación fallará en ese paso.

---

## 7. Soporte

Canal de Telegram: https://t.me/FreeNet_KYZ
