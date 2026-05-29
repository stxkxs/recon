# Recon

A fast, modular infrastructure reconnaissance toolkit for SRE and security teams.

```
                                     _
 _ __   ___   ___   ___   _ __    __| |
| '__| / _ \ / __| / _ \ | '_ \  / _` |
| |   |  __/| (__ | (_) || | | || (_| |
|_|    \___| \___| \___/ |_| |_| \__,_|
```

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Bash 4+](https://img.shields.io/badge/bash-4%2B-green.svg)](https://www.gnu.org/software/bash/)

## Overview

Recon performs passive reconnaissance on domains and IP addresses, gathering DNS records, SSL certificates, HTTP headers, WHOIS data, technology fingerprints, port states, CORS configurations, WAF/CDN detection, certificate transparency logs, and more. It integrates with Shodan, VirusTotal, and SecurityTrails for enriched intelligence, produces a security posture score, and can generate self-contained HTML reports. Designed for:

- **Incident Response**: Quickly gather context on suspicious domains
- **Infrastructure Audits**: Verify DNS, SSL, and security header configurations
- **Security Assessments**: Score security posture with actionable recommendations
- **Competitive Analysis**: Understand technology stacks and infrastructure choices
- **Asset Discovery**: Find subdomains, open ports, and related infrastructure

## Features

- **Modular Architecture** - 27 modules, run specific ones or all at once
- **Security Scoring** - Letter grade A-F with actionable recommendations
- **HTML Reports** - Self-contained dark-themed HTML report export
- **CORS Analysis** - Detect CORS misconfigurations and origin reflection
- **Port Scanning** - TCP port scanning for 20 common service ports
- **WAF/CDN Detection** - Passive fingerprinting of web application firewalls and CDNs
- **DNSSEC Validation** - Chain verification and configuration analysis
- **Takeover Detection** - Subdomain takeover vulnerability scanning
- **API Integrations** - Shodan, VirusTotal, SecurityTrails, Wayback Machine
- **Email Security** - SPF, DMARC, DKIM, and BIMI analysis
- **JS Analysis** - Extract secrets, endpoints, and dependencies from JavaScript
- **Directory Discovery** - Sensitive file and path enumeration
- **Dual Output** - Human-readable terminal or JSON for automation
- **Batch Processing** - Scan hundreds of targets with parallel execution
- **Checkpoint/Resume** - Interrupted jobs can be resumed
- **Config-Driven** - YAML configuration with environment variable overrides
- **Charm/gum UI** - Enhanced terminal output when [gum](https://github.com/charmbracelet/gum) is installed
- **Docker Ready** - Containerized for consistent environments

## Quick Start

```bash
# Clone the repo
git clone https://github.com/stxkxs/recon.git
cd recon

# Run against a domain
./bin/recon example.com

# JSON output for automation
./bin/recon --json example.com | jq .

# Specific modules only
./bin/recon -m dns,ssl example.com

# Security score
./bin/recon -s example.com

# HTML report
./bin/recon --report report.html example.com

# Port scanning only
./bin/recon -m ports example.com

# CORS analysis
./bin/recon -m cors example.com

# WAF/CDN detection
./bin/recon -m waf example.com

# Email security analysis
./bin/recon -m emailsec -s example.com

# IP reconnaissance
./bin/recon 8.8.8.8

# Batch processing
./bin/recon --batch targets.txt --parallel 4
```

## Installation

### Prerequisites

| Required | Optional |
|----------|----------|
| bash 4+  | yq (YAML config) |
| dig      | timeout (coreutils) |
| curl     | flock (batch locking) |
| openssl  | gum (enhanced UI) |
| whois    | nc (banner grabbing) |
| jq       | nmap (enhanced port scanning) |

**macOS:**
```bash
# bash 4+ (macOS ships with bash 3.2)
brew install bash

# Other dependencies
brew install bind curl openssl whois jq yq

# Optional: Charm gum for enhanced terminal UI
brew install gum
```

**Ubuntu/Debian:**
```bash
apt-get install bash dnsutils curl openssl whois jq yq

# Optional: gum
mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
apt-get update && apt-get install gum
```

### Install

```bash
# Verify dependencies
make check-deps

# Install to /usr/local (requires sudo)
sudo make install

# Or install to ~/.local (user installation, no sudo)
make install-local

# Verify installation
recon --version
```

### Docker

```bash
# Build image
make docker-build

# Run
docker run --rm -it recon:latest example.com
docker run --rm -it recon:latest --json example.com

# With docker-compose
cd docker
docker-compose run --rm recon example.com
```

## Usage

```
Usage: recon [options] <target>
       recon --batch <targets_file> [options]

Arguments:
  <target>              Domain or IP address to scan

Options:
  -h, --help            Show this help message
  -v, --version         Show version information
  -j, --json            Output results as JSON
  -o, --output FILE     Write output to file
  -m, --modules LIST    Comma-separated list of modules to run
  -c, --config FILE     Use custom config file
  -q, --quiet           Suppress banner and progress output
  -s, --score           Run security scoring after scan
  -r, --report FILE     Generate HTML report to file
  --list-modules        List available modules

Batch Processing:
  -b, --batch FILE      Process multiple targets from file
  -p, --parallel N      Number of parallel workers (default: 4)
  --resume              Resume interrupted batch
  --list-batches        List recent batch runs
```

## Modules

| Module | Description | Data Collected |
|--------|-------------|----------------|
| `dns` | DNS enumeration | A, AAAA, MX, TXT, NS, CAA, DMARC, DKIM records |
| `subdomain` | Subdomain discovery | Common subdomains from 80+ entry wordlist |
| `crt` | Certificate Transparency | CT log search for subdomains and certificates |
| `ssl` | SSL/TLS analysis | Certificate chain, validity, SANs, TLS version |
| `http` | HTTP headers | Security headers, server info, redirects |
| `whois` | WHOIS lookups | Organization, netname, country, CIDR |
| `files` | Common files | robots.txt, security.txt, sitemap.xml, well-known |
| `tech` | Tech detection | Frontend frameworks, analytics, CDN/infrastructure |
| `ip` | IP recon | Reverse DNS, ASN, geolocation hints |
| `ports` | Port scanning | 20 common TCP ports with service identification |
| `cors` | CORS analysis | Misconfiguration detection, origin reflection, risk level |
| `waf` | WAF/CDN detection | Firewall and CDN identification via header fingerprinting |
| `dnssec` | DNSSEC validation | DNSSEC chain verification and configuration status |
| `takeover` | Subdomain takeover | Dangling CNAME and takeover vulnerability detection |
| `shodan` | Shodan intelligence | Open ports, services, vulns, OS fingerprinting |
| `virustotal` | VirusTotal reputation | Domain/IP reputation, detected URLs, threat categories |
| `wayback` | Wayback Machine | Historical URL discovery and endpoint enumeration |
| `securitytrails` | SecurityTrails | DNS history, associated domains, subdomains |
| `reverseip` | Reverse IP lookup | Domains hosted on the same IP address |
| `asn` | ASN expansion | ASN details, IP prefix enumeration, peer networks |
| `axfr` | Zone transfer test | DNS AXFR zone transfer vulnerability detection |
| `methods` | HTTP methods | Allowed HTTP methods enumeration per endpoint |
| `dirs` | Directory discovery | Sensitive files, admin panels, backup files, config files |
| `jsanalysis` | JS analysis | Secrets, API endpoints, dependencies in JavaScript files |
| `favicon` | Favicon hashing | Favicon hash fingerprinting for technology identification |
| `emailsec` | Email security | SPF, DMARC, DKIM, BIMI validation and analysis |
| `score` | Security scoring | Letter grade A-F, category breakdown, recommendations |

**Default modules:**
- Domains: `dns`, `subdomain`, `crt`, `ssl`, `http`, `whois`, `files`, `tech`, `ports`, `cors`, `waf`, `dnssec`, `shodan`, `virustotal`, `wayback`, `securitytrails`, `axfr`, `methods`, `dirs`, `jsanalysis`, `favicon`
- IPs: `ip`, `ports`, `shodan`, `virustotal`, `reverseip`, `asn`
- Post-scan: `score`, `takeover`, `emailsec` (run with `-s` flag or explicitly)

## Security Scoring

Run with `-s` to get a security posture score:

```bash
recon -s example.com
```

The score evaluates:

| Category | Weight | Checks |
|----------|--------|--------|
| Transport Security | 25 pts | HTTPS, HSTS, HTTP redirect |
| Email Security | 15 pts | SPF, DMARC, DKIM |
| Certificate Health | 15 pts | Valid SSL, CAA record |
| Security Headers | 25 pts | CSP, X-Frame-Options, XCTO, Referrer-Policy, Permissions-Policy |
| Infrastructure | 10 pts | Multiple nameservers, security.txt |

Grades: **A** (90%+), **B** (80%+), **C** (70%+), **D** (60%+), **F** (<60%)

## HTML Reports

Generate a self-contained HTML report:

```bash
recon --report report.html example.com
```

Reports include all scan data in a dark-themed, responsive layout with score visualization, color-coded findings, and structured tables.

## Examples

### Basic Reconnaissance

```bash
# Full scan with terminal output
recon example.com

# Quick DNS check
recon -m dns example.com

# SSL and HTTP security analysis
recon -m ssl,http example.com

# Save results to file
recon --json example.com -o results.json

# Quiet mode (no banner)
recon -q example.com
```

### Security Assessment

```bash
# Full scan with security score
recon -s example.com

# Generate HTML report with score
recon --report audit.html -s example.com

# Check CORS configuration
recon -m cors example.com

# Port scan only
recon -m ports example.com

# Combined security check
recon -m http,ssl,cors,ports -s example.com

# Subdomain takeover check
recon -m subdomain,crt,takeover example.com

# JavaScript secrets scan
recon -m jsanalysis example.com

# Full email security audit
recon -m dns,emailsec -s example.com
```

### Working with JSON Output

```bash
# Pretty print full results
recon --json example.com | jq .

# Extract A records
recon --json example.com | jq '.results.dns.data.a'

# Get all discovered subdomains
recon --json example.com | jq '.results.subdomain.data.found[].fqdn'

# Check security headers
recon --json example.com | jq '.results.http.data.urls[0].security_headers'

# Get security score
recon --json -s example.com | jq '.results.score.data | {grade, percentage, recommendations}'

# Get open ports
recon --json example.com | jq '.results.ports.data.open[] | {port, service}'

# Check CORS risk level
recon --json example.com | jq '.results.cors.data | {risk, findings}'

# Build a summary report
recon --json -s example.com | jq '{
  domain: .target,
  grade: .results.score.data.grade,
  ips: .results.dns.data.a,
  nameservers: .results.dns.data.ns,
  open_ports: [.results.ports.data.open[].port],
  cors_risk: .results.cors.data.risk,
  subdomains: [.results.subdomain.data.found[].fqdn],
  ssl_issuer: .results.ssl.data.certificates[0].issuer,
  technologies: .results.tech.data
}'
```

### Batch Processing

```bash
# Create targets file (one per line)
cat > targets.txt << 'EOF'
example.com
github.com
cloudflare.com
EOF

# Process with 8 parallel workers
recon --batch targets.txt --parallel 8

# Resume interrupted batch
recon --resume

# View batch history
recon --list-batches

# Results saved to ~/.local/share/recon/results/
```

### Input Normalization

Recon automatically normalizes inputs:

```bash
# All of these are equivalent:
recon example.com
recon EXAMPLE.COM
recon https://example.com
recon https://example.com/path/to/page
recon "  example.com  "
```

## Configuration

### Config File

Create `~/.config/recon/recon.yaml` or `./recon.yaml`:

```yaml
global:
  output_dir: "~/.local/share/recon/results"
  output_format: "terminal"  # terminal | json
  color: "auto"              # auto | always | never
  retention_days: 30

timeouts:
  dns: 5
  http: 10
  ssl: 5
  whois: 15
  ports: 2

batch:
  max_parallel: 4
  checkpoint_interval: 10
  resume_on_start: true

rate_limits:
  requests_per_second: 2
  whois_delay: 1

modules:
  dns:
    enabled: true
    record_types: [A, AAAA, MX, TXT, NS, CAA]
  subdomain:
    enabled: true
    wordlist: ""  # empty = use built-in
  ssl:
    enabled: true
  http:
    enabled: true
  whois:
    enabled: true
  files:
    enabled: true
  tech:
    enabled: true
  ip:
    enabled: true
  ports:
    enabled: true
  cors:
    enabled: true
  crt:
    enabled: true
  waf:
    enabled: true
  dnssec:
    enabled: true
  takeover:
    enabled: true
  shodan:
    enabled: true
  virustotal:
    enabled: true
  wayback:
    enabled: true
  securitytrails:
    enabled: true
  reverseip:
    enabled: true
  asn:
    enabled: true
  axfr:
    enabled: true
  methods:
    enabled: true
  dirs:
    enabled: true
    wordlist: ""          # empty = use built-in
    request_delay: 0.2
  jsanalysis:
    enabled: true
    max_files: 20
    max_file_size: 2097152
  favicon:
    enabled: true
  emailsec:
    enabled: true
  score:
    enabled: true

# API keys for enriched intelligence
api_keys:
  shodan: ""
  securitytrails: ""
  virustotal: ""
```

See [`etc/recon.yaml.example`](etc/recon.yaml.example) for the full template.

### Environment Variables

Environment variables override config file values:

```bash
export RECON_OUTPUT_FORMAT=json
export RECON_COLOR=never
export RECON_TIMEOUT_DNS=10
export RECON_TIMEOUT_HTTP=20
export RECON_PARALLEL=8
export RECON_API_SHODAN=your_api_key
export RECON_API_VIRUSTOTAL=your_api_key
export RECON_API_SECURITYTRAILS=your_api_key
```

## JSON Schema

```json
{
  "meta": {
    "version": "2.1.0",
    "run_id": "20240201-143022-a1b2c3",
    "started_at": "2024-02-01T14:30:22Z",
    "ended_at": "2024-02-01T14:31:45Z",
    "target_original": "https://example.com",
    "target_normalized": "example.com"
  },
  "target": "example.com",
  "results": {
    "dns": {
      "status": "success",
      "data": {
        "a": ["93.184.216.34"],
        "aaaa": ["2606:2800:220:1:248:1893:25c8:1946"],
        "mx": [{"priority": 10, "host": "mail.example.com."}],
        "txt": ["v=spf1 -all"],
        "ns": ["ns1.example.com.", "ns2.example.com."],
        "caa": ["0 issue \"letsencrypt.org\""],
        "dmarc": "v=DMARC1; p=reject",
        "dkim": {"google": "v=DKIM1; ..."}
      }
    },
    "ports": {
      "status": "success",
      "data": {
        "open": [
          {"port": 80, "service": "http", "state": "open", "banner": null},
          {"port": 443, "service": "https", "state": "open", "banner": null}
        ],
        "closed": [22, 21, 3306],
        "total_scanned": 20
      }
    },
    "cors": {
      "status": "success",
      "data": {
        "url": "https://example.com",
        "tests": [],
        "findings": [],
        "risk": "none"
      }
    },
    "waf": {
      "status": "success",
      "data": {
        "detected": true,
        "provider": "Cloudflare",
        "confidence": "high"
      }
    },
    "shodan": {
      "status": "success",
      "data": {
        "ip": "93.184.216.34",
        "ports": [80, 443],
        "vulns": [],
        "os": "Linux"
      }
    },
    "score": {
      "status": "success",
      "data": {
        "score": 85,
        "max_score": 100,
        "percentage": 85,
        "grade": "B",
        "passed": 12,
        "failed": 3,
        "checks": [],
        "recommendations": ["Add Content-Security-Policy header"]
      }
    }
  },
  "errors": [],
  "conflicts": [],
  "summary": {
    "modules_run": 27,
    "modules_success": 27,
    "modules_partial": 0,
    "modules_failed": 0,
    "total_errors": 0,
    "total_conflicts": 0
  }
}
```

## Project Structure

```
recon/
├── bin/
│   └── recon              # Main entry point
├── lib/
│   ├── core/
│   │   ├── common.sh      # Colors, logging, utilities
│   │   ├── config.sh      # YAML config loading
│   │   ├── input.sh       # Input normalization & validation
│   │   ├── output.sh      # JSON formatters
│   │   ├── state.sh       # Checkpoint/resume state
│   │   ├── ui.sh          # Charm/gum UI integration
│   │   └── report.sh      # HTML report generation
│   ├── modules/
│   │   ├── dns.sh         # DNS enumeration
│   │   ├── subdomain.sh   # Subdomain discovery
│   │   ├── crt.sh         # Certificate Transparency
│   │   ├── ssl.sh         # SSL/TLS analysis
│   │   ├── http.sh        # HTTP header analysis
│   │   ├── whois.sh       # WHOIS lookups
│   │   ├── files.sh       # Common files check
│   │   ├── tech.sh        # Technology detection
│   │   ├── ip.sh          # IP-specific recon
│   │   ├── ports.sh       # TCP port scanning
│   │   ├── cors.sh        # CORS misconfiguration detection
│   │   ├── waf.sh         # WAF/CDN detection
│   │   ├── dnssec.sh      # DNSSEC validation
│   │   ├── takeover.sh    # Subdomain takeover detection
│   │   ├── shodan.sh      # Shodan intelligence
│   │   ├── virustotal.sh  # VirusTotal reputation
│   │   ├── wayback.sh     # Wayback Machine discovery
│   │   ├── securitytrails.sh # SecurityTrails intelligence
│   │   ├── reverseip.sh   # Reverse IP lookup
│   │   ├── asn.sh         # ASN expansion
│   │   ├── axfr.sh        # Zone transfer testing
│   │   ├── methods.sh     # HTTP methods enumeration
│   │   ├── dirs.sh        # Directory discovery
│   │   ├── jsanalysis.sh  # JavaScript analysis
│   │   ├── favicon.sh     # Favicon hash fingerprinting
│   │   ├── emailsec.sh    # Email security analysis
│   │   └── score.sh       # Security posture scoring
│   └── batch/
│       ├── runner.sh      # Batch orchestration
│       └── progress.sh    # Progress tracking
├── etc/
│   ├── recon.yaml.example # Config template
│   └── subdomains.txt     # Default wordlist (82 entries)
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yaml
├── tests/
│   ├── test_input.sh      # Input normalization tests
│   ├── test_output.sh     # JSON output tests
│   ├── test_modules.sh    # Module unit tests (all 27 modules)
│   ├── test_crt.sh        # Certificate Transparency tests
│   ├── test_shodan.sh     # Shodan module tests
│   ├── test_virustotal.sh # VirusTotal module tests
│   ├── test_waf.sh        # WAF detection tests
│   ├── test_dnssec.sh     # DNSSEC validation tests
│   ├── test_takeover.sh   # Subdomain takeover tests
│   ├── test_wayback.sh    # Wayback Machine tests
│   ├── test_securitytrails.sh # SecurityTrails tests
│   ├── test_reverseip.sh  # Reverse IP tests
│   ├── test_asn.sh        # ASN expansion tests
│   ├── test_axfr.sh       # Zone transfer tests
│   ├── test_methods.sh    # HTTP methods tests
│   ├── test_dirs.sh       # Directory discovery tests
│   ├── test_jsanalysis.sh # JavaScript analysis tests
│   ├── test_favicon.sh    # Favicon hashing tests
│   ├── test_emailsec.sh   # Email security tests
│   └── test_integration.sh # End-to-end tests
├── Makefile
├── LICENSE
└── README.md
```

## Development

```bash
# Run all tests
make test

# Run specific test suite
bash tests/test_input.sh        # Input normalization
bash tests/test_output.sh       # JSON output
bash tests/test_modules.sh      # All 27 modules
bash tests/test_integration.sh  # End-to-end
bash tests/test_shodan.sh       # Individual module tests
# ... 20 test files, 873 tests total

# Lint with shellcheck
make lint

# Check dependencies
make check-deps

# Demo runs
make demo          # Terminal output
make demo-json     # JSON output
```

### Adding a New Module

1. Create `lib/modules/mymodule.sh`:

```bash
#!/usr/bin/env bash

[[ -n "${_RECON_MODULE_MYMODULE_LOADED:-}" ]] && return 0
_RECON_MODULE_MYMODULE_LOADED=1

# Run the module - returns JSON
mymodule_run() {
    local target=$1
    # ... gather data ...
    echo '{"key": "value"}'
}

# Print terminal output
mymodule_print() {
    local json=$1
    local target=$2
    header "MY MODULE - $target"
    # ... format output ...
}

# Check dependencies
mymodule_check() {
    check_dependencies mytool
}
```

2. Register in `bin/recon`:

```bash
MODULES[mymodule]="mymodule_run:mymodule_print:mymodule_check"
DOMAIN_MODULES+=(mymodule)
```

3. Source in `bin/recon`:

```bash
source "${PROJECT_ROOT}/lib/modules/mymodule.sh"
```

## Security Considerations

- **Passive Only**: Recon performs passive/semi-passive reconnaissance only
- **No Authentication**: Does not attempt to authenticate or log in
- **Rate Limiting**: Configurable delays for WHOIS and other rate-limited services
- **Respect robots.txt**: Only checks for existence, does not crawl disallowed paths

## Roadmap

- [x] API integrations (Shodan, SecurityTrails, VirusTotal, Wayback Machine)
- [x] Email security analysis (SPF, DMARC, DKIM, BIMI)
- [x] WAF/CDN detection and DNSSEC validation
- [x] Subdomain takeover detection
- [x] JavaScript analysis and directory discovery
- [ ] AWS integration (Route53, EC2 metadata)
- [ ] Optional enhanced tools (subfinder, httpx)
- [ ] Historical comparison / change detection
- [ ] Webhook notifications for monitoring
- [ ] Web UI dashboard

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test`)
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

Apache License 2.0 - see [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

## Acknowledgments

- Inspired by various reconnaissance tools in the security community
- Built with standard Unix tools for maximum portability
- Enhanced with [Charm](https://charm.sh) tools when available
