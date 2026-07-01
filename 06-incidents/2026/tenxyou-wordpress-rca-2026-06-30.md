# Root Cause Analysis — TenXYou WordPress Compromise
**Incident ID:** tenxyou-wordpress-seo-spam-backdoor-2026-06-28
**Date of Incident:** 2026-06-10 (initial access) → 2026-06-28 (payload deployed)
**Date Discovered:** 2026-06-29
**Date Resolved:** 2026-06-29
**Prepared by:** Vishav Deshwal, Infinite Locus
**Environment:** `ubuntu@3.6.59.24`, WordPress 6.9.4, PHP 8.3.6, Ubuntu 24.04.4 LTS

---

## 1. Executive Summary

The TenXYou blog (`tenxyou.com/blogs`) was compromised via a web-based file manager plugin (wpide) installed on the WordPress server. An attacker uploaded a password-less PHP webshell on **June 10, 2026**, gaining persistent filesystem access for 19 days without detection. On **June 28, 2026**, the attacker weaponized this access to deploy an SEO spam backdoor into WordPress's `index.php`, breaking the site for normal visitors while silently poisoning search engine results and redirecting organic traffic to a Japanese spam affiliate site.

The site was discovered broken on June 29, 2026. Full cleanup, backdoor removal, and credential rotation was completed the same day.

---

## 2. Timeline of Events

```
2026-02-21  ai1wm-backups/ directory created (normal plugin operation)
            - Contains default index.php, index.html, robots.txt placeholders
            - No web restriction on subdirectories at this point

2026-06-10 09:20 UTC  ← INITIAL COMPROMISE
            Attacker uploads PHP File Manager webshell to:
            /var/www/wordpress/wp-content/ai1wm-backups/mu-plugins/index.php
            - Webshell has no password (public access)
            - Attacker now has full filesystem RW access as wpuser

2026-06-10 to 2026-06-27  (19 days undetected)
            Attacker performs reconnaissance — reads wp-config.php,
            maps directory structure, identifies all installed plugins

2026-06-28 23:57 UTC  ← PAYLOAD DEPLOYED
            index.php replaced with SEO spam backdoor (8246 bytes)
            - Original file: 400 bytes
            - Malware connects to: j26062_13.rdaniel.online

2026-06-29 02:27 UTC
            Backdoor files planted inside plugin directories:
            - plugins/gravatar-enhanced/classes/hovercards/
            - plugins/gutenberg/build/scripts/block-library/page-list-item/

2026-06-29 11:14 UTC
            Additional backdoor files planted (same pattern, different plugins)

2026-06-29 15:44 UTC
            PHP-FPM restarted (likely someone noticed the site was broken)
            Site still broken — FPM restart does not fix a corrupted index.php

2026-06-29 (session)  ← DETECTED AND RESOLVED
            - index.php restored
            - 9 backdoor files removed
            - Nginx block added for ai1wm-backups/
            - DB password rotated
            - All WP user passwords rotated
            - Attacker-created admin account (root/admin@wordpress.com) deleted
```

---

## 3. Root Cause

### Primary: Exposed Web-Based File Manager Plugin (wpide)

The `wpide` plugin is a web-based IDE and file manager for WordPress. It exposes authenticated HTTP endpoints for file upload and editing:

```
GET  /wp-json/wpide/v1/upload    ← check upload
POST /wp-json/wpide/v1/upload    ← upload files
```

**This is functionally a web shell gated only by WordPress authentication.** If an admin account was compromised (weak password, credential stuffing, brute force) or the plugin had an authentication bypass vulnerability, an attacker could upload arbitrary files to the server — including PHP webshells.

The uploaded webshell landed in `wp-content/ai1wm-backups/mu-plugins/` — a subdirectory that, at the time, had **no `.htaccess` PHP restriction** (the `.htaccess` blocking PHP in `ai1wm-backups/` was only created on June 30, likely by a plugin update or security scan after the fact).

### Contributing Factor 1: No PHP Restriction on Backup Directories

The All-in-One WP Migration plugin stores backups in `wp-content/ai1wm-backups/`. This directory was web-accessible. While the plugin added an `.htaccess` in the root of that directory, the **`mu-plugins/` subdirectory did not inherit the restriction**, allowing any PHP file uploaded there to be directly executed via the browser.

