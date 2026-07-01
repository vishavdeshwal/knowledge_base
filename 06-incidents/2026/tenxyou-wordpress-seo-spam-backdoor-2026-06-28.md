# Incident: TenXYou WordPress SEO Spam Backdoor Injection

**Date:** 2026-06-28 (discovered 2026-06-29)
**Severity:** High — active malware on production WordPress site
**Service:** tenxyou.com/blogs (WordPress at `ubuntu@3.6.59.24:/var/www/wordpress`)
**Status:** Resolved

---

## Symptom

Visiting `tenxyou.com/blogs` showed raw PHP source code in the browser instead of the website:

```
/**
 * Front to the WordPress application. This file doesn't do anything, but loads
 * wp-blog-header.php which does and tells WordPress to load the theme.
 * ...
```

Site returning HTTP 200 with 426 bytes — far less than a real WordPress page.

---

## Root Cause

The WordPress `index.php` had been replaced with a **SEO spam backdoor** (obfuscated PHP using goto labels and octal/hex string encoding). The malware connected to `j26062_13.rdaniel.online` (C2 server) and behaved differently per visitor type:

| Visitor type | Behavior |
|---|---|
| Googlebot / crawlers | Served fake spam content from attacker's server |
| Users from Google search referrer | Redirected to Japanese spam affiliate site |
| Normal visitors | Fell through to `CnN7_: ?>` label — closed PHP mode and printed the WordPress `index.php` as literal text |

The `?>` closing tag caused everything after it (the original WordPress code) to be output as HTML text, not executed. This is why the PHP source was visible.

### Entry Point — PHP File Manager Webshell

**Initial access date: 2026-06-10** (19 days before discovery)

A password-less PHP File Manager webshell was planted at:
```
/var/www/wordpress/wp-content/ai1wm-backups/mu-plugins/index.php
```

This file was **publicly web-accessible** (returned HTTP 200). The attacker likely uploaded it via the **All-in-One WP Migration plugin** or a compromised wp-admin account. From this webshell they had full filesystem read/write access as `wpuser`.

---

## Full Impact

### Files infected / planted:

| File | Type | Date modified |
|---|---|---|
| `/var/www/wordpress/index.php` | SEO spam backdoor | 2026-06-28 23:57 |
| `wp-content/ai1wm-backups/mu-plugins/index.php` | PHP File Manager webshell (no password) | 2026-06-10 |
| `plugins/gravatar-enhanced/classes/hovercards/wp-login.php` | Backdoor (~1MB) | 2026-06-29 02:27 |
| `plugins/gravatar-enhanced/classes/hovercards/index.php` | Backdoor (~1MB) | 2026-06-29 02:27 |
| `plugins/gutenberg/build/scripts/block-library/page-list-item/wp-login.php` | Backdoor (~1MB) | 2026-06-29 11:14 |
| `plugins/gutenberg/build/scripts/block-library/page-list-item/index.php` | Backdoor (~1MB) | 2026-06-29 11:14 |
| `plugins/wpide/freemius/includes/sdk/wp-login.php` | Backdoor (~1MB) | unknown |
| `plugins/wordpress-seo/src/values/twitter/wp-login.php` | Backdoor (~1MB) | unknown |
| `plugins/wordpress-seo/src/values/twitter/index.php` | Backdoor (~1MB) | unknown |
| `plugins/wpide/freemius/includes/sdk/index.php` | Backdoor (~1MB) | unknown |

The ~1MB fake `wp-login.php` and `index.php` files inside plugin subdirectories are a common technique — they look like plugin assets but are actually full backdoors.

---

## Why PHP Source Was Visible (Technical Detail)

Normal WordPress `index.php` is ~400 bytes. The malicious file was 8246 bytes. Structure:

```
<?php
goto EmYgD;   ← jumps past all the malicious code labels
...           ← obfuscated malware (octal/hex encoded strings)
CnN7_:        ← label reached by "normal visitor" code path
?>            ← PHP mode ENDS HERE
 /**
 * Front to the WordPress application...  ← THIS IS OUTPUT AS HTML TEXT
...
require __DIR__ . '/wp-blog-header.php';  ← NEVER EXECUTED
```

The `require` at the end was never called because it was after the `?>` closing tag — it was just output as text on the page.

---

## How It Was Diagnosed

1. `systemctl status php8.3-fpm` — FPM running, socket existed
2. `curl -sk http://127.0.0.1/blogs` — returned 426 bytes (raw PHP source)
3. `wc -c /var/www/wordpress/index.php` — returned 8246 (should be ~400)
4. `cat /var/www/wordpress/index.php | head -60` — revealed obfuscated malware

