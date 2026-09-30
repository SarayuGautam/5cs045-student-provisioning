<?php
declare(strict_types=1);

// Template only. The real file lives on the server at /etc/5cs045/smtp_config.php.
// Never put the real password in this file.
return [
    'host' => 'smtp.example.edu',
    'port' => 587,
    'username' => 'noreply@example.edu',
    'password' => 'CHANGE_ME',
    'from_address' => 'noreply@example.edu',
    'from_name' => 'Server Admin',
    'use_starttls' => true,
    'allowed_email_domain' => 'example.edu',
    'server_url' => 'https://server.example.edu',
    // The sign-up page's address, for the link that confirms a student's email.
    // Without this line, https://fullstack.heraldcollege.edu.np is used.
    'signup_url' => 'https://signup.example.edu',
    // Where server alerts go (for example "disk 80% full"). Leave empty for no alerts.
    'admin_email' => '',
];