### Contributing Factor 2: No File Integrity Monitoring

The malicious `index.php` was 8246 bytes — 20× the size of the legitimate file (400 bytes). No alerting existed to flag unexpected changes to WordPress core files. The compromise went undetected for 19 days.

### Contributing Factor 3: Excessive Admin Accounts

11 WordPress administrator accounts existed. Each is an attack surface. The attacker created an additional backdoor admin account (`root` / `admin@wordpress.com`) that would have survived a password reset of legitimate accounts.

---

## 4. How the Malware Worked

### 4.1 SEO Cloaking (Googlebot)

The backdoor detected crawlers (Googlebot, Bingbot, Yahoo) by checking the `User-Agent` header:

```php
function isc() {
    $agent = strtolower($_SERVER['HTTP_USER_AGENT']);
    return preg_match('/googlebot|google|yahoo|bing|aol\/s/', $agent);
}
```

When a crawler was detected, it made a `curl` POST request to the attacker's C2 server (`j26062_13.rdaniel.online/indata`) with the site domain, URI, and port — and returned whatever content the C2 server responded with. This is black-hat SEO: Googlebot was served spam/affiliate content, poisoning the site's search index.

### 4.2 Redirect Attack (Organic Search Visitors)

The backdoor detected visitors arriving from a search engine referrer:

```php
function isg() {
    $refer = strtolower($_SERVER['HTTP_REFERER']);
    return preg_match('/(google|yahoo|bing|aol)/', $refer);
}
```

When a real user clicked a Google result and landed on the site, the malware redirected them to a Japanese spam/affiliate URL via `j26062_13.rdaniel.online/jump`. The site's organic traffic was being monetized by the attacker.

### 4.3 Why the Site Broke for Normal Visitors

The malware used PHP's `goto` statement to create an obfuscated control flow. For normal visitors (not crawlers, not from search referrers), execution fell through to a label at the end:

```php
CnN7_:  ?>
 /**
 * Front to the WordPress application...
 */
define( 'WP_USE_THEMES', true );
require __DIR__ . '/wp-blog-header.php';
```

The `?>` tag **closed PHP mode**. Everything after it — including the original WordPress `index.php` content — was output as **literal HTML text**, not executed. So:

- The PHP source code was rendered visibly in the browser
- `require __DIR__ . '/wp-blog-header.php'` was never called
- WordPress never loaded

### 4.4 Persistence Mechanism

