/*
 * Notepad für macOS – Syntaxhervorhebung für Konfigurationsdateien.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// Building blocks shared by the configuration languages.
///
/// Performance (measured with ICU/NSRegularExpression): every rule is a capture group, and
/// with more than six groups in total (rules + the identifier rule) each match attempt gets
/// about four times slower. So each language has at most five rules plus the identifier
/// rule (which consumes whole words, so far fewer positions are tried): rules of one kind are
/// joined with `|` and some kinds are left out. Possessive quantifiers (`*+`, `++`) keep
/// failing rules from backtracking.
private enum CP {
    static let hashComment = #"#[^\n]*"#
    /// `#` at the line start or after a blank (not inside words or URLs).
    static let hashCommentAfterSpace = #"#(?<![^ \t\n]#)[^\n]*"#
    static let lineHashComment = #"^[ \t]*+#[^\n]*"#
    static let dqString = #""(?:[^"\\\n]|\\.)*+"?"#
    static let sqString = #"'(?:[^'\\\n]|\\.)*+'?"#
    /// Statement start: beginning of a line (leading blanks are part of the token).
    static let lineStart = #"^[ \t]*+"#
    /// Integer or decimal with an optional unit (`10m`, `30s`, `1.5G`); IP addresses as a whole.
    static let numberWithUnit = #"(?<![\w.$%:/-])\d++(?:\.\d++)*+[A-Za-z]*+\b"#

    static func any(_ patterns: String...) -> String { patterns.joined(separator: "|") }
}

extension SyntaxLanguage {
    static let configLanguages: [SyntaxLanguage] = [toml, caddyfile, nginx, apache, systemd, hcl, dotenv, ssh, ignore]

    // MARK: TOML

    private static let toml: SyntaxLanguage = {
        let keyPart = #"(?:[A-Za-z0-9_-]++|"(?:[^"\\\n]|\\.)*+"|'[^'\n]*+')"#
        return SyntaxLanguage(
            id: "toml", name: "TOML", extensions: ["toml"],
            fileNames: ["cargo.lock", "poetry.lock", "uv.lock", "pipfile"],
            keywords: "true false", rules: [
                (.comment, CP.hashComment),
                // Bare, quoted and dotted keys (also inside inline tables). Before strings, but
                // it cannot match at `"""`/`'''` because no "=" follows the empty key.
                (.property, keyPart + #"(?:[ \t]*+\.[ \t]*+"# + keyPart + #")*+(?=[ \t]*+=)"#),
                (.string, CP.any(#""{3}[\s\S]*?(?:"{3,5}|\z)"#, #"'{3}[\s\S]*?(?:'{3,5}|\z)"#,
                                 CP.dqString, #"'[^'\n]*+'?"#)),
                // [table] / [[array.of.tables]], indented by up to 12 blanks (a short lookbehind
                // after "[" is much cheaper than trying every blank as a line start); arrays at
                // the line start contain "," or end with ",".
                (.tag, #"\[(?<=^[ \t]{0,12}\[)\[?[^\[\]\n=,]*+\]\]?(?=[ \t]*+(?:#|$))"#),
                // RFC 3339 date-time, local date, local time; integers, floats, inf, nan.
                (.number, CP.any(#"\b\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})?)?\b"#,
                                 #"\b\d{2}:\d{2}:\d{2}(?:\.\d+)?"#,
                                 #"(?<![\w.])[+-]?(?:0x[0-9A-Fa-f_]++|0o[0-7_]++|0b[01_]++|\d[\d_]*+(?:\.\d[\d_]*+)?(?:[eE][+-]?\d[\d_]*+)?|inf|nan)(?![\w.])"#)),
            ])
    }()

    // MARK: Caddyfile

    private static let caddyfile: SyntaxLanguage = {
        let host = #"(?:(?:[\w*-]+\.)+[\w*-]+|localhost|\[[0-9A-Fa-f:]+\])"#
        let address = #"(?:[a-z][a-z0-9+.-]*://)?(?:"# + host + #"(?::\d+)?|:\d+)(?:/[^\s,{]*)?"#
        return SyntaxLanguage(
            id: "caddyfile", name: "Caddyfile", extensions: ["caddy"], fileNames: ["caddyfile"],
            keywords: "on off", rules: [
                (.comment, CP.hashCommentAfterSpace),
                // Site addresses (first on a line, followed by "{" or the line end) and snippets.
                (.tag, CP.lineStart + "(?:" + address + #"(?:(?:[ \t]*+,[ \t]*+|[ \t]++)"# + address
                    + #")*+(?=[ \t]*+(?:\{[ \t]*+)?$)|\([\w.-]+\))"#),
                // Directives (reverse_proxy, file_server, …), subdirectives and global options
                // are the first word of a line.
                (.keyword, CP.lineStart + #"[a-z_][a-z0-9_]*+(?=[ \t]|$)"#),
                // Named matchers @name, placeholders {host}, {http.request.uri}, env {$VAR}.
                (.variable, #"@(?<![\w.]@)[\w-]+|\{\$[A-Za-z_]\w*+(?::[^}\n]*+)?\}|\{[A-Za-z_>][\w.\[\]:>/-]*+\}"#),
                (.string, CP.any(CP.dqString, #"`[^`]*+`?"#)),
            ])
    }()

    // MARK: nginx

    private static let nginx: SyntaxLanguage = {
        // A statement starts a line or follows "{" / ";".
        let statement = #"(?:^|(?<=[{;]))[ \t]*+"#
        return SyntaxLanguage(
            id: "nginx", name: "nginx", extensions: ["nginx"], fileNames: ["nginx.conf"],
            keywords: "on off", rules: [
                (.comment, #"#(?<![^ \t\n;{}]#)[^\n]*"#),
                (.string, CP.any(CP.dqString, CP.sqString)),
                // Directives and block names; location/if modifiers = ~ ~* ^~ !~.
                (.keyword, CP.any(statement + #"[A-Za-z_]\w*+(?=[ \t{;]|$)"#,
                                  #"(?<=[ \t])(?:=|~\*?|\^~|!~\*?)(?=[ \t])"#)),
                (.variable, #"\$\{\w+\}|\$\w+"#),
                (.number, CP.numberWithUnit),
            ])
    }()

    // MARK: Apache

    private static let apache = SyntaxLanguage(
        id: "apache", name: "Apache", extensions: [], fileNames: [".htaccess", "httpd.conf", "apache2.conf"],
        caseInsensitive: true, keywords: "on off all none granted denied", rules: [
            (.comment, CP.lineHashComment),
            // <VirtualHost *:80> … </VirtualHost> and RewriteRule flags [L,R=301].
            (.tag, CP.any(#"</?[A-Za-z][\w:]*+|>(?=[ \t]*$)"#,
                          #"(?<=[ \t])\[[A-Za-z]++(?:=[^\],\s]*+)?(?:,[A-Za-z]++(?:=[^\],\s]*+)?)*+\](?=[ \t]*$)"#)),
            (.keyword, CP.lineStart + #"[A-Za-z]\w*+"#),  // directives always start a line
            (.variable, #"%\{[^}\n]*+\}|\$\{[\w:]+\}|[$%]\d"#),
            (.string, CP.dqString),
        ])

    // MARK: systemd

    static let systemdExtensions: Set<String> = ["service", "socket", "timer", "mount", "automount", "path", "target",
                                                 "slice", "scope", "swap", "network", "netdev", "link"]

    private static let systemd = SyntaxLanguage(
        id: "systemd", name: "systemd-Unit", extensions: Array(systemdExtensions),
        keywords: "yes no true false on off", rules: [
            (.comment, #"^[ \t]*+[#;][^\n]*"#),
            (.tag, #"^[ \t]*+\[[^\]\n]*+\]"#),
            (.property, CP.lineStart + #"[A-Za-z][\w-]*+(?=[ \t]*=)"#),
            (.variable, #"%[A-Za-z%]|\$\{\w+\}|\$\w+"#),
            (.string, CP.any(CP.dqString, CP.sqString)),
        ])

    // MARK: Terraform / HCL

    private static let hcl: SyntaxLanguage = {
        // Without backreferences a heredoc ends at the first line holding a known marker.
        let markers = "(?:EOF|EOT|EOH|EOM|END|POLICY|JSON|YAML|SCRIPT|TEMPLATE|USERDATA|CONFIG|DOC|TEXT|SHELL)"
        let heredoc = #"<<-?"# + markers + #"[ \t]*\n[\s\S]*?(?:^[ \t]*"# + markers + #"[ \t]*$|\z)"#
        return SyntaxLanguage(
            id: "hcl", name: "Terraform / HCL", extensions: ["tf", "tfvars", "hcl", "nomad"],
            keywords: "resource data variable output module provider locals terraform backend required_providers provisioner connection lifecycle dynamic content moved import check removed job group task for in if else endif endfor true false null",
            types: "string number bool list map set object tuple any", rules: [
                (.comment, CP.any(CP.hashComment, #"//[^\n]*"#, #"/\*[\s\S]*?(?:\*/|\z)"#)),
                // ${…} and %{…} may contain quotes of their own.
                (.string, CP.any(heredoc, #""(?:[^"\\\n$%]|\\.|[$%]\{[^}\n]*+\}|[$%])*+"?"#)),
                (.property, #"[A-Za-z_][\w-]*+(?=[ \t]*=(?![=>]))"#),
                (.variable, #"(?<![\w.])(?:var|local|each|count|self|path)\.[A-Za-z_][\w-]*+"#),
                (.number, #"(?<![\w.])\d++(?:\.\d++)?(?:[eE][+-]?\d++)?\b"#),
            ])
    }()

    // MARK: dotenv

    private static let dotenv = SyntaxLanguage(
        id: "dotenv", name: ".env", extensions: ["env"], keywords: "export true false yes no", rules: [
            (.comment, CP.hashCommentAfterSpace),
            // KEY= at the line start or after "export" (then with the blank before it).
            (.property, CP.any(CP.lineStart + #"[A-Za-z_][\w.-]*+(?=[ \t]*=)"#,
                               #"[ \t](?<=export[ \t])[ \t]*+[A-Za-z_][\w.-]*+(?=[ \t]*=)"#)),
            (.string, CP.any(CP.dqString, #"'[^'\n]*+'?"#)),
            (.variable, #"\$\{[^}\n]*+\}|\$[A-Za-z_]\w*+"#),
            (.number, #"(?<==)-?\d++(?:\.\d++)?(?=[ \t]*(?:#|$))"#),
        ])

    // MARK: SSH

    private static let ssh = SyntaxLanguage(
        id: "ssh", name: "SSH-Konfiguration", extensions: [], fileNames: ["ssh_config", "sshd_config"],
        caseInsensitive: true, keywords: "yes no ask confirm auto none any all force", rules: [
            (.comment, CP.lineHashComment),
            (.keyword, CP.lineStart + #"(?:host|match)(?=[ \t=]|$)"#),
            (.property, CP.lineStart + #"[A-Za-z][A-Za-z0-9]*+(?=[ \t=]|$)"#),  // HostName, User, …
            (.variable, #"%[%A-Za-z]|\$\{\w+\}"#),
            (.number, #"(?<![\w.:/-])\d++\b"#),
        ])

    // MARK: Ignore files

    private static let ignore = SyntaxLanguage(
        id: "ignore", name: "Ignore-Datei", extensions: [],
        fileNames: [".gitignore", ".dockerignore", ".npmignore", ".prettierignore", ".eslintignore", ".hgignore"],
        rules: [
            (.comment, #"^#[^\n]*"#),
            (.keyword, #"^!|^syntax:[^\n]*"#),  // negation; Mercurial syntax switch
            (.string, #"\\."#),  // escaped character
            (.variable, #"\*\*|[*?]|\[[^\]\n]*+\]"#),
            (.tag, #"/(?=[ \t]*$)"#),  // directories only
        ])

    // MARK: - Detection

    private static let apacheSniffer = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:<(?:VirtualHost|Directory|IfModule)\b|(?:LoadModule|DocumentRoot)[ \t])"#,
        options: [.anchorsMatchLines, .caseInsensitive])
    private static let nginxSniffer = try! NSRegularExpression(
        pattern: #"(?:^|[;{}])\s*(?:(?:http|events|stream|server)\s*\{|location\s+[=~^@/]|upstream\s+[\w.-]+\s*\{|(?:proxy_pass|worker_processes|fastcgi_pass)\s+[^\n;]*;)"#,
        options: [.anchorsMatchLines])

    private static func sniffConf(_ sample: NSString) -> SyntaxLanguage? {
        let all = NSRange(location: 0, length: sample.length)
        if apacheSniffer.firstMatch(in: sample as String, range: all) != nil { return named("apache") }
        if nginxSniffer.firstMatch(in: sample as String, range: all) != nil { return named("nginx") }
        return nil
    }

    /// Special file names and content sniffing (e.g. `.conf` as nginx, Apache or INI).
    /// `path` is lowercased; returns nil to fall back to file name/extension lookup.
    static func detectConfig(path: String, sample: NSString) -> SyntaxLanguage? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let lastPart = name.split(separator: ".").last.map(String.init) ?? name

        if path.hasSuffix("/.ssh/config") || path == ".ssh/config"
            || path.contains("/ssh_config.d/") || path.contains("/sshd_config.d/") {
            return named("ssh")
        }
        if name == ".env" || (name.hasPrefix(".env.") && !["json", "yml", "yaml", "toml", "js", "ts"].contains(ext)) {
            return named("dotenv")
        }
        if name == ".ignore" || (lastPart.hasSuffix("ignore") && lastPart.count > 6) || path.hasSuffix("/.git/info/exclude") {
            return named("ignore")
        }
        if name.hasPrefix("dockerfile.") || name.hasPrefix("containerfile.") || ext == "dockerfile" {
            return named("dockerfile")
        }
        if [".babelrc", ".eslintrc", ".prettierrc", ".stylelintrc"].contains(name) {
            let start = sample.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
            let isJSON = start.location != NSNotFound && sample.character(at: start.location) == 0x7B  // "{"
            return named(isJSON ? "json" : "yaml")
        }
        if name.hasPrefix("caddyfile.") && ext != "json" {
            return named("caddyfile")
        }

        // Generic extensions: a more specific file name (nginx.conf, httpd.conf, …) wins.
        guard ext == "conf" || ext == "cnf" || ext.isEmpty || ext == "types" else { return nil }
        if all.contains(where: { $0.fileNames.contains(name) }) { return nil }

        let directories = path.split(separator: "/").dropLast()
        if ext == "conf" {
            // systemd drop-ins (foo.service.d/override.conf) and /etc/systemd/*.conf
            if let parent = directories.last, parent.hasSuffix(".d"),
               systemdExtensions.contains((String(parent.dropLast(2)) as NSString).pathExtension) {
                return named("systemd")
            }
            if directories.contains("systemd") { return named("systemd") }
        }
        if ext != "cnf", directories.contains("nginx") { return named("nginx") }
        if ext == "conf", directories.contains(where: { $0 == "apache2" || $0 == "httpd" }) {
            return named("apache")
        }
        if ext == "conf" || ext == "cnf" { return sniffConf(sample) }
        return nil
    }
}
