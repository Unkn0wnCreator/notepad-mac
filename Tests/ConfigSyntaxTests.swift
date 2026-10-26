/*
 * Notepad für macOS – Tests für die Hervorhebung von Konfigurationsdateien.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// Kind of the token that covers `snippet` (first occurrence), or nil if uncolored.
private func configKind(of snippet: String, in text: String, language: String) -> TokenKind? {
    let ns = text as NSString
    let target = ns.range(of: snippet)
    precondition(target.location != NSNotFound, "\(snippet) not in sample")
    let tokens = SyntaxLanguage.named(language)!.tokens(in: ns)!
    return tokens.first { NSLocationInRange(target.location, $0.range) && NSMaxRange(target) <= NSMaxRange($0.range) }?.kind
}

private let tomlSample = #"""
# Projekt-Konfiguration
title = "TOML \"Beispiel\""
site."google.com" = true
"quoted key" = 'C:\Pfad'
physical.color = "orange"

[owner]
name = "Tom"
dob = 1979-05-27T07:32:00-08:00
lunch = 12:30:00
born = 1979-05-27

[[products.items]]
sku = 738_594_937
ratio = -6.5e+3
hex = 0xDEADBEEF
limit = +inf
missing = nan
desc = """
Mehrzeilig # kein Kommentar
"""
raw = '''
C:\Users\'''
inline = { x = 1, y = "zwei" }
ports = [
  8001,
  8002,
]

"""#

private let caddySample = #"""
{
	email admin@example.com
	admin off
}

(common) {
	encode zstd gzip
	log {
		output file /var/log/caddy/access.log
	}
}

example.com, www.example.com {
	import common
	root * /var/www/{host}
	@api path /api/*
	handle_path /api/* {
		reverse_proxy localhost:9000 {
			lb_policy round_robin
			header_up X-Real-IP {remote_host}
		}
	}
	header /static/* Cache-Control "max-age=3600"
	redir /alt /neu 301
	respond `Hallo {http.request.uri}` 200
	tls {$TLS_EMAIL}
	file_server browse # Verzeichnisliste
}

:8080 {
	respond "ok"
}

"""#

private let nginxSample = #"""
# Hauptkonfiguration
worker_processes auto;
events { worker_connections 1024; }

http {
    include mime.types;
    sendfile on;
    client_max_body_size 10m;
    keepalive_timeout 65s;

    upstream backend {
        server 127.0.0.1:8080 weight=5;
    }

    server {
        listen 443 ssl http2;
        server_name example.com www.example.com;
        root /var/www/html;

        location ~* \.(jpg|png)$ {
            expires 30d;
        }
        location = /health { return 200 "ok"; }
        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For ${proxy_add_x_forwarded_for};
            if ($request_method = POST) { return 405; }
        }
    }
}

"""#

private let apacheSample = #"""
# Virtueller Host
LoadModule rewrite_module modules/mod_rewrite.so
<VirtualHost *:80>
    ServerName example.com
    DocumentRoot "/var/www/html"
    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^/alt/(.*)$ https://%{HTTP_HOST}/neu/$1 [L,R=301]
    ErrorLog ${APACHE_LOG_DIR}/error.log
    Timeout 300
</VirtualHost>

"""#

private let systemdSample = #"""
# Beispiel-Dienst
[Unit]
Description=Notepad Sync
After=network-online.target

[Service]
Type=simple
User=%i
ExecStart=/usr/bin/sync --home %h --dir ${STATE_DIRECTORY}
Environment="LANG=de_DE.UTF-8"
Restart=on-failure
RestartSec=5s
MemoryMax=512M
NoNewPrivileges=yes
; alter Kommentar

[Install]
WantedBy=multi-user.target

"""#

private let hclSample = #"""
# Terraform
terraform {
  required_version = ">= 1.5"
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  count         = 2
  monitoring    = true
  tags = {
    Name = "web-${count.index}-${lookup(var.names, "x")}"
  }
  // Startskript
  user_data = <<-EOF
    #!/bin/bash
    echo "kein Kommentar"
  EOF
  /* Block
     Kommentar */
  ratio = 1.5e3
  owner = null
}

output "ip" {
  value = [for i in aws_instance.web : i.public_ip if i.public_ip != null]
}

"""#

private let dotenvSample = #"""
# Datenbank
DATABASE_URL=postgres://user:pass@localhost:5432/app?x=1
export API_KEY="geheim ${SUFFIX}"
GREETING='Hallo Welt'
HOME_DIR=${HOME}/app
PORT=8080
DEBUG=true # Inline-Kommentar