The ~1MB backdoor files (`wp-login.php`, `index.php`) planted inside plugin subdirectories are full-featured PHP backdoors disguised as plugin assets. Their names blend in — `wp-login.php` inside a plugin dir looks like part of the plugin at a glance. These would survive:
- A WordPress core file restore (they're in `wp-content/plugins/`, not core)
- A plugin deactivation (files remain on disk)
- An `index.php` restore (only the core file is fixed)

The attacker-created admin account (`root`) is another persistence layer — it would survive a file cleanup if passwords weren't also rotated.

---

## 5. Indicators of Compromise (IoC)

### Malware Signature
```bash
# Obfuscated goto pattern
grep -rl 'goto EmYgD\|rdaniel\.online\|execReq.*curl_init' /var/www/

# Oversized files in plugin directories
find /var/www/ -name '*.php' -size +500k -not -path '*/uploads/*'

# Fake wp-login.php inside plugin subdirs
find /var/www/wordpress/wp-content/plugins/ -name 'wp-login.php'
```

### C2 Server
- `j26062_13.rdaniel.online` — attacker's command-and-control server

### Backdoor Admin Account
- Username: `root`, Email: `admin@wordpress.com`
- Generic placeholder values — no real person

### Webshell Location Pattern
- `wp-content/ai1wm-backups/mu-plugins/index.php`
- PHP File Manager with empty `auth_pass` field (no password)

---

## 6. Resolution Steps Taken

| Step | Action | Result |
|---|---|---|
| 1 | Restored `/var/www/wordpress/index.php` (400 bytes clean file) | Site loading |
| 2 | Removed PHP File Manager webshell from `ai1wm-backups/mu-plugins/` | Entry point eliminated |
| 3 | Removed 8 backdoor files from plugin subdirectories | Persistence removed |
| 4 | Added Nginx `deny all` for `wp-content/ai1wm-backups/` | Web access blocked |
| 5 | Deleted attacker admin account `root` (ID 275029659) | Backdoor account removed |
| 6 | Rotated MySQL `wp_user` password + updated `wp-config.php` | DB access secured |
| 7 | Reset all 10 WordPress user passwords | Credential compromise mitigated |

---

## 7. What Was NOT Done (Requires Follow-Up)

| Action | Risk if skipped | Owner |
|---|---|---|
| Rotate WordPress secret keys (AUTH_KEY etc.) | Existing session cookies remain valid — attacker may still have authenticated sessions | Vishav |
| Full malware scan (Wordfence / Maldet) | Unknown files may still exist in uploads/ or theme dirs | Vishav |
| Audit plugin list — remove wpide | Plugin remains installed and operational | Vishav |
| Check Google Search Console | SEO damage may trigger manual penalty; need to request review | Client / SEO team |
| Review all plugin versions | Outdated plugins were used as hiding spots | Vishav |
| Enable file integrity monitoring | Next compromise goes undetected again | Vishav |

---

## 8. Prevention & Hardening Recommendations

### Immediate (this week)

**1. Remove high-risk plugins:**
```bash
sudo wp --path=/var/www/wordpress plugin delete wpide --allow-root
sudo wp --path=/var/www/wordpress plugin delete all-in-one-wp-migration --allow-root
```

**2. Rotate WordPress secret keys:**
```bash
# Generate new keys at: https://api.wordpress.org/secret-key/1.1/salt/
# Replace the 8 define('AUTH_KEY'... lines in wp-config.php
```

**3. Block dangerous directories in Nginx:**
```nginx
# Add to /etc/nginx/sites-enabled/wordpress
location ~* /wp-content/(ai1wm-backups|cache|backups|upgrade)/ {
    deny all;
}
location ~* /wp-content/plugins/.+\.(php|php5|phtml)$ {
    # Allow only known-good paths; deny PHP execution inside plugins
    deny all;
}
```

**4. Restrict wp-admin to office IPs only:**
```nginx
location /wp-admin {
    allow <office-ip>;
    allow <vpn-ip>;
    deny all;
}
```

### Short-Term (this month)

**5. Enable Wordfence or Sucuri** for file integrity monitoring — alerts when core files are modified.

**6. Audit and reduce admin accounts** — most users don't need administrator role. Use Editor or Author where sufficient.

**7. Enable WordPress application passwords** and require 2FA for all admin accounts.

**8. Set up PHP-FPM open_basedir** to restrict file access:
```ini
; /etc/php/8.3/fpm/pool.d/wordpress.conf
php_admin_value[open_basedir] = /var/www/wordpress:/tmp
```

**9. Monitor for large PHP files in wp-content:**
```bash
# Add to cron - alert if any PHP file >100KB appears in plugins/
find /var/www/wordpress/wp-content/plugins/ -name '*.php' -size +100k \
  | mail -s "Large PHP files detected" vishav.deshwal@infinitelocus.com
```

### Long-Term

**10. Implement a WAF** (AWS WAF or Cloudflare) with WordPress rulesets to block malicious upload attempts.

**11. Read-only filesystem for WordPress core** using Linux immutable flag on index.php and other core files:
```bash
sudo chattr +i /var/www/wordpress/index.php
sudo chattr +i /var/www/wordpress/wp-login.php
sudo chattr +i /var/www/wordpress/wp-config.php
```
Remove the flag only during plugin/WP updates.

---

## 9. Lessons Learned

1. **File manager plugins are webshells with a login page.** Treat them as such. Install only during active use, delete immediately after.

2. **Backup directories must be web-restricted.** Any directory writable by PHP-FPM that is also web-accessible is a potential webshell drop zone.

3. **Site monitoring must include content checks, not just uptime.** The site returned HTTP 200 throughout the 19-day compromise — an uptime monitor would not have caught this. A content check (e.g., assert page contains `<html>` and not `<?php`) would have.

4. **File size anomalies are a detection signal.** `index.php` going from 400 bytes to 8246 bytes is immediately suspicious. Automated file integrity monitoring catches this in minutes, not 19 days.

5. **Multiple persistence layers require multiple cleanup steps.** Fixing `index.php` alone was not enough — backdoor files in plugin dirs and a backdoor admin account both survived. Always assume multiple persistence mechanisms.
