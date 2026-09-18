<?php
/**
 * smtp_config.php — fill these in with real values before going live.
 * Ask IT for the college's outgoing mail relay details (most institutions
 * have one — often the same server that handles staff email, or your
 * email provider's SMTP relay if you're on Google Workspace/Office 365).
 *
 * This file is not web-accessible on its own (nginx only routes
 * register.php/register_handler.php to PHP-FPM — see templates/nginx-
 * students.conf), but keep it out of any public git repo regardless.
 */
declare(strict_types=1);

return [
    'host'         => 'smtp.heraldcollege.edu.np',   // CHANGE ME — ask IT for the real relay
    'port'         => 587,                            // 587 = STARTTLS (typical); 465 = implicit TLS; 25 = usually blocked outbound by ISPs
    'username'     => 'noreply@heraldcollege.edu.np', // CHANGE ME
    'password'     => 'CHANGE_ME',                     // CHANGE ME — consider an app-specific password if the provider supports one
    'from_address' => 'noreply@heraldcollege.edu.np',
    'from_name'    => '5CS045 Student Server',
    'use_starttls' => true,

    // Only emails ending in this domain may register. Set to null to allow
    // any domain (not recommended — see README "About the registration form").
    'allowed_email_domain' => 'heraldcollege.edu.np',  // CONFIRM with registry — this is inferred from your old server's URLs, not verified
];