---

## Resolution Steps

### 1. Restored clean `index.php`
```bash
sudo python3 -c "
content = '''<?php
define( 'WP_USE_THEMES', true );
require __DIR__ . '/wp-blog-header.php';
'''
open('/var/www/wordpress/index.php','w').write(content)
"
sudo php -l /var/www/wordpress/index.php
```

### 2. Removed all backdoors
```bash
sudo rm /var/www/wordpress/wp-content/ai1wm-backups/mu-plugins/index.php
sudo rm /var/www/wordpress/wp-content/plugins/gravatar-enhanced/classes/hovercards/wp-login.php
sudo rm /var/www/wordpress/wp-content/plugins/gravatar-enhanced/classes/hovercards/index.php
sudo rm /var/www/wordpress/wp-content/plugins/gutenberg/build/scripts/block-library/page-list-item/wp-login.php
sudo rm /var/www/wordpress/wp-content/plugins/gutenberg/build/scripts/block-library/page-list-item/index.php
sudo rm /var/www/wordpress/wp-content/plugins/wpide/freemius/includes/sdk/wp-login.php
sudo rm /var/www/wordpress/wp-content/plugins/wpide/freemius/includes/sdk/index.php
sudo rm /var/www/wordpress/wp-content/plugins/wordpress-seo/src/values/twitter/wp-login.php
sudo rm /var/www/wordpress/wp-content/plugins/wordpress-seo/src/values/twitter/index.php
```

### 3. Blocked backups directory in Nginx
Added to `/etc/nginx/sites-enabled/wordpress`:
```nginx
location ~* /wp-content/ai1wm-backups/ {
    deny all;
}
```
Then: `sudo nginx -s reload`

### 4. Changed DB password
- Generated new strong password (32 chars, URL-safe random)
- Used PHP script to: read old password from wp-config internally → ALTER USER in MariaDB → update wp-config.php
- Password stored in: **1Password / vault** — see TenXYou credentials entry
- DB user: `wp_user` @ `localhost`, DB: `wordpress_db`

---

## Verification

```bash
# Site returns 200 with WordPress content (follows redirect chain)
curl -skL -o /dev/null -w '%{http_code} %{url_effective}\n' https://tenxyou.com/blogs/
# Expected: 200 https://tenxyou.com/blogs/

# Webshell is blocked
curl -sk -o /dev/null -w '%{http_code}\n' https://tenxyou.com/wp-content/ai1wm-backups/mu-plugins/index.php
# Expected: 403 or 404
```

---

## Remaining Actions (Owner: Vishav)

- [ ] **Change WordPress admin passwords** for all admin users
- [ ] **Rotate WordPress secret keys** — generate at `https://api.wordpress.org/secret-key/1.1/salt/` and replace the 8 `define('AUTH_KEY'...` lines in wp-config.php
- [ ] **Audit WordPress admin users** for unknown accounts: `wp --path=/var/www/wordpress user list --allow-root`
- [ ] **Check Google Search Console** for manual spam penalty from the SEO injection period (Jun 10–28)
- [ ] **Consider removing `wpide` plugin** — file manager plugins are a persistent high-risk attack surface
- [ ] **Restrict or remove All-in-One WP Migration plugin** — likely the attacker's upload vector
- [ ] **Run a full malware scan** with a tool like Wordfence or Maldet across the entire `/var/www/` directory

---

## Prevention

1. **Never leave file manager plugins installed** (wpide, file-manager, ai1wm) unless actively in use. Remove after use.
2. **Block `wp-content` subdirs that should never be web-accessible** in Nginx:
   ```nginx
   location ~* /wp-content/(ai1wm-backups|cache|backups)/ { deny all; }
   ```
3. **Monitor for unexpected changes to WordPress core files** — index.php, wp-login.php, wp-config.php
4. **Keep plugins updated** — especially Gravatar Enhanced, Gutenberg (out-of-date plugins were used as hiding spots)
5. **Enable Jetpack or Wordfence file integrity monitoring** so future tampering triggers an alert

---

## Malware Signature (for future scanning)

The malware uses this pattern — search for it:
```bash
sudo grep -rl 'goto EmYgD\|rdaniel\.online\|isc.*isg.*execReq' /var/www/ 2>/dev/null
```

Fake backdoor files are also identifiable by size (>500KB) inside plugin subdirectories:
```bash
sudo find /var/www/ -name '*.php' -size +500k -not -path '*/uploads/*' 2>/dev/null
```
