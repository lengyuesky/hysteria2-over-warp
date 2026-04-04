from pathlib import Path

ROOT = Path(__file__).resolve().parent

entrypoint = (ROOT / "docker" / "entrypoint.sh").read_text()
compose = (ROOT / "docker-compose.yml").read_text()
dockerfile = (ROOT / "Dockerfile").read_text()
readme = (ROOT / "README.md").read_text()
readme_zh = (ROOT / "README.zh-CN.md").read_text()
spec = (ROOT / "docs" / "superpowers" / "specs" / "2026-04-03-warp-debian-macvlan-design.md").read_text()

checks = [
    ("entrypoint campus login stage", "run_campus_login_script()" in entrypoint),
    ("entrypoint warp auto connect stage", "auto_connect_warp()" in entrypoint),
    ("entrypoint hysteria start stage", "start_hysteria()" in entrypoint),
    (
        "entrypoint dhcpv6 happens before campus login",
        entrypoint.index('log "requesting optional dhcpv6 lease"')
        < entrypoint.index('log "running optional campus login stage"'),
    ),
    ("compose campus login is optional", "CAMPUS_LOGIN_SCRIPT:" not in compose),
    ("compose loads env file", "env_file:" in compose),
    ("compose uses env password", "HY2_PASSWORD: ${HY2_PASSWORD}" in compose),
    ("compose keeps user input minimal", "WARP_AUTO_CONNECT:" not in compose and "WARP_CONNECT_DELAY:" not in compose and "HY2_SNI:" not in compose),
    ("compose hysteria config volume", "/config/hysteria" in compose),
    ("compose hysteria port", "8443/udp" in compose),
    ("env example exists", (ROOT / ".env.example").exists()),
    ("dockerfile installs openssl", "openssl" in dockerfile),
    ("dockerfile copies hysteria config", "hysteria" in dockerfile.lower()),
    ("readme mentions campus login script", "campus login script" in readme.lower()),
    ("readme mentions auto connect", "30 seconds" in readme.lower()),
    ("readme mentions bing sni", "bing.com" in readme.lower()),
    ("readme zh mentions campus script", "校园网登录脚本" in readme_zh),
    ("readme zh mentions 30 second delay", "30 秒" in readme_zh),
    ("spec mentions hysteria 2", "Hysteria 2" in spec),
]

failed = [name for name, ok in checks if not ok]
if failed:
    raise SystemExit("contract check failed:\n- " + "\n- ".join(failed))

print("startup contract checks passed")