"""#

private let sshSample = #"""
# Eigene Hosts
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host *.intern !gateway.intern
    ProxyJump gateway.intern
    port 2222
    ControlPath ~/.ssh/cm-%r@%h:%p
    ForwardAgent no

Match host prod-*
    StrictHostKeyChecking ask

"""#

private let ignoreSample = ##"""
# Abhängigkeiten
node_modules/
*.log
**/build/**
!keep.log
debug?.txt
[Bb]in/
\#datei

"""##

func runConfigSyntaxTests() {
    print("== Konfigurationsdateien")

    let ids = ["toml", "caddyfile", "nginx", "apache", "systemd", "hcl", "dotenv", "ssh", "ignore"]
    check("Alle Konfigurationssprachen registriert", ids.allSatisfy { SyntaxLanguage.named($0) != nil })

    // MARK: Detection

    let ini = SyntaxLanguage.named("ini")!.id
    let nginxConf = "user www-data;\nworker_processes auto;\nhttp {\n  server {\n    listen 80;\n  }\n}\n"
    let nginxSnippet = "server\n{\n  listen 80;\n}\n"
    let apacheConf = "<VirtualHost *:80>\n  DocumentRoot /var/www\n</VirtualHost>\n"
    let detections: [(String, String, String?)] = [
        ("Cargo.toml", "", "toml"), ("pyproject.toml", "", "toml"), ("Cargo.lock", "", "toml"),
        ("Caddyfile", "", "caddyfile"), ("caddyfile", "", "caddyfile"), ("CADDYFILE", "", "caddyfile"),
        ("site.caddy", "", "caddyfile"), ("Caddyfile.dev", "", "caddyfile"),
        ("nginx.conf", "", "nginx"), ("/etc/nginx/nginx.conf", "", "nginx"), ("app.nginx", "", "nginx"),
        ("site.conf", nginxConf, "nginx"), ("default.conf", nginxSnippet, "nginx"),
        ("proxy.conf", "location /api {\n  proxy_pass http://x;\n}\n", "nginx"),
        ("/etc/nginx/sites-available/default", "", "nginx"),
        ("/etc/nginx/conf.d/gzip.conf", "gzip on;\n", "nginx"),
        (".htaccess", "", "apache"), ("/srv/www/.htaccess", "", "apache"), ("httpd.conf", "", "apache"),
        ("apache2.conf", "", "apache"), ("vhost.conf", apacheConf, "apache"),
        ("modules.conf", "LoadModule ssl_module mod_ssl.so\n", "apache"),
        ("/etc/apache2/sites-available/000-default.conf", "", "apache"),
        ("plain.conf", "key = value\nname = x\n", ini), ("my.cnf", "[mysqld]\nport = 3306\n", ini),
        ("empty.conf", "", ini), ("settings.ini", "", ini),
        ("app.service", "", "systemd"), ("app.socket", "", "systemd"), ("backup.timer", "", "systemd"),
        ("home.mount", "", "systemd"), ("home.automount", "", "systemd"), ("watch.path", "", "systemd"),
        ("multi-user.target", "", "systemd"), ("user.slice", "", "systemd"), ("run.scope", "", "systemd"),
        ("file.swap", "", "systemd"), ("10-eth.network", "", "systemd"), ("br0.netdev", "", "systemd"),
        ("10-eth.link", "", "systemd"),
        ("/etc/systemd/system/nginx.service.d/override.conf", "[Service]\n", "systemd"),
        ("/etc/systemd/journald.conf", "[Journal]\n", "systemd"),
        ("main.tf", "", "hcl"), ("prod.tfvars", "", "hcl"), ("config.hcl", "", "hcl"), ("job.nomad", "", "hcl"),
        (".env", "", "dotenv"), (".env.local", "", "dotenv"), (".env.production", "", "dotenv"),
        ("/app/.env.development.local", "", "dotenv"), ("app.env", "", "dotenv"),
        (".envrc", "", nil), (".env.json", "", "json"),
        ("ssh_config", "", "ssh"), ("sshd_config", "", "ssh"), ("/etc/ssh/sshd_config", "", "ssh"),
        ("/Users/m/.ssh/config", "", "ssh"), ("~/.ssh/config", "", "ssh"),
        ("/etc/ssh/sshd_config.d/50-cloud.conf", "", "ssh"),
        ("config", "Host x\n", nil), ("/project/config", "", nil), ("/project/.git/config", "", nil),
        (".gitignore", "", "ignore"), (".dockerignore", "", "ignore"), (".npmignore", "", "ignore"),
        (".prettierignore", "", "ignore"), (".eslintignore", "", "ignore"), (".hgignore", "", "ignore"),
        ("/repo/sub/.gitignore", "", "ignore"), ("Dockerfile.dockerignore", "", "ignore"),
        ("Dockerfile", "", "dockerfile"), ("Dockerfile.prod", "", "dockerfile"), ("api.Dockerfile", "", "dockerfile"),
        ("Containerfile.dev", "", "dockerfile"),
        (".babelrc", "  {\"presets\": []}", "json"), (".eslintrc", "\n{\n}", "json"),
        (".prettierrc", "semi: false\n", "yaml"), (".prettierrc", "", "yaml"),
        ("docker-compose.yml", "", "yaml"), ("docker-compose.prod.yml", "", "yaml"),
        ("notes.txt", "", nil), ("main.swift", "", "swift"), ("Makefile", "", "makefile"),
    ]
    for (fileName, sample, expected) in detections {
        let detected = SyntaxLanguage.detect(fileName: fileName, sample: sample as NSString)?.id
        check("Erkennung \(fileName)\(sample.isEmpty ? "" : " (Inhalt)")", detected == expected, detected ?? "nil")
    }

    // MARK: Highlighting

    func expect(_ language: String, _ text: String, _ cases: [(String, TokenKind?)]) {
        for (snippet, kind) in cases {
            let actual = configKind(of: snippet, in: text, language: language)
            check("\(language): \(snippet)", actual == kind, actual.map { "\($0)" } ?? "nil")
        }
    }

    expect("toml", tomlSample, [
        ("Projekt-Konfiguration", .comment), ("[owner]", .tag), ("[[products.items]]", .tag),
        ("title", .property), (#"site."google.com""#, .property), (#""quoted key""#, .property),
        ("physical.color", .property), (#""TOML \"Beispiel\"""#, .string), ("'C:\\Pfad'", .string),
        ("true", .keyword), ("1979-05-27T07:32:00-08:00", .number), ("12:30:00", .number),
        ("1979-05-27", .number), ("born", .property), ("738_594_937", .number), ("-6.5e+3", .number), ("0xDEADBEEF", .number),
        ("+inf", .number), ("nan", .number), ("# kein Kommentar", .string), ("C:\\Users\\", .string),
        ("\"zwei\"", .string), ("8001", .number), ("ports", .property),
    ])
    expect("caddyfile", caddySample, [
        ("example.com, www.example.com", .tag), (":8080", .tag), ("(common)", .tag),
        ("email", .keyword), ("off", .keyword), ("admin@example.com", nil), ("encode", .keyword), ("reverse_proxy", .keyword),
        ("handle_path", .keyword), ("file_server", .keyword), ("lb_policy", .keyword), ("header_up", .keyword),
        ("@api", .variable), ("{host}", .variable), ("{remote_host}", .variable),
        ("{http.request.uri}", .string), ("{$TLS_EMAIL}", .variable), ("\"max-age=3600\"", .string),
        ("`Hallo", .string), ("# Verzeichnisliste", .comment), ("localhost:9000", nil),
        ("/var/log/caddy/access.log", nil),
    ])
    expect("nginx", nginxSample, [
        ("# Hauptkonfiguration", .comment), ("worker_processes", .keyword), ("events", .keyword),
        ("worker_connections", .keyword), ("http", .keyword), ("upstream", .keyword), ("server", .keyword),
        ("location", .keyword), ("~*", .keyword), ("return", .keyword),
        ("proxy_pass", .keyword), ("$host", .variable), ("${proxy_add_x_forwarded_for}", .variable),
        ("$request_method", .variable), ("\"ok\"", .string), ("10m", .number), ("65s", .number),
        ("1024", .number), ("127.0.0.1", .number), ("server_name", .keyword),
        ("example.com", nil),
    ])
    expect("apache", apacheSample, [
        ("# Virtueller Host", .comment), ("<VirtualHost", .tag), ("</VirtualHost", .tag), ("<Directory", .tag),
        ("ServerName", .keyword), ("LoadModule", .keyword), ("RewriteRule", .keyword), ("\"/var/www/html\"", .string),
        ("%{HTTPS}", .variable), ("%{HTTP_HOST}", .variable), ("$1", .variable), ("${APACHE_LOG_DIR}", .variable),
        ("[L,R=301]", .tag), ("granted", .keyword), ("On", .keyword),
        ("example.com", nil),
    ])
    expect("systemd", systemdSample, [
        ("# Beispiel-Dienst", .comment), ("; alter Kommentar", .comment), ("[Unit]", .tag), ("[Service]", .tag),
        ("Description", .property), ("ExecStart", .property), ("NoNewPrivileges", .property), ("%i", .variable),
        ("%h", .variable), ("${STATE_DIRECTORY}", .variable), ("\"LANG=de_DE.UTF-8\"", .string),
        ("yes", .keyword), ("network-online.target", nil),
    ])
    expect("hcl", hclSample, [
        ("# Terraform", .comment), ("// Startskript", .comment), ("Kommentar */", .comment),
        ("terraform", .keyword), ("resource", .keyword), ("variable", .keyword), ("output", .keyword),
        ("\"aws_instance\"", .string), ("instance_type", .property), ("required_version", .property),
        ("string", .type), ("var.instance_type", .variable), ("data", .keyword),
        (#""web-${count.index}-${lookup(var.names, "x")}""#, .string), ("kein Kommentar", .string),
        ("<<-EOF", .string), ("1.5e3", .number), ("true", .keyword), ("null", .keyword), ("owner", .property),
        ("Name", .property),
    ])
    expect("dotenv", dotenvSample, [
        ("# Datenbank", .comment), ("DATABASE_URL", .property), ("x=1", nil), ("export", .keyword),
        ("API_KEY", .property), ("\"geheim ${SUFFIX}\"", .string), ("'Hallo Welt'", .string),
        ("${HOME}", .variable), ("8080", .number), ("true", .keyword), ("# Inline-Kommentar", .comment),
        ("5432", nil),
    ])
    expect("ssh", sshSample, [
        ("# Eigene Hosts", .comment), ("HostName", .property), ("User", .property),
        ("IdentityFile", .property), ("ProxyJump", .property), ("port", .property), ("Match", .keyword),
        ("StrictHostKeyChecking", .property), ("yes", .keyword), ("ask", .keyword), ("2222", .number),
        ("%r", .variable), ("%h", .variable),
    ])
    expect("ignore", ignoreSample, [
        ("# Abhängigkeiten", .comment), ("!", .keyword), ("*", .variable), ("**", .variable),
        ("?", .variable), ("[Bb]", .variable), ("node_modules/", nil), ("/", .tag), ("\\#", .string),
        ("keep.log", nil),
    ])

    // Small cases that need their own text.
    expect("toml", "t = { yy = 2 }\n", [("yy", .property)])
    expect("toml", "  [eingerückt]\nv = [\n  [1, 2],\n  [\"a\"],\n]\n",
           [("[eingerückt]", .tag), ("[1, 2]", nil), ("1", .number)])
    expect("nginx", "gzip on;\nlocation = /health {}\n", [("on", .keyword), ("=", .keyword), ("location", .keyword)])
    expect("hcl", "x = [for i in y : i]\nz = { for k, v in m : k => v }\n", [("for", .keyword), ("in", .keyword), ("k", nil)])
    expect("ssh", "host Server\n  hostname 10.0.0.1\nHOST=alt\n", [("host", .keyword), ("hostname", .property), ("HOST", .keyword)])
    expect("dotenv", "A=1 # c\n", [("1", .number), ("# c", .comment)])

    // Realistic files: ~1 MB per language must tokenize quickly.
    let samples: [(String, String)] = [
        ("toml", tomlSample), ("caddyfile", caddySample), ("nginx", nginxSample), ("apache", apacheSample),
        ("systemd", systemdSample), ("hcl", hclSample), ("dotenv", dotenvSample), ("ssh", sshSample),
        ("ignore", ignoreSample),
    ]
    var report: [String] = []
    var slowest = 0.0
    for (id, sample) in samples {
        let big = String(repeating: sample, count: 1_000_000 / sample.utf8.count + 1) as NSString
        let start = Date()
        _ = SyntaxLanguage.named(id)!.tokens(in: big)
        let msPerMB = Date().timeIntervalSince(start) * 1000 / (Double(big.length) / 1_000_000)
        slowest = max(slowest, msPerMB)
        report.append(String(format: "%@ %.0f", id, msPerMB))
    }
    print("     ms/MB: " + report.joined(separator: ", "))
    check("Konfigurationsdateien: 1 MB unter 1,5 s", slowest < 1500, slowest)
}
