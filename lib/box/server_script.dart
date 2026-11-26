// GENERATED from server/box.sh by tools/embed_server.py. Do not edit.
const String boxServerScript = r'''
#!/usr/bin/env bash
# Wokok Box server agent: Deploy compartments + Tunnel edge.
# Uploaded and driven by the Wokok Box app over SSH; also usable by hand.
set -euo pipefail

BOX_VERSION="1.0.0"
ETC=/etc/wokok-box
APPS="$ETC/apps"
SECRETS="$ETC/secrets"
SITES="$ETC/caddy"
OPT=/opt/wokok-box
LOG=/var/log/wokok-box.log
SELF=/usr/local/bin/wokok-box
VPN_INSTALLER="https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/server/install.sh"
EDGE_PORT=8444
CADDY_ALT_PORT=9443
MARK="# managed by wokok-box"

say()  { printf '> %s\n' "$*"; }
ok()   { printf '+ %s\n' "$*"; }
die()  { printf '! %s\n' "$*" >&2; exit 1; }
json() { printf '@@JSON %s\n' "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -eq 0 ] || die "Нужны права root (или sudo без пароля)"
mkdir -p "$APPS" "$SECRETS" "$SITES" "$OPT"
chmod 700 "$SECRETS"
touch "$ETC/domains.lst" "$LOG"

valid_name()   { [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || die "Имя: латиница в нижнем регистре, цифры и дефис, до 31 символа"; }
valid_domain() { [[ "${1:-}" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$ ]] || die "Неверный домен: ${1:-}"; }
valid_git()    { [[ "${1:-}" =~ ^https://[A-Za-z0-9._~/@:%+-]+$ ]] || die "Нужен адрес репозитория вида https://..."; }
valid_port()   { [[ "${1:-}" =~ ^[0-9]{2,5}$ ]] && [ "$1" -le 65535 ] || die "Неверный порт: ${1:-}"; }

pkg() {
  has apt-get || die "Поддерживаются Debian и Ubuntu (нужен apt)"
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
  apt-get -o DPkg::Lock::Timeout=180 install -y --no-install-recommends "$@" >>"$LOG" 2>&1 && return 0
  apt-get -o DPkg::Lock::Timeout=180 update >>"$LOG" 2>&1 || true
  apt-get -o DPkg::Lock::Timeout=180 install -y --no-install-recommends "$@" >>"$LOG" 2>&1 \
    || die "Не удалось установить: $* (подробности в $LOG)"
}
need() { local c="$1" p="${2:-$1}"; has "$c" || { say "Устанавливаю $p"; pkg "$p" ca-certificates; }; }

public_ip() {
  [ -s "$ETC/ip" ] && { cat "$ETC/ip"; return; }
  local ip=""
  has curl && ip="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ "$ip" =~ ^[0-9.]+$ ]] || die "Не удалось узнать внешний IP сервера"
  printf '%s' "$ip" | tee "$ETC/ip"
}
default_domain() { local ip; ip="$(public_ip)"; printf '%s.%s.sslip.io' "$1" "${ip//./-}"; }

listener() { (ss -ltnpH "sport = :$1" 2>/dev/null || true) | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -1; }
free_port() {
  local p
  for p in $(seq 4300 4999); do
    [ -z "$( (ss -ltnH "sport = :$p" 2>/dev/null || true) )" ] && ! grep -qs "^PORT=$p$" "$APPS"/*.env && { echo "$p"; return; }
  done
  die "Нет свободных портов"
}
firewall() {
  if has ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
    local p; for p in "$@"; do ufw allow "$p/tcp" >/dev/null; done
  fi
}

# ---------------------------------------------------------------- edge ----
# One public :443 shared by the VPN (Reality) and HTTPS sites. Reality hands
# every non-VPN handshake to its "dest"; HAProxy there routes by SNI: our
# domains go to Caddy, everything else to the decoy site as before.
install_caddy() {
  has caddy && return 0
  say "Устанавливаю Caddy (HTTPS-сертификаты получает сам)"
  if ! ( export DEBIAN_FRONTEND=noninteractive; apt-get update >>"$LOG" 2>&1; apt-get install -y caddy >>"$LOG" 2>&1 ); then
    need curl
    local arch; case "$(uname -m)" in aarch64|arm64) arch=arm64 ;; armv7*) arch=arm ;; *) arch=amd64 ;; esac
    curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=$arch" -o /usr/bin/caddy || die "Не удалось скачать Caddy"
    chmod 755 /usr/bin/caddy
    id caddy >/dev/null 2>&1 || useradd -r -m -d /var/lib/caddy -s /usr/sbin/nologin caddy
    cat > /etc/systemd/system/caddy.service <<'UNIT'
[Unit]
Description=Caddy
After=network-online.target
[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
  fi
  mkdir -p /etc/caddy
}

write_caddyfile() { # $1 = https port
  local f=/etc/caddy/Caddyfile
  if [ -s "$f" ] && ! grep -qF "$MARK" "$f" && ! grep -q '/usr/share/caddy' "$f"; then
    die "На сервере уже есть своя настройка Caddy ($f). Wokok Box не будет её перезаписывать."
  fi
  { echo "$MARK"; echo "{"
    echo "  https_port $1"
    echo "  servers {"; echo "    protocols h1 h2"; echo "  }"
    echo "}"; echo "import $SITES/*.caddy"
  } > "$f"
}

xray_on_443() { [ "$(listener 443)" = xray ]; }

edge_behind_vpn() {
  need haproxy
  local cfg=/etc/haproxy/haproxy.cfg
  if [ -f "$cfg" ] && ! grep -qF "$MARK" "$cfg" && grep -qE '^(frontend|listen)[[:space:]]' "$cfg"; then
    die "На сервере уже настроен свой HAProxy, не буду его перезаписывать"
  fi
  local sni; sni="$(jq -r .sni /etc/wokok/server.json)"
  valid_domain "$sni"
  cat > /etc/haproxy/haproxy.cfg <<EOF
$MARK
global
  maxconn 4096
defaults
  mode tcp
  timeout connect 5s
  timeout client 1h
  timeout server 1h
frontend wokok_edge
  bind 127.0.0.1:$EDGE_PORT
  tcp-request inspect-delay 5s
  tcp-request content accept if { req.ssl_hello_type 1 }
  use_backend web if { req.ssl_sni -i -m end .sslip.io }
  use_backend web if { req.ssl_sni -i -f $ETC/domains.lst }
  default_backend decoy
backend web
  server caddy 127.0.0.1:$CADDY_ALT_PORT
backend decoy
  server site $sni:443
EOF
  systemctl enable haproxy >/dev/null 2>&1 || true
  systemctl restart haproxy || die "HAProxy не запустился"
  if ! grep -qF "127.0.0.1:$EDGE_PORT" /usr/local/bin/wokok; then
    cp /usr/local/bin/wokok "$ETC/wokok.cli.bak"
    sed -i "s|dest:(\$sni+\":443\")|dest:\"127.0.0.1:$EDGE_PORT\"|" /usr/local/bin/wokok
    grep -qF "127.0.0.1:$EDGE_PORT" /usr/local/bin/wokok || die "Версия команды wokok не распознана, VPN оставлен без изменений"
    wokok render >>"$LOG" 2>&1 && systemctl restart xray && sleep 1 && systemctl is-active --quiet xray || {
      cp "$ETC/wokok.cli.bak" /usr/local/bin/wokok
      wokok render >>"$LOG" 2>&1 || true; systemctl restart xray || true
      die "Не удалось подружить VPN и сайты, вернул прежние настройки VPN"
    }
  fi
}

edge_ensure() {
  need jq
  install_caddy
  if xray_on_443; then
    local owner; owner="$(listener 80)"
    [ -z "$owner" ] || [ "$owner" = caddy ] || die "Порт 80 занят программой $owner"
    write_caddyfile "$CADDY_ALT_PORT"
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || die "Caddy не запустился"
    edge_behind_vpn
  else
    local p owner
    for p in 80 443; do
      owner="$(listener "$p")"
      [ -z "$owner" ] || [ "$owner" = caddy ] || die "Порт $p занят программой $owner"
    done
    write_caddyfile 443
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl reload caddy 2>/dev/null || systemctl restart caddy || die "Caddy не запустился"
  fi
  firewall 80 443
}

site_publish() { # name domain body
  local name="$1" domain="$2" body="$3"
  valid_domain "$domain"
  edge_ensure
  if grep -lsE "^$domain \{" "$SITES"/*.caddy 2>/dev/null | grep -vqx "$SITES/$name.caddy"; then
    die "Домен $domain уже занят другим отсеком"
  fi
  case "$domain" in *.sslip.io) ;; *) grep -qxF "$domain" "$ETC/domains.lst" || echo "$domain" >> "$ETC/domains.lst" ;; esac
  has haproxy && systemctl is-active --quiet haproxy && systemctl reload haproxy || true
  [ -f "$SITES/$name.caddy" ] && cp "$SITES/$name.caddy" "$SITES/$name.bak"
  printf '%s {\n  encode gzip\n  %s\n}\n' "$domain" "$body" > "$SITES/$name.caddy"
  if ! caddy validate --config /etc/caddy/Caddyfile >>"$LOG" 2>&1; then
    rm -f "$SITES/$name.caddy"; [ -f "$SITES/$name.bak" ] && mv "$SITES/$name.bak" "$SITES/$name.caddy"
    die "Caddy отклонил настройку сайта"
  fi
  rm -f "$SITES/$name.bak"
  systemctl reload caddy || systemctl restart caddy
}
site_unpublish() {
  [ -f "$SITES/$1.caddy" ] || return 0
  local domain; domain="$(awk 'NR==1{print $1}' "$SITES/$1.caddy")"
  rm -f "$SITES/$1.caddy"
  sed -i "/^${domain//./\\.}\$/d" "$ETC/domains.lst"
  systemctl reload caddy 2>/dev/null || true
}

# ---------------------------------------------------------------- apps ----
app_get() { sed -n "s/^$2=//p" "$APPS/$1.env" 2>/dev/null | head -1; }
app_set() { local f="$APPS/$1.env"; touch "$f"; sed -i "/^$2=/d" "$f"; printf '%s=%s\n' "$2" "$3" >> "$f"; }

fetch_source() { # source destdir
  local src="$1" dst="$2"
  case "$src" in
    git:*) valid_git "${src#git:}"; need git
           git clone -q --depth 1 -- "${src#git:}" "$dst" >>"$LOG" 2>&1 || die "Не удалось скачать репозиторий" ;;
    dir:/tmp/wokok-up-*) mkdir -p "$dst"; cp -a "${src#dir:}/." "$dst/"; rm -rf -- "${src#dir:}" ;;
    zip:/tmp/wokok-up-*) need unzip; mkdir -p "$dst"; unzip -q "${src#zip:}" -d "$dst" || die "Архив повреждён"
           rm -f -- "${src#zip:}"
           local only; only="$(find "$dst" -mindepth 1 -maxdepth 1)"
           if [ "$(printf '%s\n' "$only" | wc -l)" = 1 ] && [ -d "$only" ]; then cp -a "$only/." "$dst/"; rm -rf "$only"; fi ;;
    *) die "Неизвестный источник" ;;
  esac
}

detect_runtime() {
  if [ -f "$1/Dockerfile" ]; then echo docker
  elif [ -f "$1/package.json" ]; then echo node
  elif [ -f "$1/requirements.txt" ] || ls "$1"/*.py >/dev/null 2>&1; then echo python
  else die "Не понял, что это за бот: нужен package.json, requirements.txt, *.py или Dockerfile"; fi
}
entry_file() {
  local f
  for f in "${@:2}"; do [ -f "$1/$f" ] && { echo "$f"; return; }; done
  die "Не нашёл главный файл. Ожидал один из: ${*:2}"
}

install_docker() {
  has docker && return 0
  say "Устанавливаю Docker"
  pkg docker.io
  systemctl enable --now docker >/dev/null 2>&1 || true
  has docker || die "Docker не установился"
}
app_user() { id wokokapps >/dev/null 2>&1 || useradd -r -m -d "$OPT/.home" -s /usr/sbin/nologin wokokapps; }

write_unit() { # name workdir command
  cat > "/etc/systemd/system/wb-$1.service" <<EOF
[Unit]
Description=Wokok Box app $1
After=network-online.target
[Service]
User=wokokapps
WorkingDirectory=$2
EnvironmentFile=-$SECRETS/$1.env
ExecStart=$3
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

# Prepare a release (dependencies, image) and start it. Returns non-zero on failure.
activate() { # name release_dir
  local name="$1" rel="$2" type docker port cmd entry
  type="$(app_get "$name" TYPE)"; docker="$(app_get "$name" DOCKER)"; port="$(app_get "$name" PORT)"
  ln -sfn "$rel" "$OPT/$name/current"
  if [ "$type" = site ]; then
    if [ "$docker" = 1 ]; then
      install_docker
      docker rm -f "wb-$name" >/dev/null 2>&1 || true
      if [ -f "$rel/Dockerfile" ]; then
        docker build -q -t "wb-$name" "$rel" >>"$LOG" 2>&1 || return 1
        docker run -d --name "wb-$name" --restart unless-stopped -e PORT=8080 -p "127.0.0.1:$port:8080" "wb-$name" >>"$LOG" 2>&1 || return 1
      else
        docker run -d --name "wb-$name" --restart unless-stopped -p "127.0.0.1:$port:80" -v "$rel:/srv:ro" caddy:alpine \
          caddy file-server --root /srv --listen :80 >>"$LOG" 2>&1 || return 1
      fi
      sleep 4
      [ "$(docker inspect -f '{{.State.Running}}' "wb-$name" 2>/dev/null)" = true ] || return 1
      site_publish "$name" "$(app_get "$name" DOMAIN)" "reverse_proxy 127.0.0.1:$port" || return 1
    else
      local root="$rel" d
      for d in dist public build _site; do [ -f "$rel/$d/index.html" ] && { root="$rel/$d"; break; }; done
      [ -f "$root/index.html" ] || { say "Нет index.html"; return 1; }
      chmod -R a+rX "$OPT/$name"
      site_publish "$name" "$(app_get "$name" DOMAIN)" "root * $root
  @hidden path */.*
  respond @hidden 404
  file_server" || return 1
    fi
    return 0
  fi

  # bot
  local runtime; runtime="$(detect_runtime "$rel")" || return 1
  if [ "$docker" = 1 ] || [ "$runtime" = docker ]; then
    install_docker
    app_set "$name" DOCKER 1
    docker rm -f "wb-$name" >/dev/null 2>&1 || true
    local image="wb-$name" args=()
    if [ "$runtime" = docker ]; then docker build -q -t "$image" "$rel" >>"$LOG" 2>&1 || return 1
    elif [ "$runtime" = node ]; then
      image=node:22-alpine; entry="$(entry_file "$rel" bot.js index.js main.js)" || return 1
      docker run --rm -v "$rel:/app" -w /app "$image" npm install --omit=dev >>"$LOG" 2>&1 || return 1
      args=(-v "$rel:/app" -w /app); cmd="node $entry"
    else
      image=python:3.12-slim; entry="$(entry_file "$rel" bot.py main.py app.py)" || return 1
      args=(-v "$rel:/app" -w /app)
      cmd="sh -c 'if [ -f requirements.txt ]; then pip install -q -r requirements.txt; fi; exec python -u $entry'"
    fi
    eval "docker run -d --name 'wb-$name' --restart unless-stopped --env-file '$SECRETS/$name.env' \"\${args[@]}\" '$image' ${cmd:-}" >>"$LOG" 2>&1 || return 1
    sleep 8
    [ "$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "wb-$name" 2>/dev/null)" = "true 0" ]
    return
  fi
  app_user
  if [ "$runtime" = node ]; then
    need node nodejs; need npm
    entry="$(entry_file "$rel" bot.js index.js main.js)" || return 1
    chown -R wokokapps: "$rel"
    (cd "$rel" && runuser -u wokokapps -- env HOME="$OPT/.home" npm install --omit=dev) >>"$LOG" 2>&1 || return 1
    cmd="$(command -v node) $entry"
  else
    need python3; python3 -c 'import ensurepip' 2>/dev/null || pkg python3-venv
    entry="$(entry_file "$rel" bot.py main.py app.py)" || return 1
    python3 -m venv "$rel/.venv" >>"$LOG" 2>&1 || return 1
    if [ -f "$rel/requirements.txt" ]; then "$rel/.venv/bin/pip" install -q -r "$rel/requirements.txt" >>"$LOG" 2>&1 || return 1; fi
    chown -R wokokapps: "$rel"
    cmd="$rel/.venv/bin/python -u $entry"
  fi
  write_unit "$name" "$rel" "$cmd"
  systemctl enable "wb-$name" >/dev/null 2>&1 || true
  systemctl restart "wb-$name" || return 1
  sleep 6
  systemctl is-active --quiet "wb-$name" && [ "$(systemctl show -p NRestarts --value "wb-$name")" = 0 ]
}

deploy() { # name  (source already stored in env)
  local name="$1" src rel prev=""
  src="$(app_get "$name" SRC)"
  mkdir -p "$OPT/$name/releases"; chmod 755 "$OPT" "$OPT/$name" "$OPT/$name/releases"
  [ -L "$OPT/$name/current" ] && prev="$(readlink -f "$OPT/$name/current")"
  rel="$OPT/$name/releases/$(date +%Y%m%d%H%M%S)"
  say "Готовлю новую версию"
  fetch_source "$src" "$rel"
  if ( activate "$name" "$rel" ); then
    [ -d "$rel/.git" ] && app_set "$name" COMMIT "$(git -C "$rel" rev-parse HEAD 2>/dev/null || true)"
    app_set "$name" PREV "$prev"
    # keep the three newest releases
    ls -1dt "$OPT/$name"/releases/* 2>/dev/null | tail -n +4 | xargs -r rm -rf
    ok "Отсек $name работает"
  else
    logs "$name" 15 || true
    if [ -n "$prev" ] && [ -d "$prev" ]; then
      say "Новая версия не запустилась, возвращаю прежнюю"
      rm -rf "$rel"
      ( activate "$name" "$prev" ) || die "И прежняя версия не стартует"
      die "Обновление отменено: работает прежняя версия"
    fi
    remove_app "$name"
    die "Не запустилось. Всё, что успел создать для $name, убрано"
  fi
}

create_app() { # type name source domain
  local type="$1" name="$2" src="$3" domain="${4:-}"
  valid_name "$name"
  [ -f "$APPS/$name.env" ] && [ "$(app_get "$name" TYPE)" != "$type" ] && die "Имя $name уже занято"
  case "$src" in git:*) valid_git "${src#git:}" ;; dir:/tmp/wokok-up-*|zip:/tmp/wokok-up-*) ;; *) die "Неизвестный источник" ;; esac
  app_set "$name" TYPE "$type"; app_set "$name" SRC "$src"; app_set "$name" DOCKER "${WB_DOCKER:-0}"
  [ -n "$(app_get "$name" PORT)" ] || app_set "$name" PORT "$(free_port)"
  if [ "$type" = site ]; then
    [ -n "$domain" ] || domain="$(default_domain "$name")"
    valid_domain "$domain"; app_set "$name" DOMAIN "$domain"
  else
    ( umask 077; grep -E '^[A-Za-z_][A-Za-z0-9_]*=' > "$SECRETS/$name.env" || true )
  fi
  deploy "$name"
  [ "$type" = site ] && json "{\"url\":\"https://$domain\"}"
  return 0
}

update_app() {
  local name="$1" src cur new
  valid_name "$name"; [ -f "$APPS/$name.env" ] || die "Нет такого отсека"
  src="$(app_get "$name" SRC)"
  case "$src" in git:*) ;; *) die "Автообновление работает только с GitHub-репозиторием" ;; esac
  cur="$(app_get "$name" COMMIT)"
  new="$(git ls-remote -- "${src#git:}" HEAD 2>/dev/null | awk '{print $1}')"
  [ -n "$new" ] || die "Репозиторий недоступен"
  if [ "$new" = "$cur" ]; then ok "Уже последняя версия"; return 0; fi
  # a commit that failed once is not retried every five minutes
  if [ "$new" = "$(app_get "$name" BADCOMMIT)" ]; then say "Коммит ${new:0:7} уже не запустился, жду следующий"; return 0; fi
  app_set "$name" BADCOMMIT "$new"
  ( deploy "$name" ) || return 1
  app_set "$name" BADCOMMIT ""
}

autoupdate() {
  local name="$1" mode="$2"
  valid_name "$name"; [ -f "$APPS/$name.env" ] || die "Нет такого отсека"
  if [ "$mode" = on ]; then
    case "$(app_get "$name" SRC)" in git:*) ;; *) die "Нужен источник из GitHub" ;; esac
    cat > /etc/systemd/system/wokok-box-update@.service <<EOF
[Unit]
Description=Wokok Box update %i
[Service]
Type=oneshot
ExecStart=$SELF update %i
EOF
    cat > /etc/systemd/system/wokok-box-update@.timer <<'EOF'
[Unit]
Description=Wokok Box update timer %i
[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now "wokok-box-update@$name.timer" >/dev/null 2>&1 || die "Таймер не включился"
    app_set "$name" AUTO 1; ok "Новые коммиты будут выкатываться сами"
  else
    systemctl disable --now "wokok-box-update@$name.timer" >/dev/null 2>&1 || true
    app_set "$name" AUTO 0; ok "Автообновление выключено"
  fi
}

rollback() {
  local name="$1" prev cur
  valid_name "$name"
  prev="$(app_get "$name" PREV)"
  [ -n "$prev" ] && [ -d "$prev" ] || die "Прежней версии нет"
  cur="$(readlink -f "$OPT/$name/current")"
  autoupdate "$name" off >/dev/null 2>&1 || true
  ( activate "$name" "$prev" ) || { ( activate "$name" "$cur" ) || true; die "Прежняя версия не запустилась"; }
  app_set "$name" PREV "$cur"
  ok "Вернул прежнюю версию (автообновление выключено, чтобы она не перезаписалась)"
}

remove_app() {
  local name="$1"; valid_name "$name"
  systemctl disable --now "wokok-box-update@$name.timer" >/dev/null 2>&1 || true
  systemctl disable --now "wb-$name" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/wb-$name.service"; systemctl daemon-reload || true
  has docker && docker rm -f "wb-$name" >/dev/null 2>&1 || true
  site_unpublish "$name"
  rm -rf "$OPT/${name:?}" "$APPS/$name.env" "$SECRETS/$name.env"
}

logs() {
  local name="$1" n="${2:-40}"; valid_name "$name"
  if [ "$(app_get "$name" DOCKER)" = 1 ]; then docker logs --tail "$n" "wb-$name" 2>&1 || true
  elif [ -f "/etc/systemd/system/wb-$name.service" ]; then journalctl -u "wb-$name" -n "$n" --no-pager 2>&1 || true
  else journalctl -u caddy -n "$n" --no-pager 2>&1 || true; fi
}

app_active() {
  local name="$1"
  if [ "$(app_get "$name" DOCKER)" = 1 ] || [ "$(app_get "$name" TYPE)" = recipe-docker ]; then
    [ "$(docker inspect -f '{{.State.Running}}' "wb-$name" 2>/dev/null)" = true ]
  elif [ "$(app_get "$name" TYPE)" = site ]; then [ -f "$SITES/$name.caddy" ] && systemctl is-active --quiet caddy
  else systemctl is-active --quiet "wb-$name"; fi
}

# ---------------------------------------------------------------- recipes --
recipe_docker() { # name domain-or-empty container-port image [docker args...]
  local name="$1" domain="$2" cport="$3" image="$4"; shift 4
  install_docker
  local port; port="$(app_get "$name" PORT)"; [ -n "$port" ] || port="$(free_port)"
  docker rm -f "wb-$name" >/dev/null 2>&1 || true
  docker run -d --name "wb-$name" --restart unless-stopped -p "127.0.0.1:$port:$cport" "$@" "$image" >>"$LOG" 2>&1 \
    || die "Контейнер не запустился"
  app_set "$name" TYPE recipe-docker; app_set "$name" PORT "$port"; app_set "$name" DOCKER 1
  [ -n "$domain" ] || domain="$(default_domain "$name")"
  app_set "$name" DOMAIN "$domain"
  ( site_publish "$name" "$domain" "reverse_proxy 127.0.0.1:$port" ) || { remove_app "$name"; die "Не удалось опубликовать"; }
  json "{\"url\":\"https://$domain\"}"
}

recipe() {
  case "$1" in
    shield)   pkg fail2ban; systemctl enable --now fail2ban >/dev/null 2>&1; ok "fail2ban отбивает подбор паролей" ;;
    updates)  pkg unattended-upgrades
              printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
              ok "Обновления безопасности ставятся сами" ;;
    turbo)    printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-wokok-bbr.conf
              sysctl -q --system >/dev/null 2>&1 || true
              [ "$(sysctl -n net.ipv4.tcp_congestion_control)" = bbr ] || die "Ядро сервера не поддерживает BBR"
              ok "BBR включён: сеть быстрее на плохих линиях" ;;
    swap)     if [ -n "$(swapon --noheadings 2>/dev/null)" ]; then ok "Подкачка уже есть"; else
                fallocate -l 1G /swapfile-wokok && chmod 600 /swapfile-wokok && mkswap /swapfile-wokok >/dev/null && swapon /swapfile-wokok \
                  || { rm -f /swapfile-wokok; die "Этот сервер не разрешает подкачку"; }
                echo '/swapfile-wokok none swap sw 0 0' >> /etc/fstab; ok "Добавил 1 ГБ подкачки"; fi ;;
    monitor)  recipe_docker monitor "" 3001 louislam/uptime-kuma:1 -v wb-monitor:/app/data
              ok "Uptime Kuma: откройте адрес и сразу создайте администратора" ;;
    notes)    recipe_docker notes "" 5230 neosmemo/memos:stable -v wb-notes:/var/opt/memos
              ok "Заметочная Memos: первый зарегистрированный становится хозяином" ;;
    files)    recipe_docker files "" 80 filebrowser/filebrowser:v2 -v wb-files:/srv -v wb-files-db:/database
              docker logs wb-files 2>&1 | grep -i password | tail -1 || true
              ok "File Browser: логин admin, пароль строкой выше (или admin). Смените его сразу!" ;;
    *) die "Нет такого рецепта" ;;
  esac
}

# ---------------------------------------------------------------- top level
cmd_check() {
  local os ram disk ip apps="" f n active
  os="$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
  ram="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
  disk="$(df -Pm / | awk 'NR==2{print $4}')"
  ip="$(public_ip)"
  for f in "$APPS"/*.env; do
    [ -f "$f" ] || continue; n="$(basename "$f" .env)"
    active=false; app_active "$n" && active=true
    apps="$apps${apps:+,}{\"name\":\"$n\",\"type\":\"$(app_get "$n" TYPE)\",\"active\":$active,\"domain\":\"$(app_get "$n" DOMAIN)\",\"auto\":$([ "$(app_get "$n" AUTO)" = 1 ] && echo true || echo false),\"docker\":$([ "$(app_get "$n" DOCKER)" = 1 ] && echo true || echo false),\"git\":$(case "$(app_get "$n" SRC)" in git:*) echo true ;; *) echo false ;; esac)}"
  done
  json "{\"version\":\"$BOX_VERSION\",\"os\":\"${os//\"/}\",\"arch\":\"$(uname -m)\",\"ramMb\":$ram,\"diskMb\":$disk,\"ip\":\"$ip\",\"apt\":$(has apt-get && echo true || echo false),\"port80\":\"$(listener 80)\",\"port443\":\"$(listener 443)\",\"vpn\":$([ -f /etc/wokok/server.json ] && echo true || echo false),\"caddy\":$(has caddy && echo true || echo false),\"docker\":$(has docker && echo true || echo false),\"apps\":[$apps]}"
}

cmd_key() { # authorize a fresh key for the login user and hand it to the app
  need ssh-keygen openssh-client
  local user="${SUDO_USER:-root}" home tmp
  home="$(getent passwd "$user" | cut -d: -f6)"
  tmp="$(mktemp -d)"
  ssh-keygen -q -t ed25519 -N '' -C "wokok-box" -f "$tmp/k"
  install -d -m 700 -o "$user" "$home/.ssh"
  touch "$home/.ssh/authorized_keys"
  cat "$tmp/k.pub" >> "$home/.ssh/authorized_keys"
  chown "$user" "$home/.ssh/authorized_keys"; chmod 600 "$home/.ssh/authorized_keys"
  json "{\"key\":\"$(base64 -w0 "$tmp/k")\"}"
  rm -rf "$tmp"
}

cmd_vpn() {
  need curl; need jq
  # free :443 for Reality if our web edge is sitting on it
  if [ "$(listener 443)" = caddy ] && grep -qF "$MARK" /etc/caddy/Caddyfile 2>/dev/null; then
    say "Освобождаю порт 443 для VPN"
    write_caddyfile "$CADDY_ALT_PORT"; systemctl restart caddy
  fi
  local tmp; tmp="$(mktemp)"
  curl -fsSL "$VPN_INSTALLER" -o "$tmp" || die "Не удалось скачать установщик VPN"
  bash -n "$tmp" || die "Установщик повреждён"
  local failed=0
  bash "$tmp" </dev/null || failed=1
  rm -f "$tmp"
  if ls "$SITES"/*.caddy >/dev/null 2>&1; then ( edge_ensure ) || say "Сайты требуют внимания: запустите «Доктор»"; fi
  [ "$failed" = 0 ] || die "VPN не установился"
  local ticket; ticket="$(wokok link 2>/dev/null | grep -oE 'wokok://[A-Za-z0-9_=-]+' | head -1 || true)"
  [ -n "$ticket" ] || die "VPN установлен, но талон не найден (sudo wokok link)"
  json "{\"ticket\":\"$ticket\"}"
}

cmd_doctor() {
  local f n bad=0
  say "Осматриваю сервер"
  [ "$(df -Pm / | awk 'NR==2{print $4}')" -gt 300 ] || { say "Мало места, чищу кэши"; apt-get clean >>"$LOG" 2>&1 || true; journalctl --vacuum-size=100M >>"$LOG" 2>&1 || true; has docker && docker image prune -f >>"$LOG" 2>&1 || true; }
  if [ -f /etc/wokok/server.json ]; then
    systemctl is-active --quiet xray || systemctl restart xray || true
    sleep 1; if systemctl is-active --quiet xray; then ok "VPN работает"; else say "VPN не стартует"; bad=1; fi
  fi
  # close tunnels whose agent is gone
  for f in "$SITES"/tun-*.caddy; do
    [ -f "$f" ] || continue
    local port; port="$(grep -oE '127\.0\.0\.1:[0-9]+' "$f" | head -1 | cut -d: -f2)"
    [ -n "$( (ss -ltnH "sport = :$port" 2>/dev/null || true) )" ] || { n="$(basename "$f" .caddy)"; site_unpublish "$n"; say "Убрал мёртвый туннель ${n#tun-}"; }
  done
  if ls "$SITES"/*.caddy >/dev/null 2>&1; then
    if ( edge_ensure ); then ok "HTTPS-вход работает"; else bad=1; fi
  fi
  for f in "$APPS"/*.env; do
    [ -f "$f" ] || continue; n="$(basename "$f" .env)"
    if app_active "$n"; then ok "$n работает"; continue; fi
    say "$n лежит, поднимаю"
    if [ "$(app_get "$n" DOCKER)" = 1 ]; then docker restart "wb-$n" >>"$LOG" 2>&1 || true
    elif [ -L "$OPT/$n/current" ]; then ( activate "$n" "$(readlink -f "$OPT/$n/current")" ) || true; fi
    sleep 3
    if app_active "$n"; then ok "$n снова работает"; else say "$n не поднялся, смотрите журнал"; bad=1; fi
  done
  if [ "$bad" = 0 ]; then ok "Сервер здоров"; else die "Остались проблемы"; fi
}

tunnel_open() { # name remote_port [domain]
  local name="$1" port="$2" domain="${3:-}"
  valid_name "$name"; valid_port "$port"
  [ -n "$domain" ] || domain="$(default_domain "$name")"
  site_publish "tun-$name" "$domain" "reverse_proxy 127.0.0.1:$port"
  json "{\"url\":\"https://$domain\"}"
}

install_self() { [ "$(readlink -f "$0")" = "$SELF" ] || install -m 755 "$0" "$SELF"; }
install_self

c="${1:-check}"; shift || true
case "$c" in
  version)      echo "$BOX_VERSION" ;;
  check)        cmd_check ;;
  key)          cmd_key ;;
  vpn)          cmd_vpn ;;
  site|bot)     create_app "$c" "${1:-}" "${2:-}" "${3:-}" ;;
  update)       update_app "${1:-}" ;;
  autoupdate)   autoupdate "${1:-}" "${2:-off}" ;;
  rollback)     rollback "${1:-}" ;;
  remove)       remove_app "${1:-}"; ok "Отсек удалён" ;;
  logs)         logs "${1:-}" "${2:-60}" ;;
  doctor)       cmd_doctor ;;
  recipe)       recipe "${1:-}" ;;
  tunnel-open)  tunnel_open "${1:-}" "${2:-}" "${3:-}" ;;
  tunnel-close) valid_name "${1:-}"; site_unpublish "tun-$1"; ok "Туннель закрыт" ;;
  *) die "Команды: check key vpn site bot update autoupdate rollback remove logs doctor recipe tunnel-open tunnel-close" ;;
esac
''';
