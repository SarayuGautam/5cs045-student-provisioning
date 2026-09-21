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
];
